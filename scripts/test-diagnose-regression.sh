#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/emdashctl"
load_site_common

test_diagnose_canary_redaction_truncation_and_atomic_out() {
	local tmpdir enc_key report out_file symlink_target symlink_path
	tmpdir="$(mktemp -d)"
	DIAG_TEST_TMP="${tmpdir}"
	trap 'rm -rf "${DIAG_TEST_TMP:-}"' RETURN

	ROOT_DIR="${tmpdir}/emdash"
	SITE_DIR="${ROOT_DIR}/app/site"
	SQLITE_DIR="${ROOT_DIR}/data/sqlite"
	SQLITE_PATH="${SQLITE_DIR}/data.db"
	SESSIONS_DIR="${ROOT_DIR}/data/sessions"
	UPLOADS_DIR="${ROOT_DIR}/data/uploads"
	APP_ENV_FILE="${ROOT_DIR}/etc/emdash.env"
	ENV_FILE="${APP_ENV_FILE}"
	APP_SYSTEMD_SERVICE="emdash-app"
	APP_PORT="3000"
	APP_PUBLIC_URL="http://127.0.0.1:3000"
	PROJECT_NAME="diag-test"
	TEMPLATE="blog"
	APP_RUN_USER="$(id -un)"
	APP_RUN_GROUP="$(id -gn)"
	DB_DRIVER="sqlite"
	SESSION_DRIVER="file"
	STORAGE_DRIVER="local"
	USE_CADDY="1"
	ENABLE_HTTPS="0"
	ENABLE_PLUGIN_SANDBOX="0"
	BACKUP_ENABLED="0"
	BACKUP_TARGET_TYPE="local"

	# Secret canaries
	local canary_pg="CanaryPgSecret_987654"
	local canary_s3="CanaryS3Secret_XYZ999"
	local canary_bearer="CanaryBearerTok_AABBCC112233"
	local canary_cookie="emdash_sid=CanarySessionCookieVal_778899; HttpOnly"
	local canary_jwt="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyXzEyMyJ9.CanaryJwtSignature998877"
	local canary_query="CanaryQuerySecret_554433"
	local canary_ip="203.0.113.42"
	enc_key="$(generate_emdash_encryption_key_spec)"

	PG_DB_PASSWORD="${canary_pg}"
	S3_SECRET_ACCESS_KEY="${canary_s3}"
	EMDASH_ENCRYPTION_KEY="${enc_key}"
	EMDASH_AUTH_SECRET="CanaryAuthSecret_112233"
	EMDASH_PREVIEW_SECRET="CanaryPreviewSecret_445566"

	mkdir -p "${SITE_DIR}" "${SQLITE_DIR}" "${SESSIONS_DIR}" "${UPLOADS_DIR}" "$(dirname "${APP_ENV_FILE}")"
	printf 'EMDASH_ENCRYPTION_KEY="%s"\n' "${enc_key}" >"${APP_ENV_FILE}"
	chmod 0640 "${APP_ENV_FILE}"
	cat >"${SITE_DIR}/package.json" <<'EOF'
{
  "name": "diag-test",
  "packageManager": "pnpm@11.9.0",
  "dependencies": {
    "emdash": "^1.6.0",
    "astro": "^6.1.0"
  }
}
EOF
	python3 - "${SQLITE_PATH}" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("CREATE TABLE t (id INTEGER)")
c.commit()
c.close()
PY

	# Mock runtime commands
	bool_active() { return 0; }
	curl() { return 0; }
	caddy() { return 0; }
	systemctl() {
		if [[ "${1:-}" == "show" ]]; then
			printf 'active\nrunning\n0\n0\n4242\n'
			return 0
		fi
		return 0
	}
	journalctl() {
		# Emit JSON journal entries containing all secret canaries + oversized payload to test truncation
		python3 - "${canary_bearer}" "${canary_cookie}" "${canary_jwt}" "${canary_query}" "${canary_ip}" "${enc_key}" "${canary_pg}" "${canary_s3}" <<'PY'
import json, sys
bearer, cookie, jwt, qsec, ip, enc_key, pg_pw, s3_sk = sys.argv[1:]
entries = [
    {
        "__REALTIME_TIMESTAMP": "1760000000000000",
        "PRIORITY": "6",
        "MESSAGE": f'Authorization: Bearer {bearer} jwt={jwt} url=https://example.com/cb?token={qsec}&ok=1\nSet-Cookie: {cookie}',
    },
    {
        "__REALTIME_TIMESTAMP": "1760000001000000",
        "PRIORITY": "6",
        "MESSAGE": json.dumps({
            "msg": "handled request",
            "request": {
                "remote_ip": ip,
                "client_ip": ip,
                "headers": {
                    "Authorization": [f"Bearer {bearer}"],
                    "Cookie": [cookie],
                    "X-Forwarded-For": [ip],
                },
            },
            "leak": f"postgres://u:{pg_pw}@db/app key={enc_key} s3={s3_sk}",
        }),
    },
]
# Add 15 large lines (~3.5 KiB each) to guarantee >32 KiB per-service cap triggers truncated=True
for i in range(15):
    entries.append({
        "__REALTIME_TIMESTAMP": str(1760000002000000 + i * 1000),
        "PRIORITY": "6",
        "MESSAGE": f"bulk-line-{i}-" + ("X" * 3500),
    })
for e in entries:
    print(json.dumps(e))
PY
	}

	report="$(diagnose_command --json --lines 50)"

	# 1. Secret canary check: ZERO leakage allowed
	local secret
	for secret in "${canary_pg}" "${canary_s3}" "${canary_bearer}" "CanarySessionCookieVal_778899" "${canary_jwt}" "${canary_query}" "${canary_ip}" "${enc_key}" "${EMDASH_AUTH_SECRET}" "${EMDASH_PREVIEW_SECRET}"; do
		if grep -Fq "${secret}" <<<"${report}"; then
			printf '[ERROR] diagnose --json leaked canary value: %s\n' "${secret}" >&2
			exit 1
		fi
	done

	# 2. Schema, truncation & redaction verification
	python3 - "${report}" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d["schema_version"] == 1
assert d["redaction"]["secrets_redacted"] is True
assert d["redaction"]["ips_redacted"] is True
assert d["config_summary"]["template"] == "blog"
assert len(d["config_summary"]["encryption_key_kids"]) == 1
assert d["site_packages"]["packages"]["emdash"] == "^1.6.0"
assert d["doctor"]["mode"] == "deep"
assert d["services"]["app"]["active_state"] == "active"
app_logs = d["recent_logs"]["app"]
assert app_logs["available"] is True
assert app_logs["truncated"] is True, f"expected truncated=True, got {app_logs}"
assert app_logs["bytes"] <= 32768, f"exceeded 32KiB cap: {app_logs['bytes']}"
first_msg = app_logs["entries"][0]["message"]
assert "[REDACTED_JWT]" in first_msg, first_msg
assert "[REDACTED_COOKIE]" in first_msg, first_msg
assert "[REDACTED]" in first_msg, first_msg
second_msg = app_logs["entries"][1]["message"]
assert "[REDACTED_IP]" in second_msg, second_msg
# Nested JSON inside message must remain valid JSON after two-pass redaction
nested = json.loads(second_msg)
assert nested["request"]["headers"]["Cookie"] == ["[REDACTED_COOKIE]"], nested
assert nested["request"]["headers"]["X-Forwarded-For"] == ["[REDACTED_IP]"], nested
PY

	# 3. --no-ip-redact preserves IP while still redacting secrets
	local no_ip_report
	no_ip_report="$(diagnose_command --json --lines 5 --no-ip-redact)"
	grep -Fq "${canary_ip}" <<<"${no_ip_report}" || {
		printf '[ERROR] --no-ip-redact should preserve IP\n' >&2
		exit 1
	}
	if grep -Fq "${canary_jwt}" <<<"${no_ip_report}"; then
		printf '[ERROR] --no-ip-redact must still redact JWT\n' >&2
		exit 1
	fi

	# 4. --out atomic write with 0600 permissions
	out_file="${tmpdir}/diag-out.json"
	diagnose_command --json --lines 5 --out "${out_file}" >/dev/null
	[[ -f "${out_file}" ]] || { printf '[ERROR] --out file not created\n' >&2; exit 1; }
	local out_mode
	out_mode="$(stat -c '%a' "${out_file}")"
	[[ "${out_mode}" == "600" ]] || { printf '[ERROR] --out file mode expected 600, got %s\n' "${out_mode}" >&2; exit 1; }
	python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "${out_file}"

	# 5. --out symlink rejection
	symlink_target="${tmpdir}/sensitive-target.txt"
	symlink_path="${tmpdir}/evil-link.json"
	printf 'DO_NOT_OVERWRITE\n' >"${symlink_target}"
	ln -s "${symlink_target}" "${symlink_path}"
	if (diagnose_command --json --out "${symlink_path}" >/dev/null 2>&1); then
		printf '[ERROR] diagnose --out should reject symlink target\n' >&2
		exit 1
	fi
	[[ "$(cat "${symlink_target}")" == "DO_NOT_OVERWRITE" ]] || {
		printf '[ERROR] symlink target was modified!\n' >&2
		exit 1
	}

	# 6. Human-readable output smoke check
	local text_out
	text_out="$(diagnose_command --lines 5)"
	printf '%s\n' "${text_out}" | grep -Fq "EmDash Diagnostic Summary" || {
		printf '[ERROR] diagnose text output unexpected:\n%s\n' "${text_out}" >&2
		exit 1
	}

	printf '[INFO] diagnose regression checks passed\n'
	trap - RETURN
	rm -rf "${tmpdir}"
}

test_diagnose_canary_redaction_truncation_and_atomic_out
