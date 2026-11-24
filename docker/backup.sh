#!/usr/bin/env bash
# Safe backup helper for EmdashDeploy Docker Compose deployments.
#
# - SQLite: runs Python sqlite3.backup() + PRAGMA integrity_check inside the emdash container
#           (never copies raw SQLite WAL files directly).
# - PostgreSQL: runs pg_dump -Fc inside the postgres container + verifies with pg_restore --list.
# - Media/uploads: archives /data/uploads from the emdash container when STORAGE_DRIVER=local.
# - Permissions: umask 0077 / chmod 0600 on output archive.
# - Encryption: optional --encrypt uses a dedicated BACKUP_ENCRYPTION_PASSPHRASE
#               (intentionally separate from EMDASH_ENCRYPTION_KEY).
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILES=()
ENV_FILE="${ENV_FILE:-${SCRIPT_DIR}/.env}"
OUTPUT_DIR="${BACKUP_OUTPUT_DIR:-${SCRIPT_DIR}/backups}"
ENCRYPT_MODE="0"

usage() {
	cat <<'EOF'
Usage:
  bash docker/backup.sh [--env-file <path>] [--compose-file <path>]... [--out-dir <dir>] [--encrypt]

Environment:
  BACKUP_ENCRYPTION_PASSPHRASE   Required when --encrypt is set (must NOT reuse EMDASH_ENCRYPTION_KEY)
EOF
}

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
	case "$1" in
	--env-file=*) ENV_FILE="${1#--env-file=}" ;;
	--env-file)
		shift
		[[ $# -gt 0 ]] || fail "Missing value for --env-file"
		ENV_FILE="$1"
		;;
	--compose-file=*) COMPOSE_FILES+=("${1#--compose-file=}") ;;
	--compose-file)
		shift
		[[ $# -gt 0 ]] || fail "Missing value for --compose-file"
		COMPOSE_FILES+=("$1")
		;;
	--out-dir=*) OUTPUT_DIR="${1#--out-dir=}" ;;
	--out-dir)
		shift
		[[ $# -gt 0 ]] || fail "Missing value for --out-dir"
		OUTPUT_DIR="$1"
		;;
	--encrypt) ENCRYPT_MODE="1" ;;
	-h | --help)
		usage
		exit 0
		;;
	*) fail "Unknown option: $1" ;;
	esac
	shift
done

command -v docker >/dev/null 2>&1 || fail "docker is required"
docker compose version >/dev/null 2>&1 || fail "docker compose plugin is required"
if (( ${#COMPOSE_FILES[@]} == 0 )); then
	COMPOSE_FILES=("${COMPOSE_FILE:-${SCRIPT_DIR}/compose.yml}")
fi
for cf in "${COMPOSE_FILES[@]}"; do
	[[ -f "${cf}" ]] || fail "Compose file not found: ${cf}"
done

# Load non-exported defaults from env file if present without overriding explicit shell env
if [[ -f "${ENV_FILE}" ]]; then
	set -a
	# shellcheck disable=SC1090
	source "${ENV_FILE}"
	set +a
fi

DB_DRIVER="${DB_DRIVER:-sqlite}"
STORAGE_DRIVER="${STORAGE_DRIVER:-local}"
PG_DB_USER="${PG_DB_USER:-emdash}"
PG_DB_NAME="${PG_DB_NAME:-emdash}"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-emdash}"

if [[ -n "${BACKUP_ENCRYPTION_PASSPHRASE:-}" ]]; then
	ENCRYPT_MODE="1"
fi
if [[ "${ENCRYPT_MODE}" == "1" ]]; then
	[[ -n "${BACKUP_ENCRYPTION_PASSPHRASE:-}" ]] || fail "--encrypt requires BACKUP_ENCRYPTION_PASSPHRASE"
	if [[ -n "${EMDASH_ENCRYPTION_KEY:-}" && "${BACKUP_ENCRYPTION_PASSPHRASE}" == "${EMDASH_ENCRYPTION_KEY}" ]]; then
		fail "BACKUP_ENCRYPTION_PASSPHRASE must be separate from EMDASH_ENCRYPTION_KEY"
	fi
fi

compose_args=()
for cf in "${COMPOSE_FILES[@]}"; do
	compose_args+=(-f "${cf}")
done
[[ -f "${ENV_FILE}" ]] && compose_args+=(--env-file "${ENV_FILE}")
[[ "${DB_DRIVER}" == "postgres" ]] && compose_args+=(--profile postgres)

umask 0077
mkdir -p "${OUTPUT_DIR}"
chmod 0700 "${OUTPUT_DIR}"

TS="$(date -u +%Y%m%d-%H%M%SZ)"
TMP_DIR="$(mktemp -d)"
DOCKER_BACKUP_TMP="${TMP_DIR}"
trap 'rm -rf "${DOCKER_BACKUP_TMP:-}"' EXIT

mkdir -p "${TMP_DIR}/data" "${TMP_DIR}/meta"

if [[ "${DB_DRIVER}" == "sqlite" ]]; then
	log "Creating consistent SQLite backup via sqlite3.backup() inside emdash container..."
	mkdir -p "${TMP_DIR}/data/sqlite"
	docker compose "${compose_args[@]}" exec -T emdash python3 - <<'PY' >"${TMP_DIR}/data/sqlite/data.db"
import os, sqlite3, sys, tempfile
src_path = os.environ.get("SQLITE_PATH", "/data/sqlite/data.db")
if not os.path.isfile(src_path):
    sys.stderr.write(f"SQLite file not found: {src_path}\n")
    sys.exit(2)
fd, tmp_path = tempfile.mkstemp(prefix="emdash-bak-", suffix=".db")
os.close(fd)
try:
    src = sqlite3.connect(src_path)
    dst = sqlite3.connect(tmp_path)
    src.backup(dst)
    res = dst.execute("PRAGMA integrity_check;").fetchone()
    dst.close()
    src.close()
    if not res or res[0] != "ok":
        sys.stderr.write(f"PRAGMA integrity_check failed: {res}\n")
        sys.exit(3)
    with open(tmp_path, "rb") as fh:
        while True:
            chunk = fh.read(65536)
            if not chunk:
                break
            sys.stdout.buffer.write(chunk)
finally:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
PY
	python3 - "${TMP_DIR}/data/sqlite/data.db" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
res = conn.execute("PRAGMA integrity_check;").fetchone()
conn.close()
if not res or res[0] != "ok":
    raise SystemExit(f"Host-side SQLite verification failed: {res}")
PY
elif [[ "${DB_DRIVER}" == "postgres" ]]; then
	log "Creating PostgreSQL custom dump via pg_dump -Fc inside postgres container..."
	docker compose "${compose_args[@]}" exec -T postgres \
		pg_dump -Fc -U "${PG_DB_USER}" -d "${PG_DB_NAME}" >"${TMP_DIR}/data/postgres.dump"
	docker compose "${compose_args[@]}" exec -T postgres \
		pg_restore --list <"${TMP_DIR}/data/postgres.dump" >/dev/null \
		|| fail "PostgreSQL backup verification (pg_restore --list) failed"
else
	fail "Unsupported DB_DRIVER: ${DB_DRIVER}"
fi

if [[ "${STORAGE_DRIVER}" == "local" ]]; then
	log "Archiving /data/uploads from emdash container..."
	mkdir -p "${TMP_DIR}/data/uploads"
	docker compose "${compose_args[@]}" exec -T emdash sh -c 'if [ -d /data/uploads ]; then tar -C /data/uploads -cf - .; fi' \
		| tar -C "${TMP_DIR}/data/uploads" -xf -
fi

PROJECT_NAME="${PROJECT_NAME}" DB_DRIVER="${DB_DRIVER}" STORAGE_DRIVER="${STORAGE_DRIVER}" TS="${TS}" TMP_DIR="${TMP_DIR}" python3 - <<'PY'
import hashlib, json, os
from pathlib import Path

root = Path(os.environ["TMP_DIR"])
files = {}
for p in sorted(root.rglob("*")):
    if p.is_file():
        rel = p.relative_to(root).as_posix()
        if rel == "meta/manifest.json":
            continue
        h = hashlib.sha256()
        with p.open("rb") as fh:
            for chunk in iter(lambda: fh.read(65536), b""):
                h.update(chunk)
        files[rel] = h.hexdigest()

manifest = {
    "schema_version": 1,
    "runtime": "docker",
    "project": os.environ["PROJECT_NAME"],
    "created_at": os.environ["TS"],
    "db_driver": os.environ["DB_DRIVER"],
    "storage_driver": os.environ["STORAGE_DRIVER"],
    "files": files,
}
(root / "meta" / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
PY

ARCHIVE="${OUTPUT_DIR}/${PROJECT_NAME}-backup-${TS}.tar.gz"
tar -C "${TMP_DIR}" -czf "${ARCHIVE}" .
chmod 0600 "${ARCHIVE}"
tar -tzf "${ARCHIVE}" >/dev/null || fail "Archive integrity check (tar -tzf) failed"

if [[ "${ENCRYPT_MODE}" == "1" ]]; then
	ENC_ARCHIVE="${ARCHIVE}.enc"
	BACKUP_ENCRYPTION_PASSPHRASE="${BACKUP_ENCRYPTION_PASSPHRASE}" openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt \
		-pass env:BACKUP_ENCRYPTION_PASSPHRASE \
		-in "${ARCHIVE}" -out "${ENC_ARCHIVE}"
	chmod 0600 "${ENC_ARCHIVE}"
	rm -f "${ARCHIVE}"
	ARCHIVE="${ENC_ARCHIVE}"
fi

log "Docker backup complete (0600): ${ARCHIVE}"
printf '%s\n' "${ARCHIVE}"
