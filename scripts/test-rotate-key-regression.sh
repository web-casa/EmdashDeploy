#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/emdashctl"
load_site_common

test_rotate_encryption_key_two_stage_and_rollback() {
	local tmpdir key1 kid1 status_json env_val key2 kid2
	tmpdir="$(mktemp -d)"
	ROTATE_TEST_TMP="${tmpdir}"
	trap 'rm -rf "${ROTATE_TEST_TMP:-}"' RETURN

	ROOT_DIR="${tmpdir}/emdash"
	SITE_DIR="${ROOT_DIR}/app/site"
	TMP_DIR="${ROOT_DIR}/tmp"
	SQLITE_DIR="${ROOT_DIR}/data/sqlite"
	SQLITE_PATH="${SQLITE_DIR}/data.db"
	APP_ENV_FILE="${ROOT_DIR}/etc/emdash.env"
	ENV_FILE="${APP_ENV_FILE}"
	INSTALL_YAML="${ROOT_DIR}/etc/install.yml"
	APP_SYSTEMD_SERVICE="emdash-app"
	APP_PORT="3000"
	APP_RUN_USER="$(id -un)"
	APP_RUN_GROUP="$(id -gn)"
	DB_DRIVER="sqlite"
	EMDASHCTL_HEALTH_TRIES="1"
	EMDASHCTL_SETUP_TRIES="1"

	mkdir -p "${SITE_DIR}" "${TMP_DIR}" "${SQLITE_DIR}" "$(dirname "${APP_ENV_FILE}")"

	key1="$(generate_emdash_encryption_key_spec)"
	kid1="$(emdash_encryption_key_fingerprint "${key1}")"
	EMDASH_ENCRYPTION_KEY="${key1}"

	printf 'EMDASH_ENCRYPTION_KEY="%s"\nAPP_PORT="3000"\n' "${key1}" >"${APP_ENV_FILE}"
	chmod 0640 "${APP_ENV_FILE}"
	cat >"${INSTALL_YAML}" <<EOF
version: 1
secrets:
  encryption_key_kid: ${kid1}
EOF

	# Seed SQLite DB with an EmDash 1.6.0 encrypted plugin setting referencing kid1
	python3 - "${SQLITE_PATH}" "${kid1}" <<'PY'
import json, sqlite3, sys
db_path, kid = sys.argv[1], sys.argv[2]
conn = sqlite3.connect(db_path)
conn.execute("CREATE TABLE _emdash_options (key TEXT PRIMARY KEY, value TEXT)")
envelope = {
    "apiKey": {
        "$emdash": "encrypted",
        "v": 1,
        "kid": kid,
        "iv": "AAAAAAAAAAAAAAAA",
        "ciphertext": "BBBBBBBBBBBBBBBBBBBBBB",
    }
}
conn.execute("INSERT INTO _emdash_options (key, value) VALUES (?, ?)", ("plugin:resend:settings", json.dumps(envelope)))
conn.commit()
conn.close()
PY

	# Mock systemctl / curl / run_as_app_user
	MOCK_HEALTH_OK="1"
	systemctl() { return 0; }
	curl() { [[ "${MOCK_HEALTH_OK}" == "1" ]]; }
	run_as_app_user() { return 1; }

	# 1. --status shows 1 key and 1 DB reference for kid1, never plaintext
	status_json="$(rotate_encryption_key_command --status --json)"
	if printf '%s' "${status_json}" | grep -Fq "${key1}"; then
		printf '[ERROR] --status leaked plaintext key1\n' >&2
		exit 1
	fi
	python3 - "${status_json}" "${kid1}" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
kid1 = sys.argv[2]
assert d["key_count"] == 1
assert d["primary_kid"] == kid1
assert d["legacy_kids"] == []
assert d["db_scan"]["checked"] is True
assert d["db_scan"]["counts"].get(kid1) == 1, d["db_scan"]
PY

	# 2. --dry-run does not modify emdash.env or install.yml
	local dry_out
	dry_out="$(rotate_encryption_key_command --dry-run)"
	printf '%s\n' "${dry_out}" | grep -Fq "Dry-run" || { printf '[ERROR] unexpected dry-run output\n' >&2; exit 1; }
	env_val="$(bash -c 'set -a; . "$1"; printf "%s" "$EMDASH_ENCRYPTION_KEY"' _ "${APP_ENV_FILE}")"
	[[ "${env_val}" == "${key1}" ]] || { printf '[ERROR] --dry-run modified emdash.env\n' >&2; exit 1; }

	# 3. Stage 1 rollback when health check fails after restart
	MOCK_HEALTH_OK="0"
	if (rotate_encryption_key_command --yes >/dev/null 2>&1); then
		printf '[ERROR] Stage 1 should fail when health check fails\n' >&2
		exit 1
	fi
	env_val="$(bash -c 'set -a; . "$1"; printf "%s" "$EMDASH_ENCRYPTION_KEY"' _ "${APP_ENV_FILE}")"
	[[ "${env_val}" == "${key1}" ]] || { printf '[ERROR] Stage 1 rollback did not restore emdash.env\n' >&2; exit 1; }
	grep -Fq "encryption_key_kid: ${kid1}" "${INSTALL_YAML}" || { printf '[ERROR] Stage 1 rollback did not restore install.yml\n' >&2; exit 1; }

	# 4. Stage 1 succeeds when healthy -> prepends new key, preserves old key & 0640 mode, updates install.yml
	MOCK_HEALTH_OK="1"
	rotate_encryption_key_command --yes >/dev/null
	env_val="$(bash -c 'set -a; . "$1"; printf "%s" "$EMDASH_ENCRYPTION_KEY"' _ "${APP_ENV_FILE}")"
	EMDASH_ENCRYPTION_KEY="${env_val}"
	[[ "${env_val}" == *",${key1}" ]] || { printf '[ERROR] Stage 1 did not prepend new key: %s\n' "${env_val}" >&2; exit 1; }
	key2="${env_val%%,*}"
	kid2="$(emdash_encryption_key_fingerprint "${key2}")"
	[[ "${kid2}" != "${kid1}" ]] || { printf '[ERROR] New kid equals old kid\n' >&2; exit 1; }
	[[ "$(stat -c '%a' "${APP_ENV_FILE}")" == "640" ]] || { printf '[ERROR] emdash.env mode lost after Stage 1\n' >&2; exit 1; }
	grep -Fq "encryption_key_kid: ${kid2},${kid1}" "${INSTALL_YAML}" || { printf '[ERROR] install.yml not updated after Stage 1\n' >&2; exit 1; }

	# 5. Stage 2 (--prune-old) MUST block when DB still references kid1
	if (rotate_encryption_key_command --prune-old --confirm-prune-kid "${kid1}" >/dev/null 2>&1); then
		printf '[ERROR] --prune-old should block when DB still has encrypted values using old kid\n' >&2
		exit 1
	fi

	# 6. Simulate re-encrypting plugin setting under kid2
	python3 - "${SQLITE_PATH}" "${kid2}" <<'PY'
import json, sqlite3, sys
db_path, kid = sys.argv[1], sys.argv[2]
conn = sqlite3.connect(db_path)
envelope = {
    "apiKey": {
        "$emdash": "encrypted",
        "v": 1,
        "kid": kid,
        "iv": "CCCCCCCCCCCCCCCC",
        "ciphertext": "DDDDDDDDDDDDDDDDDDDDDD",
    }
}
conn.execute("UPDATE _emdash_options SET value = ? WHERE key = ?", (json.dumps(envelope), "plugin:resend:settings"))
conn.commit()
conn.close()
PY

	# 7. Stage 2 MUST reject missing --confirm-prune-kid (even with --yes) or mismatched kid
	if (rotate_encryption_key_command --prune-old --yes </dev/null >/dev/null 2>&1); then
		printf '[ERROR] --prune-old must NOT allow plain --yes without --confirm-prune-kid\n' >&2
		exit 1
	fi
	if (rotate_encryption_key_command --prune-old --confirm-prune-kid "deadbeef" </dev/null >/dev/null 2>&1); then
		printf '[ERROR] --prune-old must reject mismatched --confirm-prune-kid\n' >&2
		exit 1
	fi

	# 8. Stage 2 succeeds cleanly with matching --confirm-prune-kid once DB refs are 0
	rotate_encryption_key_command --prune-old --confirm-prune-kid "${kid1}" </dev/null >/dev/null
	env_val="$(bash -c 'set -a; . "$1"; printf "%s" "$EMDASH_ENCRYPTION_KEY"' _ "${APP_ENV_FILE}")"
	[[ "${env_val}" == "${key2}" ]] || { printf '[ERROR] Stage 2 did not prune old key properly\n' >&2; exit 1; }
	grep -Fq "encryption_key_kid: ${kid2}" "${INSTALL_YAML}" || { printf '[ERROR] install.yml not updated after Stage 2\n' >&2; exit 1; }
	if grep -Fq "${kid1}" "${INSTALL_YAML}"; then
		printf '[ERROR] old kid still present in install.yml after Stage 2\n' >&2
		exit 1
	fi

	printf '[INFO] rotate-encryption-key regression checks passed\n'
	trap - RETURN
	rm -rf "${tmpdir}"
}

test_pg_scan_handles_row_to_json_escaped_text_column() {
	local tmpdir key1 kid1 scan_out
	tmpdir="$(mktemp -d)"
	PG_ROTATE_TEST_TMP="${tmpdir}"
	trap 'rm -rf "${PG_ROTATE_TEST_TMP:-}"' RETURN

	DB_DRIVER="postgres"
	POSTGRES_HOST="127.0.0.1"
	POSTGRES_PORT="5432"
	PG_DB_USER="emdash"
	PG_DB_NAME="emdash"
	PG_DB_PASSWORD="dummy"
	key1="$(generate_emdash_encryption_key_spec)"
	kid1="$(emdash_encryption_key_fingerprint "${key1}")"

	# Mock psql returning row_to_json() where TEXT column JSON quotes are escaped as \"
	psql() {
		local sql="${*: -1}"
		if [[ "${sql}" == *"pg_tables"* ]]; then
			printf '_emdash_options\n'
			return 0
		fi
		# Verify the query does NOT require unescaped quotes around $emdash
		if [[ "${sql}" == *'%"$emdash"%'* ]]; then
			printf '[ERROR] PG scan SQL must not require unescaped quotes around $emdash: %s\n' "${sql}" >&2
			return 1
		fi
		python3 - "${kid1}" <<'PY'
import json, sys
kid = sys.argv[1]
inner = json.dumps({
    "apiKey": {"$emdash": "encrypted", "v": 1, "kid": kid, "iv": "AAAA", "ciphertext": "BBBB"}
})
# Simulate PostgreSQL row_to_json(t)::text on a TEXT column
row_json = json.dumps({"key": "plugin:resend:settings", "value": inner})
print(f"_emdash_options\t{row_json}")
PY
	}

	scan_out="$(scan_db_encrypted_kid_refs)"
	python3 - "${scan_out}" "${kid1}" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
kid = sys.argv[2]
assert d["checked"] is True, d
assert d["counts"].get(kid) == 1, f"PG row_to_json escaped TEXT column missed kid={kid}: {d}"
assert "_emdash_options" in d["tables"].get(kid, []), d
PY
	printf '[INFO] rotate-encryption-key PG row_to_json scan regression passed\n'
	trap - RETURN
	rm -rf "${tmpdir}"
}

test_rotate_encryption_key_two_stage_and_rollback
test_pg_scan_handles_row_to_json_escaped_text_column
