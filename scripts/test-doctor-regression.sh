#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/emdashctl"
load_site_common

test_doctor_deep_json_schema_and_redaction() {
	local tmpdir enc_key report
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "${tmpdir}"' RETURN

	ROOT_DIR="${tmpdir}/emdash"
	SITE_DIR="${ROOT_DIR}/app/site"
	SQLITE_DIR="${ROOT_DIR}/data/sqlite"
	SQLITE_PATH="${SQLITE_DIR}/data.db"
	SESSIONS_DIR="${ROOT_DIR}/data/sessions"
	APP_ENV_FILE="${ROOT_DIR}/etc/emdash.env"
	ENV_FILE="${APP_ENV_FILE}"
	APP_SYSTEMD_SERVICE="emdash-app"
	APP_PORT="3000"
	APP_PUBLIC_URL="http://127.0.0.1:3000"
	APP_RUN_USER="$(id -un)"
	APP_RUN_GROUP="$(id -gn)"
	DB_DRIVER="sqlite"
	SESSION_DRIVER="file"
	STORAGE_DRIVER="local"
	USE_CADDY="0"
	ENABLE_HTTPS="0"
	ENABLE_PLUGIN_SANDBOX="0"
	BACKUP_ENABLED="0"
	BACKUP_TARGET_TYPE="local"
	PG_DB_PASSWORD="SuperSecretPgPassword!999"
	enc_key="$(generate_emdash_encryption_key_spec)"
	EMDASH_ENCRYPTION_KEY="${enc_key}"

	mkdir -p "${SITE_DIR}" "${SQLITE_DIR}" "${SESSIONS_DIR}" "${ROOT_DIR}/data/uploads" "$(dirname "${APP_ENV_FILE}")"
	UPLOADS_DIR="${ROOT_DIR}/data/uploads"
	printf 'EMDASH_ENCRYPTION_KEY="%s"\n' "${enc_key}" >"${APP_ENV_FILE}"
	chmod 0640 "${APP_ENV_FILE}"
	python3 - "${SQLITE_PATH}" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("CREATE TABLE t (id INTEGER)")
c.commit()
c.close()
PY

	# Verify redaction helper directly
	local redacted
	redacted="$(printf 'leak %s and postgres://u:%s@127.0.0.1/db' "${enc_key}" "${PG_DB_PASSWORD}" | redact_sensitive_text)"
	if printf '%s' "${redacted}" | grep -Fq "${enc_key}" || printf '%s' "${redacted}" | grep -Fq "${PG_DB_PASSWORD}"; then
		printf '[ERROR] redact_sensitive_text leaked secret: %s\n' "${redacted}" >&2
		exit 1
	fi

	bool_active() { return 0; }
	curl() { return 0; }

	# Mock upstream emdash doctor JSON aggregation
	mkdir -p "${SITE_DIR}/node_modules"
	run_as_app_user() {
		local cmd="$1"
		if [[ "${cmd}" == *"emdash doctor --help"* ]]; then
			return 0
		fi
		if [[ "${cmd}" == *"emdash doctor --database"* ]]; then
			printf '[{"name":"database","status":"pass","message":"ok"},{"name":"collections","status":"pass","message":"3 collections"},{"name":"datetime storage","status":"warn","message":"1 legacy column"},{"name":"users","status":"pass","message":"1 admin user"}]\n'
			return 0
		fi
		return 1
	}

	report="$(doctor_command 1 1)"
	if printf '%s' "${report}" | grep -Fq "${enc_key}"; then
		printf '[ERROR] doctor JSON leaked EMDASH_ENCRYPTION_KEY\n' >&2
		exit 1
	fi

	python3 - "${report}" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data["schema_version"] == 1
assert data["mode"] == "deep"
checks = {c["name"]: c for c in data["checks"]}
assert checks["permissions"]["status"] == "ok", checks.get("permissions")
assert checks["backup schedule"]["status"] == "skipped"
assert checks["encryption key"]["status"] == "ok"
assert "kid=" in checks["encryption key"]["detail"]
assert checks["database"]["status"] == "ok"
assert checks["caddy"]["status"] == "skipped"
assert checks["plugin sandbox"]["status"] == "skipped"
assert checks["upstream:collections"]["status"] == "ok", checks.get("upstream:collections")
assert checks["upstream:datetime storage"]["status"] == "warn", checks.get("upstream:datetime storage")
assert checks["upstream:users"]["status"] == "ok", checks.get("upstream:users")
assert "upstream:database" not in checks
PY

	# World-readable env file must trigger permissions failure
	chmod 0644 "${APP_ENV_FILE}"
	local bad_perm_report
	bad_perm_report="$(doctor_command 1 1)"
	python3 - "${bad_perm_report}" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
checks = {c["name"]: c for c in data["checks"]}
assert checks["permissions"]["status"] == "fail", checks.get("permissions")
assert data["healthy"] is False
PY
	chmod 0640 "${APP_ENV_FILE}"

	# Also verify human-readable text output runs cleanly without syntax errors
	local text_report
	text_report="$(doctor_command 0 1)"
	printf '%s\n' "${text_report}" | grep -Fq '[OK] database:' || {
		printf '[ERROR] doctor text output unexpected:\n%s\n' "${text_report}" >&2
		exit 1
	}

	printf '[INFO] doctor regression checks passed\n'
	trap - RETURN
	rm -rf "${tmpdir}"
}

test_doctor_deep_json_schema_and_redaction
