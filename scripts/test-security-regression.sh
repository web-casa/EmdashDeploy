#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== [1] Static check: no secret values passed as CLI argv or psql -c ==="
if grep -rnE 'python3 - .*(SECRET|PASSWORD|ENCRYPTION_KEY|s3_sk)' \
	"${SCRIPT_DIR}/emdashctl" "${SCRIPT_DIR}/lib/"*.sh "${SCRIPT_DIR}/docker/"*.sh "${SCRIPT_DIR}/scripts/migrate-runtime.sh"; then
	printf '[ERROR] Found secret passed via python3 CLI argv (exposes secret in /proc/cmdline)\n' >&2
	exit 1
fi
if grep -rnE 'psql .* -c "\$\{?alter_sql' "${SCRIPT_DIR}/emdashctl"; then
	printf '[ERROR] Found password-bearing ALTER ROLE passed via psql -c CLI arg\n' >&2
	exit 1
fi
if grep -rnE 'secrets fingerprint.*\$\{?EMDASH_ENCRYPTION_KEY' "${SCRIPT_DIR}/lib/"*.sh "${SCRIPT_DIR}/emdashctl"; then
	printf '[ERROR] Found EMDASH_ENCRYPTION_KEY passed via CLI argument\n' >&2
	exit 1
fi

echo "=== [2] Static check: restore must never chmod postgres.dump to 0644 ==="
if grep -rnE 'chmod 0?644.*postgres\.dump' "${SCRIPT_DIR}/emdashctl" "${SCRIPT_DIR}/docker/"*.sh; then
	printf '[ERROR] Found world-readable chmod 0644 on postgres.dump\n' >&2
	exit 1
fi

echo "=== [3] Input validation: DOMAIN & ADMIN_EMAIL reject Caddyfile injection ==="
(
	# shellcheck source=../lib/common.sh
	source "${SCRIPT_DIR}/lib/common.sh"
	# shellcheck source=../lib/config.sh
	source "${SCRIPT_DIR}/lib/config.sh"
	# shellcheck source=../lib/i18n.sh
	source "${SCRIPT_DIR}/lib/i18n.sh"

	init_defaults
	TEMPLATE="blog"
	DB_DRIVER="sqlite"
	SESSION_DRIVER="file"
	STORAGE_DRIVER="local"
	BACKUP_ENABLED="0"
	USE_CADDY="1"
	ENABLE_HTTPS="0"
	APP_PORT="3000"
	EMDASH_ENCRYPTION_KEY=""
	EMDASH_PREVIEW_SECRET="abc123"

	# Valid domain + email must pass
	DOMAIN="blog.example.com"
	ADMIN_EMAIL="ops@example.com"
	validate_config

	# Malicious DOMAIN with braces/newline must fail
	for bad_domain in "evil.com { respond 200 }" $'evil.com\n{\n}' "evil..example.com" "-bad.example.com"; do
		DOMAIN="${bad_domain}"
		if ( validate_config ) >/dev/null 2>&1; then
			printf '[ERROR] validate_config unexpectedly accepted malicious DOMAIN: %q\n' "${bad_domain}" >&2
			exit 1
		fi
	done

	# Malicious ADMIN_EMAIL must fail
	DOMAIN="blog.example.com"
	for bad_email in "ops@example.com }" $'ops@example.com\nevil' "not-an-email"; do
		ADMIN_EMAIL="${bad_email}"
		if ( validate_config ) >/dev/null 2>&1; then
			printf '[ERROR] validate_config unexpectedly accepted malicious ADMIN_EMAIL: %q\n' "${bad_email}" >&2
			exit 1
		fi
	done
)

echo "=== [4] Malicious tar archive rejection in emdashctl restore ==="
TMP_DIR="$(mktemp -d)"
SEC_TEST_TMP="${TMP_DIR}"
trap 'rm -rf "${SEC_TEST_TMP:-}"' EXIT

(
	# shellcheck source=../emdashctl
	source "${SCRIPT_DIR}/emdashctl"
	load_site_common

	ROOT_DIR="${TMP_DIR}/emdash"
	SITE_DIR="${ROOT_DIR}/app/site"
	SCRIPTS_DIR="${ROOT_DIR}/scripts"
	BACKUP_DIR="${ROOT_DIR}/backups"
	UPLOADS_DIR="${ROOT_DIR}/data/uploads"
	SESSIONS_DIR="${ROOT_DIR}/data/sessions"
	SQLITE_DIR="${ROOT_DIR}/data/sqlite"
	SQLITE_PATH="${SQLITE_DIR}/data.db"
	APP_ENV_FILE="${ROOT_DIR}/etc/emdash.env"
	ENV_FILE="${APP_ENV_FILE}"
	APP_SYSTEMD_SERVICE="emdash-app"
	APP_RUN_USER="$(id -un)"
	APP_RUN_GROUP="$(id -gn)"
	DB_DRIVER="sqlite"
	SESSION_DRIVER="file"
	STORAGE_DRIVER="local"
	EMDASH_LOCK_FILE="${TMP_DIR}/sec.lock"
	mkdir -p "${SITE_DIR}" "${UPLOADS_DIR}" "${SESSIONS_DIR}" "${SQLITE_DIR}" "$(dirname "${APP_ENV_FILE}")"
	systemctl() { return 0; }
	wait_http_ok() { return 0; }

	# 4a. Path traversal tar member (../escape.txt) must be rejected
	TRAVERSAL_TAR="${TMP_DIR}/traversal.tar.gz"
	python3 - "${TRAVERSAL_TAR}" <<'PY'
import io, sys, tarfile
with tarfile.open(sys.argv[1], "w:gz") as tf:
    info = tarfile.TarInfo("data/../../escape.txt")
    payload = b"pwned\n"
    info.size = len(payload)
    tf.addfile(info, io.BytesIO(payload))
PY
	if ( restore_command "${TRAVERSAL_TAR}" --yes ) >/dev/null 2>&1; then
		printf '[ERROR] emdashctl restore accepted path-traversal tar archive!\n' >&2
		exit 1
	fi

	# 4b. Symlink inside data/ must be rejected
	SYMLINK_TAR="${TMP_DIR}/symlink.tar.gz"
	python3 - "${SYMLINK_TAR}" <<'PY'
import sys, tarfile
with tarfile.open(sys.argv[1], "w:gz") as tf:
    info = tarfile.TarInfo("data/uploads/evil-link")
    info.type = tarfile.SYMTYPE
    info.linkname = "/etc/passwd"
    tf.addfile(info)
PY
	if ( restore_command "${SYMLINK_TAR}" --yes ) >/dev/null 2>&1; then
		printf '[ERROR] emdashctl restore accepted symlink inside data/!\n' >&2
		exit 1
	fi

	# 4c. Escaping symlink inside site/ when --with-site is passed must be rejected
	SITE_ESCAPE_TAR="${TMP_DIR}/site-escape.tar.gz"
	python3 - "${SITE_ESCAPE_TAR}" <<'PY'
import sys, tarfile
with tarfile.open(sys.argv[1], "w:gz") as tf:
    info = tarfile.TarInfo("site/evil-link")
    info.type = tarfile.SYMTYPE
    info.linkname = "../../../../etc/passwd"
    tf.addfile(info)
PY
	if ( restore_command "${SITE_ESCAPE_TAR}" --with-site --yes ) >/dev/null 2>&1; then
		printf '[ERROR] emdashctl restore --with-site accepted escaping symlink!\n' >&2
		exit 1
	fi

	# 4d. Tampered SHA-256 in meta/manifest.json must be rejected
	TAMPER_TAR="${TMP_DIR}/tamper.tar.gz"
	python3 - "${TAMPER_TAR}" <<'PY'
import io, json, sys, tarfile
with tarfile.open(sys.argv[1], "w:gz") as tf:
    db_bytes = b"not-a-matching-checksum"
    ti = tarfile.TarInfo("data/sqlite/data.db")
    ti.size = len(db_bytes)
    tf.addfile(ti, io.BytesIO(db_bytes))
    manifest = json.dumps({"db_driver": "sqlite", "files": {"data/sqlite/data.db": "0" * 64}}).encode()
    mi = tarfile.TarInfo("meta/manifest.json")
    mi.size = len(manifest)
    tf.addfile(mi, io.BytesIO(manifest))
PY
	if ( restore_command "${TAMPER_TAR}" --yes ) >/dev/null 2>&1; then
		printf '[ERROR] emdashctl restore accepted tampered SHA-256 manifest!\n' >&2
		exit 1
	fi
)

echo "=== [5] Hardening contracts: systemd sandboxing, Caddy security headers, Docker no-new-privileges, bootstrap --sha256 ==="
for directive in "NoNewPrivileges=yes" "PrivateTmp=yes" "ProtectSystem=full" "ProtectHome=yes" "UMask=0027"; do
	grep -Fq "${directive}" "${SCRIPT_DIR}/lib/render.sh" || {
		printf '[ERROR] Missing systemd hardening directive in lib/render.sh: %s\n' "${directive}" >&2
		exit 1
	}
done

for hdr in "-Server" 'X-Content-Type-Options "nosniff"' 'Referrer-Policy "strict-origin-when-cross-origin"' 'X-Frame-Options "SAMEORIGIN"'; do
	grep -Fq -- "${hdr}" "${SCRIPT_DIR}/lib/render.sh" || {
		printf '[ERROR] Missing Caddy security header in lib/render.sh: %s\n' "${hdr}" >&2
		exit 1
	}
done

grep -Fq 'no-new-privileges:true' "${SCRIPT_DIR}/docker/compose.yml" || {
	printf '[ERROR] Missing no-new-privileges:true in docker/compose.yml\n' >&2
	exit 1
}
grep -Fq 'cap_drop:' "${SCRIPT_DIR}/docker/compose.yml" || {
	printf '[ERROR] Missing cap_drop in docker/compose.yml\n' >&2
	exit 1
}
grep -Fq -- '--sha256' "${SCRIPT_DIR}/bootstrap.sh" || {
	printf '[ERROR] Missing --sha256 integrity support in bootstrap.sh\n' >&2
	exit 1
}

printf '[INFO] security regression checks passed\n'
