#!/usr/bin/env bash
set -Eeuo pipefail

export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
SITE_DIR="${SITE_DIR:-/app/site}"
DATA_DIR="${DATA_DIR:-/data}"
SQLITE_PATH="${SQLITE_PATH:-${DATA_DIR}/sqlite/data.db}"
UPLOADS_DIR="${UPLOADS_DIR:-${DATA_DIR}/uploads}"
SESSIONS_DIR="${SESSIONS_DIR:-${DATA_DIR}/sessions}"
PERSISTED_KEY_FILE="${DATA_DIR}/.emdash_encryption_key"

if [[ -f /opt/emdash/lib/site-common.sh ]]; then
	# shellcheck disable=SC1091
	source /opt/emdash/lib/site-common.sh
fi

log() { printf '[emdash-docker] %s\n' "$*"; }
warn() { printf '[emdash-docker][WARN] %s\n' "$*" >&2; }
fail() { printf '[emdash-docker][ERROR] %s\n' "$*" >&2; exit 1; }

setup_runtime_user() {
	local target_uid="${PUID:-10001}"
	local target_gid="${PGID:-10001}"
	mkdir -p "$(dirname "${SQLITE_PATH}")" "${UPLOADS_DIR}" "${SESSIONS_DIR}"
	if [[ "$(id -u)" == "0" ]]; then
		if [[ "${target_gid}" != "$(id -g emdash)" ]]; then
			groupmod -o -g "${target_gid}" emdash >/dev/null 2>&1 || true
		fi
		if [[ "${target_uid}" != "$(id -u emdash)" ]]; then
			usermod -o -u "${target_uid}" emdash >/dev/null 2>&1 || true
		fi
		chown -R "${target_uid}:${target_gid}" "${DATA_DIR}" 2>/dev/null || true
	fi
}

run_as_runtime_user() {
	if [[ "$(id -u)" == "0" ]]; then
		gosu emdash "$@"
	else
		"$@"
	fi
}

ensure_encryption_key() {
	if [[ -n "${EMDASH_ENCRYPTION_KEY:-}" ]]; then
		validate_emdash_encryption_key "${EMDASH_ENCRYPTION_KEY}" \
			|| fail "Invalid EMDASH_ENCRYPTION_KEY format (expected emdash_enc_v1_<43 base64url chars>)."
		local kid=""
		kid="$(emdash_encryption_key_fingerprint "${EMDASH_ENCRYPTION_KEY}" 2>/dev/null || echo unknown)"
		log "EMDASH_ENCRYPTION_KEY configured from environment (kid=${kid})."
		return 0
	fi

	if [[ -f "${PERSISTED_KEY_FILE}" ]]; then
		EMDASH_ENCRYPTION_KEY="$(tr -d '\r\n' <"${PERSISTED_KEY_FILE}")"
		export EMDASH_ENCRYPTION_KEY
		validate_emdash_encryption_key "${EMDASH_ENCRYPTION_KEY}" \
			|| fail "Persisted key in ${PERSISTED_KEY_FILE} has invalid format."
		local kid=""
		kid="$(emdash_encryption_key_fingerprint "${EMDASH_ENCRYPTION_KEY}" 2>/dev/null || echo unknown)"
		log "Loaded persisted EMDASH_ENCRYPTION_KEY from ${PERSISTED_KEY_FILE} (kid=${kid})."
		return 0
	fi

	log "EMDASH_ENCRYPTION_KEY not provided; generating a persistent key in ${PERSISTED_KEY_FILE}."
	local raw="" generated="" kid=""
	raw="$(cd "${SITE_DIR}" && run_as_runtime_user pnpm exec emdash secrets generate 2>&1 || true)"
	generated="$(printf '%s\n' "${raw}" | grep -oE 'emdash_enc_v1_[A-Za-z0-9_-]{43}' | head -n1 || true)"
	if [[ -z "${generated}" ]]; then
		generated="$(generate_emdash_encryption_key_spec)"
	fi
	umask 0077
	printf '%s\n' "${generated}" >"${PERSISTED_KEY_FILE}"
	chmod 0600 "${PERSISTED_KEY_FILE}"
	if [[ "$(id -u)" == "0" ]]; then
		chown emdash:emdash "${PERSISTED_KEY_FILE}"
	fi
	EMDASH_ENCRYPTION_KEY="${generated}"
	export EMDASH_ENCRYPTION_KEY
	kid="$(emdash_encryption_key_fingerprint "${EMDASH_ENCRYPTION_KEY}" 2>/dev/null || echo unknown)"
	warn "Auto-generated EMDASH_ENCRYPTION_KEY (kid=${kid}) saved to ${PERSISTED_KEY_FILE}. Back up this key or move it into your Compose .env!"
}

ensure_database_ready() {
	if [[ "${DB_DRIVER:-sqlite}" == "postgres" ]]; then
		export PGHOST="${PGHOST:-${POSTGRES_HOST:-postgres}}"
		export PGPORT="${PGPORT:-${POSTGRES_PORT:-5432}}"
		export PGDATABASE="${PGDATABASE:-${PG_DB_NAME:-emdash}}"
		export PGUSER="${PGUSER:-${PG_DB_USER:-emdash}}"
		export PGPASSWORD="${PGPASSWORD:-${PG_DB_PASSWORD:-}}"
		if [[ -z "${DATABASE_URL:-}" && -n "${PGPASSWORD}" ]]; then
			DATABASE_URL="$(python3 -c 'import os, urllib.parse; u=urllib.parse.quote(os.environ["PGUSER"],safe=""); p=urllib.parse.quote(os.environ["PGPASSWORD"],safe=""); d=urllib.parse.quote(os.environ["PGDATABASE"],safe=""); h=os.environ["PGHOST"]; port=os.environ["PGPORT"]; print(f"postgres://{u}:{p}@{h}:{port}/{d}")')"
			export DATABASE_URL
		fi
		log "Waiting for PostgreSQL at ${PGHOST}:${PGPORT}..."
		python3 - "${PGHOST}" "${PGPORT}" <<'PY'
import socket, sys, time
host, port = sys.argv[1], int(sys.argv[2])
deadline = time.time() + 60
while time.time() < deadline:
    try:
        with socket.create_connection((host, port), timeout=2):
            sys.exit(0)
    except OSError:
        time.sleep(1)
sys.exit(1)
PY
	elif [[ "${DB_DRIVER:-sqlite}" == "sqlite" && ! -f "${SQLITE_PATH}" ]]; then
		log "Initializing SQLite database at ${SQLITE_PATH}..."
		(cd "${SITE_DIR}" && run_as_runtime_user pnpm exec emdash init --database "${SQLITE_PATH}")
	fi

	if [[ "${SESSION_DRIVER:-file}" == "redis" && -z "${REDIS_URL:-}" && -n "${REDIS_PASSWORD:-}" ]]; then
		REDIS_URL="$(python3 -c 'import os, urllib.parse; p=urllib.parse.quote(os.environ["REDIS_PASSWORD"],safe=""); h=os.environ.get("REDIS_HOST","valkey"); port=os.environ.get("REDIS_PORT","6379"); db=os.environ.get("REDIS_DB","0"); print(f"redis://:{p}@{h}:{port}/{db}")')"
		export REDIS_URL
	fi
}

parse_migration_report() {
	python3 -c '
import json, sys
raw = sys.stdin.read()
for line in reversed(raw.splitlines()):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        d = json.loads(line)
        if isinstance(d, dict) and "pending" in d and "unknownApplied" in d:
            target = d.get("target") or {}
            print(json.dumps({
                "valid": True,
                "pending": len(d.get("pending") or []),
                "unknown": len(d.get("unknownApplied") or []),
                "applied": len(d.get("knownApplied") or []),
                "fingerprint": target.get("fingerprint") or "",
            }))
            sys.exit(0)
    except Exception:
        continue
print(json.dumps({"valid": False}))
sys.exit(1)
'
}

run_migration_step() {
	local apply="${1:-1}"
	if ! (cd "${SITE_DIR}" && run_as_runtime_user pnpm exec emdash migrate --help >/dev/null 2>&1); then
		warn "emdash migrate CLI unavailable; skipping explicit migration check."
		return 0
	fi
	local out="" parsed="" valid="" pending="0" unknown="0" fingerprint=""
	set +e
	out="$(cd "${SITE_DIR}" && run_as_runtime_user pnpm exec emdash migrate --status --json 2>&1)"
	set -e
	parsed="$(printf '%s\n' "${out}" | parse_migration_report 2>/dev/null || printf '{"valid":false}')"
	valid="$(printf '%s' "${parsed}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("valid", False))')"
	if [[ "${valid}" != "True" ]]; then
		warn "Could not parse migrate --status --json output; proceeding with caution."
		return 0
	fi
	unknown="$(printf '%s' "${parsed}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("unknown", 0))')"
	pending="$(printf '%s' "${parsed}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("pending", 0))')"
	fingerprint="$(printf '%s' "${parsed}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("fingerprint", ""))')"
	if (( unknown > 0 )); then
		fail "Database has ${unknown} unknown applied migrations (DB newer than image). Refusing to start."
	fi
	if (( pending > 0 )); then
		if [[ "${apply}" == "1" ]]; then
			log "Applying ${pending} pending EmDash database migrations..."
			if [[ -n "${fingerprint}" ]]; then
				(cd "${SITE_DIR}" && run_as_runtime_user pnpm exec emdash migrate --expected-target-fingerprint "${fingerprint}")
			else
				(cd "${SITE_DIR}" && run_as_runtime_user pnpm exec emdash migrate)
			fi
		else
			log "Migration status: ${pending} pending migrations."
		fi
	else
		log "Database migrations are up to date (0 pending)."
	fi
}

run_container_doctor() {
	local kid="unset"
	if [[ -n "${EMDASH_ENCRYPTION_KEY:-}" ]]; then
		kid="$(emdash_encryption_key_fingerprint "${EMDASH_ENCRYPTION_KEY}" 2>/dev/null || echo invalid)"
	fi
	local sandbox_ok="false"
	if (cd "${SITE_DIR}" && run_as_runtime_user node -e 'import("@emdash-cms/sandbox-workerd/sandbox").then(() => process.exit(0)).catch(() => process.exit(1))' >/dev/null 2>&1); then
		sandbox_ok="true"
	fi
	NODE_VER="$(node --version)" \
	PNPM_VER="$(cd "${SITE_DIR}" && pnpm --version 2>/dev/null || echo unknown)" \
	KEY_KID="${kid}" \
	SANDBOX_OK="${sandbox_ok}" \
	DB_DRIVER="${DB_DRIVER:-sqlite}" \
	SESSION_DRIVER="${SESSION_DRIVER:-file}" \
	STORAGE_DRIVER="${STORAGE_DRIVER:-local}" \
	ENABLE_PLUGIN_SANDBOX="${ENABLE_PLUGIN_SANDBOX:-1}" \
	python3 -c '
import json, os
print(json.dumps({
    "runtime": "docker",
    "node": os.environ["NODE_VER"],
    "pnpm": os.environ["PNPM_VER"],
    "db_driver": os.environ["DB_DRIVER"],
    "session_driver": os.environ["SESSION_DRIVER"],
    "storage_driver": os.environ["STORAGE_DRIVER"],
    "plugin_sandbox_enabled": os.environ["ENABLE_PLUGIN_SANDBOX"] == "1",
    "plugin_sandbox_importable": os.environ["SANDBOX_OK"] == "true",
    "encryption_key_kid": os.environ["KEY_KID"],
}, indent=2))
'
}

cmd="${1:-start}"
shift || true

case "${cmd}" in
start)
	setup_runtime_user
	ensure_encryption_key
	ensure_database_ready
	if [[ "${EMDASH_AUTO_MIGRATE:-1}" == "1" ]]; then
		run_migration_step 1
	fi
	cd "${SITE_DIR}"
	if [[ "$(id -u)" == "0" ]]; then
		exec gosu emdash pnpm start
	fi
	exec pnpm start
	;;
migrate)
	setup_runtime_user
	ensure_encryption_key
	ensure_database_ready
	run_migration_step 1
	;;
migrate-status)
	setup_runtime_user
	ensure_encryption_key
	ensure_database_ready
	run_migration_step 0
	;;
secrets-generate)
	cd "${SITE_DIR}"
	exec pnpm exec emdash secrets generate "$@"
	;;
doctor)
	setup_runtime_user
	ensure_encryption_key
	run_container_doctor
	;;
*)
	exec "${cmd}" "$@"
	;;
esac
