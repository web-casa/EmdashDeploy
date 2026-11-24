#!/usr/bin/env bash
# Safe restore helper for EmdashDeploy Docker Compose deployments.
#
# - Supports plain .tar.gz and AES-256-CBC PBKDF2 encrypted .tar.gz.enc archives
#   created by docker/backup.sh (or emdashctl backup with matching DB driver).
# - Validates tar member paths (rejects path traversal / symlinks), manifest.json
#   driver compatibility, and SHA-256 file checksums before mutating any state.
# - SQLite: stops emdash container, removes -wal/-shm, atomically replaces
#   /data/sqlite/data.db with PUID:PGID ownership, and verifies PRAGMA integrity_check.
# - PostgreSQL: stops emdash container, restores into a fresh temporary database via
#   pg_restore --no-owner, then atomically swaps databases.
# - Restores /data/uploads when present and restarts emdash with /healthz verification.
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILES=()
ENV_FILE="${ENV_FILE:-${SCRIPT_DIR}/.env}"
ARCHIVE=""
ASSUME_YES="0"

usage() {
	cat <<'EOF'
Usage:
  bash docker/restore.sh <backup-file> [--env-file <path>] [--compose-file <path>]... [--yes]

Environment:
  BACKUP_ENCRYPTION_PASSPHRASE   Required when restoring a .tar.gz.enc archive
EOF
}

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
	case "$1" in
	--env-file=*) ENV_FILE="${1#--env-file=}" ;;
	--env-file) shift; [[ $# -gt 0 ]] || fail "Missing value for --env-file"; ENV_FILE="$1" ;;
	--compose-file=*) COMPOSE_FILES+=("${1#--compose-file=}") ;;
	--compose-file) shift; [[ $# -gt 0 ]] || fail "Missing value for --compose-file"; COMPOSE_FILES+=("$1") ;;
	--yes | -y) ASSUME_YES="1" ;;
	-h | --help) usage; exit 0 ;;
	-*) fail "Unknown option: $1" ;;
	*)
		[[ -z "${ARCHIVE}" ]] || fail "Unexpected extra argument: $1"
		ARCHIVE="$1"
		;;
	esac
	shift
done

[[ -n "${ARCHIVE}" && -f "${ARCHIVE}" ]] || { usage; fail "Backup archive not found: ${ARCHIVE:-<empty>}"; }
command -v docker >/dev/null 2>&1 || fail "docker is required"
docker compose version >/dev/null 2>&1 || fail "docker compose plugin is required"
if (( ${#COMPOSE_FILES[@]} == 0 )); then
	COMPOSE_FILES=("${COMPOSE_FILE:-${SCRIPT_DIR}/compose.yml}")
fi
for cf in "${COMPOSE_FILES[@]}"; do
	[[ -f "${cf}" ]] || fail "Compose file not found: ${cf}"
done

# Preserve caller-supplied passphrase before sourcing .env
CALLER_PASSPHRASE="${BACKUP_ENCRYPTION_PASSPHRASE:-}"
if [[ -f "${ENV_FILE}" ]]; then
	set -a
	# shellcheck disable=SC1090
	source "${ENV_FILE}"
	set +a
fi
if [[ -n "${CALLER_PASSPHRASE}" ]]; then
	BACKUP_ENCRYPTION_PASSPHRASE="${CALLER_PASSPHRASE}"
fi

DB_DRIVER="${DB_DRIVER:-sqlite}"
STORAGE_DRIVER="${STORAGE_DRIVER:-local}"
PG_DB_USER="${PG_DB_USER:-emdash}"
PG_DB_NAME="${PG_DB_NAME:-emdash}"
PUID="${PUID:-10001}"
PGID="${PGID:-10001}"

compose_args=()
for cf in "${COMPOSE_FILES[@]}"; do
	compose_args+=(-f "${cf}")
done
[[ -f "${ENV_FILE}" ]] && compose_args+=(--env-file "${ENV_FILE}")
[[ "${DB_DRIVER}" == "postgres" ]] && compose_args+=(--profile postgres)
[[ "${SESSION_DRIVER:-file}" == "redis" ]] && compose_args+=(--profile valkey)

umask 0077
TMP_DIR="$(mktemp -d)"
DOCKER_RESTORE_TMP="${TMP_DIR}"
trap 'rm -rf "${DOCKER_RESTORE_TMP:-}"' EXIT

TAR_PATH="${ARCHIVE}"
if [[ "${ARCHIVE}" == *.enc ]]; then
	[[ -n "${BACKUP_ENCRYPTION_PASSPHRASE:-}" ]] || fail "Encrypted archive requires BACKUP_ENCRYPTION_PASSPHRASE."
	TAR_PATH="${TMP_DIR}/decrypted.tar.gz"
	BACKUP_ENCRYPTION_PASSPHRASE="${BACKUP_ENCRYPTION_PASSPHRASE}" openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
		-pass env:BACKUP_ENCRYPTION_PASSPHRASE \
		-in "${ARCHIVE}" -out "${TAR_PATH}" \
		|| fail "Failed to decrypt backup archive."
fi

EXTRACT_DIR="${TMP_DIR}/extracted"
mkdir -p "${EXTRACT_DIR}"

# Safe extraction (rejects path traversal, absolute paths, symlinks, device nodes)
TAR_PATH="${TAR_PATH}" EXTRACT_DIR="${EXTRACT_DIR}" python3 - <<'PY'
import os, tarfile
from pathlib import Path

tar_path = os.environ["TAR_PATH"]
dest = Path(os.environ["EXTRACT_DIR"]).resolve()

with tarfile.open(tar_path, "r:gz") as tf:
    for m in tf.getmembers():
        if m.issym() or m.islnk() or m.isdev():
            raise SystemExit(f"Refusing unsafe tar member (symlink/hardlink/device): {m.name}")
        target = (dest / m.name).resolve()
        if target != dest and dest not in target.parents:
            raise SystemExit(f"Refusing path traversal tar member: {m.name}")
    if hasattr(tarfile, "data_filter"):
        tf.extractall(dest, filter="data")
    else:
        tf.extractall(dest)
PY

# Verify manifest driver compatibility and SHA-256 checksums when present
if [[ -f "${EXTRACT_DIR}/meta/manifest.json" ]]; then
	EXTRACT_DIR="${EXTRACT_DIR}" EXPECTED_DB="${DB_DRIVER}" python3 - <<'PY'
import hashlib, json, os
from pathlib import Path

root = Path(os.environ["EXTRACT_DIR"])
manifest = json.loads((root / "meta" / "manifest.json").read_text())
m_db = manifest.get("db_driver", "")
if m_db and m_db != os.environ["EXPECTED_DB"]:
    raise SystemExit(f"Backup DB driver ({m_db}) does not match target DB_DRIVER ({os.environ['EXPECTED_DB']}).")
for rel, expected_sha in (manifest.get("files") or {}).items():
    p = root / rel
    if not p.is_file():
        raise SystemExit(f"Manifest listed file missing from archive: {rel}")
    h = hashlib.sha256()
    with p.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    if h.hexdigest() != expected_sha:
        raise SystemExit(f"SHA-256 checksum mismatch for {rel}")
print(f"[INFO] Manifest verified ({len(manifest.get('files') or {})} files, db_driver={m_db or os.environ['EXPECTED_DB']})")
PY
fi

if [[ "${ASSUME_YES}" != "1" && -t 0 ]]; then
	ans=""
	read -r -p "Restore backup '${ARCHIVE}' into Docker Compose stack (DB_DRIVER=${DB_DRIVER})? [y/N]: " ans
	[[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] || fail "Docker restore aborted by user."
fi

log "Stopping emdash application container before restore..."
docker compose "${compose_args[@]}" stop emdash || true

if [[ "${DB_DRIVER}" == "sqlite" ]]; then
	[[ -f "${EXTRACT_DIR}/data/sqlite/data.db" ]] || fail "data/sqlite/data.db not found in archive"
	python3 - "${EXTRACT_DIR}/data/sqlite/data.db" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
res = conn.execute("PRAGMA integrity_check;").fetchone()
conn.close()
if not res or res[0] != "ok":
    raise SystemExit(f"Backup SQLite integrity_check failed: {res}")
PY
	log "Restoring SQLite database into emdash volume..."
	docker compose "${compose_args[@]}" run --rm -T --no-deps --entrypoint sh emdash -ec \
		"mkdir -p /data/sqlite && rm -f /data/sqlite/data.db-wal /data/sqlite/data.db-shm && cat > /data/sqlite/data.db.tmp && mv -f /data/sqlite/data.db.tmp /data/sqlite/data.db && chown ${PUID}:${PGID} /data/sqlite /data/sqlite/data.db && chmod 0640 /data/sqlite/data.db" \
		<"${EXTRACT_DIR}/data/sqlite/data.db"
elif [[ "${DB_DRIVER}" == "postgres" ]]; then
	[[ -f "${EXTRACT_DIR}/data/postgres.dump" ]] || fail "data/postgres.dump not found in archive"
	docker compose "${compose_args[@]}" up -d postgres
	TS="$(date +%s)"
	TMP_DB="${PG_DB_NAME}_restore_${TS}"
	OLD_DB="${PG_DB_NAME}_pre_restore_${TS}"
	log "Restoring PostgreSQL dump into temporary database ${TMP_DB}..."
	docker compose "${compose_args[@]}" exec -T postgres createdb -U "${PG_DB_USER}" "${TMP_DB}"
	if ! docker compose "${compose_args[@]}" exec -T postgres pg_restore --no-owner --role="${PG_DB_USER}" -U "${PG_DB_USER}" -d "${TMP_DB}" <"${EXTRACT_DIR}/data/postgres.dump"; then
		docker compose "${compose_args[@]}" exec -T postgres dropdb --if-exists -U "${PG_DB_USER}" "${TMP_DB}" || true
		fail "pg_restore failed; original database ${PG_DB_NAME} untouched."
	fi
	log "Swapping restored database ${TMP_DB} -> ${PG_DB_NAME}..."
	docker compose "${compose_args[@]}" exec -T postgres psql -U "${PG_DB_USER}" -d postgres -v ON_ERROR_STOP=1 <<EOF
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname IN ('${PG_DB_NAME}', '${TMP_DB}') AND pid <> pg_backend_pid();
ALTER DATABASE "${PG_DB_NAME}" RENAME TO "${OLD_DB}";
ALTER DATABASE "${TMP_DB}" RENAME TO "${PG_DB_NAME}";
EOF
else
	fail "Unsupported DB_DRIVER: ${DB_DRIVER}"
fi

if [[ "${STORAGE_DRIVER}" == "local" && -d "${EXTRACT_DIR}/data/uploads" ]]; then
	log "Restoring /data/uploads into emdash volume..."
	tar -C "${EXTRACT_DIR}/data/uploads" -cf - . \
		| docker compose "${compose_args[@]}" run --rm -T --no-deps --entrypoint sh emdash -ec \
			"mkdir -p /data/uploads && find /data/uploads -mindepth 1 -delete && tar -C /data/uploads -xf - && chown -R ${PUID}:${PGID} /data/uploads"
fi

log "Starting emdash container and verifying health..."
docker compose "${compose_args[@]}" up -d emdash
for _ in $(seq 1 30); do
	if docker compose "${compose_args[@]}" exec -T emdash sh -c \
		'curl -fsS http://127.0.0.1:3000/healthz >/dev/null 2>&1 || curl -fsS http://127.0.0.1:3000/_emdash/api/setup/status >/dev/null 2>&1'; then
		log "Docker restore complete and container is healthy!"
		exit 0
	fi
	sleep 2
done

fail "emdash container did not become healthy after restore"
