#!/usr/bin/env bash
# Runtime migration helper between EmdashDeploy Docker Compose and Native systemd deployments.
#
# Modes:
#   docker-to-native --backup <docker-backup.tar.gz[.enc]> --docker-env <docker/.env> [--instance <name>] [--dry-run] [--yes]
#   native-to-docker --backup <emdashctl-backup.tar.gz[.enc]> --out-dir <target-docker-dir> [--compose-file <path>] [--apply] [--yes]
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE=""
BACKUP_FILE=""
DOCKER_ENV_FILE=""
INSTANCE_NAME=""
OUT_DIR=""
COMPOSE_FILE="${SCRIPT_DIR}/docker/compose.yml"
DRY_RUN="0"
APPLY_DOCKER="0"
ASSUME_YES="0"

usage() {
	cat <<'EOF'
migrate-runtime.sh — Migrate EmDash state between Docker Compose and Native systemd

Usage:
  bash scripts/migrate-runtime.sh docker-to-native \
    --backup <docker-backup.tar.gz[.enc]> \
    [--docker-env <docker/.env>] \
    [--instance <name>] [--dry-run] [--yes]

  bash scripts/migrate-runtime.sh native-to-docker \
    --backup <native-emdash-backup.tar.gz[.enc]> \
    --out-dir <target-dir> \
    [--compose-file <path>] [--apply] [--yes]

Notes:
  - Always preserves EMDASH_ENCRYPTION_KEY so encrypted plugin settings remain decryptable.
  - Supports encrypted backups via BACKUP_ENCRYPTION_PASSPHRASE env var.
EOF
}

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

[[ $# -gt 0 ]] || { usage; exit 0; }
case "$1" in
-h | --help) usage; exit 0 ;;
docker-to-native | native-to-docker) MODE="$1"; shift ;;
*) fail "Unknown mode: $1 (expected docker-to-native | native-to-docker)" ;;
esac

while [[ $# -gt 0 ]]; do
	case "$1" in
	--backup=*) BACKUP_FILE="${1#--backup=}" ;;
	--backup) shift; [[ $# -gt 0 ]] || fail "Missing value for --backup"; BACKUP_FILE="$1" ;;
	--docker-env=*) DOCKER_ENV_FILE="${1#--docker-env=}" ;;
	--docker-env) shift; [[ $# -gt 0 ]] || fail "Missing value for --docker-env"; DOCKER_ENV_FILE="$1" ;;
	--instance=*) INSTANCE_NAME="${1#--instance=}" ;;
	--instance) shift; [[ $# -gt 0 ]] || fail "Missing value for --instance"; INSTANCE_NAME="$1" ;;
	--out-dir=*) OUT_DIR="${1#--out-dir=}" ;;
	--out-dir) shift; [[ $# -gt 0 ]] || fail "Missing value for --out-dir"; OUT_DIR="$1" ;;
	--compose-file=*) COMPOSE_FILE="${1#--compose-file=}" ;;
	--compose-file) shift; [[ $# -gt 0 ]] || fail "Missing value for --compose-file"; COMPOSE_FILE="$1" ;;
	--dry-run) DRY_RUN="1" ;;
	--apply) APPLY_DOCKER="1" ;;
	--yes | -y) ASSUME_YES="1" ;;
	-h | --help) usage; exit 0 ;;
	*) fail "Unknown option: $1" ;;
	esac
	shift
done

[[ -n "${BACKUP_FILE}" && -f "${BACKUP_FILE}" ]] || fail "Backup archive not found: ${BACKUP_FILE:-<empty>}"

umask 0077
TMP_DIR="$(mktemp -d)"
MIGRATE_RT_TMP="${TMP_DIR}"
trap 'rm -rf "${MIGRATE_RT_TMP:-}"' EXIT

TAR_PATH="${BACKUP_FILE}"
if [[ "${BACKUP_FILE}" == *.enc ]]; then
	[[ -n "${BACKUP_ENCRYPTION_PASSPHRASE:-}" ]] || fail "Encrypted backup requires BACKUP_ENCRYPTION_PASSPHRASE."
	TAR_PATH="${TMP_DIR}/decrypted.tar.gz"
	BACKUP_ENCRYPTION_PASSPHRASE="${BACKUP_ENCRYPTION_PASSPHRASE}" openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
		-pass env:BACKUP_ENCRYPTION_PASSPHRASE \
		-in "${BACKUP_FILE}" -out "${TAR_PATH}" \
		|| fail "Failed to decrypt backup archive."
fi

EXTRACT_DIR="${TMP_DIR}/extracted"
mkdir -p "${EXTRACT_DIR}"
TAR_PATH="${TAR_PATH}" EXTRACT_DIR="${EXTRACT_DIR}" python3 - <<'PY'
import os, tarfile
from pathlib import Path

dest = Path(os.environ["EXTRACT_DIR"]).resolve()
with tarfile.open(os.environ["TAR_PATH"], "r:gz") as tf:
    for m in tf.getmembers():
        if m.issym() or m.islnk() or m.isdev():
            raise SystemExit(f"Unsafe tar member rejected: {m.name}")
        target = (dest / m.name).resolve()
        if target != dest and dest not in target.parents:
            raise SystemExit(f"Path traversal member rejected: {m.name}")
    if hasattr(tarfile, "data_filter"):
        tf.extractall(dest, filter="data")
    else:
        tf.extractall(dest)
PY

MANIFEST_DB="sqlite"
MANIFEST_STORAGE="local"
if [[ -f "${EXTRACT_DIR}/meta/manifest.json" ]]; then
	MANIFEST_DB="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("db_driver","sqlite"))' "${EXTRACT_DIR}/meta/manifest.json")"
	MANIFEST_STORAGE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("storage_driver","local"))' "${EXTRACT_DIR}/meta/manifest.json")"
fi

if [[ "${MODE}" == "docker-to-native" ]]; then
	local_env_file="/etc/emdash/emdash.env"
	declare -a ctl_args=()
	if [[ -n "${INSTANCE_NAME}" ]]; then
		local_env_file="/etc/emdash/instances/${INSTANCE_NAME}/emdash.env"
		ctl_args+=(--instance "${INSTANCE_NAME}")
	fi

	log "Docker -> Native migration plan:"
	log "  Backup archive:    ${BACKUP_FILE} (db_driver=${MANIFEST_DB}, storage=${MANIFEST_STORAGE})"
	log "  Target native env: ${local_env_file}"
	[[ -n "${DOCKER_ENV_FILE}" ]] && log "  Docker .env:       ${DOCKER_ENV_FILE}"

	if [[ "${DRY_RUN}" == "1" ]]; then
		log "Dry-run complete. No native state was modified."
		exit 0
	fi

	[[ -f "${local_env_file}" ]] || fail "Target native instance not found (${local_env_file}). Install the target native instance first with matching DB_DRIVER=${MANIFEST_DB}."
	command -v emdashctl >/dev/null 2>&1 || fail "emdashctl not found in PATH"

	# Restore DB + uploads into native instance using emdashctl restore
	log "Restoring database and uploads into native instance via emdashctl..."
	emdashctl "${ctl_args[@]}" restore "${BACKUP_FILE}" --yes

	# Merge portable cryptographic secrets from Docker .env when provided
	if [[ -n "${DOCKER_ENV_FILE}" ]]; then
		[[ -f "${DOCKER_ENV_FILE}" ]] || fail "Docker .env not found: ${DOCKER_ENV_FILE}"
		# shellcheck disable=SC1091
		source "${SCRIPT_DIR}/lib/site-common.sh"
		for secret_key in EMDASH_ENCRYPTION_KEY EMDASH_AUTH_SECRET EMDASH_PREVIEW_SECRET; do
			val="$(set +u; set -a; . "${DOCKER_ENV_FILE}" 2>/dev/null; set +a; printf '%s' "${!secret_key-}")"
			if [[ -n "${val}" ]]; then
				update_env_file_value "${secret_key}" "${val}" "${local_env_file}"
				log "Merged portable secret ${secret_key} into ${local_env_file}"
			fi
		done
		emdashctl "${ctl_args[@]}" restart app
	fi

	emdashctl "${ctl_args[@]}" doctor --deep --json >/dev/null
	log "Docker -> Native migration completed and verified healthy!"
	exit 0
fi

# native-to-docker
[[ -n "${OUT_DIR}" ]] || fail "native-to-docker requires --out-dir <target-dir>"
mkdir -p "${OUT_DIR}"
chmod 0700 "${OUT_DIR}"

NATIVE_ENV="${EXTRACT_DIR}/meta/emdash.env"
[[ -f "${NATIVE_ENV}" ]] || fail "meta/emdash.env not found inside native backup archive."

# Extract portable config & secrets safely into a 0600 Docker .env file
NATIVE_ENV="${NATIVE_ENV}" OUT_ENV="${OUT_DIR}/.env" MANIFEST_DB="${MANIFEST_DB}" MANIFEST_STORAGE="${MANIFEST_STORAGE}" python3 - <<'PY'
import os, shlex
from pathlib import Path

src_env = {}
for line in Path(os.environ["NATIVE_ENV"]).read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    try:
        parsed = shlex.split(v)
        src_env[k] = parsed[0] if parsed else ""
    except Exception:
        src_env[k] = v.strip('"').strip("'")

db_driver = os.environ["MANIFEST_DB"]
storage_driver = os.environ["MANIFEST_STORAGE"]
session_driver = src_env.get("SESSION_DRIVER", "file")
image_profile = "blog-pg-valkey" if db_driver == "postgres" else "blog-sqlite"

lines = [
    "# Generated by EmdashDeploy scripts/migrate-runtime.sh (native-to-docker)",
    f"COMPOSE_PROJECT_NAME={src_env.get('PROJECT_NAME', 'emdash')}-docker",
    f"EMDASH_IMAGE=ghcr.io/web-casa/emdash-deploy:1.6.0-hi.3-{image_profile}",
    "APP_BIND_IP=127.0.0.1",
    f"APP_PORT={src_env.get('APP_PORT', '3000')}",
    f"EMDASH_SITE_URL={src_env.get('APP_PUBLIC_URL', 'http://127.0.0.1:3000')}",
    f"TIMEZONE={src_env.get('TIMEZONE', 'UTC')}",
    f"EMDASH_TEMPLATE={src_env.get('TEMPLATE', 'blog')}",
    f"DB_DRIVER={db_driver}",
    f"SESSION_DRIVER={session_driver}",
    f"STORAGE_DRIVER={storage_driver}",
    f"ENABLE_PLUGIN_SANDBOX={src_env.get('ENABLE_PLUGIN_SANDBOX', '1')}",
    f"EMDASH_ENCRYPTION_KEY={src_env.get('EMDASH_ENCRYPTION_KEY', '')}",
]
for opt_key in ("EMDASH_AUTH_SECRET", "EMDASH_PREVIEW_SECRET", "PG_DB_NAME", "PG_DB_USER", "PG_DB_PASSWORD", "REDIS_PASSWORD", "S3_ENDPOINT", "S3_REGION", "S3_BUCKET", "S3_ACCESS_KEY_ID", "S3_SECRET_ACCESS_KEY", "S3_PUBLIC_URL"):
    if src_env.get(opt_key):
        lines.append(f"{opt_key}={src_env[opt_key]}")

out_path = Path(os.environ["OUT_ENV"])
out_path.write_text("\n".join(lines) + "\n")
os.chmod(out_path, 0o600)
PY

log "Generated 0600 Docker Compose .env at: ${OUT_DIR}/.env"
if [[ "${DRY_RUN}" == "1" || "${APPLY_DOCKER}" != "1" ]]; then
	log "Next steps to bring up and restore into Docker Compose:"
	log "  bash docker/restore.sh '${BACKUP_FILE}' --env-file '${OUT_DIR}/.env' --compose-file '${COMPOSE_FILE}' --yes"
	exit 0
fi

log "Applying backup into Docker Compose stack via docker/restore.sh..."
bash "${SCRIPT_DIR}/docker/restore.sh" \
	"${BACKUP_FILE}" \
	--env-file "${OUT_DIR}/.env" \
	--compose-file "${COMPOSE_FILE}" \
	--yes
log "Native -> Docker migration completed and verified healthy!"
