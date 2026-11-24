#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/emdashctl"
load_site_common

test_encrypted_full_backup_and_safe_restore() {
	local tmpdir archive enc_archive key1 key2
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "${tmpdir}"' RETURN

	ROOT_DIR="${tmpdir}/emdash"
	SITE_DIR="${ROOT_DIR}/app/site"
	SCRIPTS_DIR="${ROOT_DIR}/scripts"
	TMP_DIR="${ROOT_DIR}/tmp"
	BACKUP_DIR="${ROOT_DIR}/backups"
	UPLOADS_DIR="${ROOT_DIR}/data/uploads"
	SESSIONS_DIR="${ROOT_DIR}/data/sessions"
	SQLITE_DIR="${ROOT_DIR}/data/sqlite"
	SQLITE_PATH="${SQLITE_DIR}/data.db"
	INSTALL_YAML="${ROOT_DIR}/etc/install.yml"
	APP_ENV_FILE="${ROOT_DIR}/etc/emdash.env"
	ENV_FILE="${APP_ENV_FILE}"
	APP_SYSTEMD_SERVICE="emdash-app"
	APP_SYSTEMD_UNIT="${ROOT_DIR}/etc/emdash-app.service"
	CADDYFILE_PATH="${ROOT_DIR}/etc/caddy/Caddyfile"
	APP_BUILD_SCRIPT="${SCRIPTS_DIR}/emdash-build.sh"
	APP_RUN_USER="$(id -un)"
	APP_RUN_GROUP="$(id -gn)"
	DB_DRIVER="sqlite"
	SESSION_DRIVER="file"
	STORAGE_DRIVER="local"
	BACKUP_TARGET_TYPE="local"
	TEMPLATE="blog"

	mkdir -p "${SITE_DIR}/src" "${SITE_DIR}/node_modules/fake" "${SITE_DIR}/dist" "${SCRIPTS_DIR}" "${UPLOADS_DIR}" "${SESSIONS_DIR}" "${SQLITE_DIR}" "$(dirname "${CADDYFILE_PATH}")"
	key1="$(generate_emdash_encryption_key_spec)"
	key2="$(generate_emdash_encryption_key_spec)"
	EMDASH_ENCRYPTION_KEY="${key1}"

	cat >"${APP_ENV_FILE}" <<EOF
DOMAIN="source.example.com"
APP_PUBLIC_URL="https://source.example.com"
EMDASH_ENCRYPTION_KEY="${key1}"
EMDASH_PREVIEW_SECRET="preview-secret-1"
DB_DRIVER="sqlite"
EOF
	printf 'version: 1\n' >"${INSTALL_YAML}"
	printf 'source.example.com {}\n' >"${CADDYFILE_PATH}"
	printf '[Service]\n' >"${APP_SYSTEMD_UNIT}"
	printf '#!/usr/bin/env bash\nexit 0\n' >"${APP_BUILD_SCRIPT}"
	chmod +x "${APP_BUILD_SCRIPT}"
	cat >"${SITE_DIR}/package.json" <<'EOF'
{"name":"blog","dependencies":{"emdash":"^1.6.0"}}
EOF
	printf 'custom-page-content\n' >"${SITE_DIR}/src/custom.astro"
	printf 'should-be-excluded\n' >"${SITE_DIR}/node_modules/fake/index.js"
	printf 'should-be-excluded\n' >"${SITE_DIR}/dist/entry.mjs"
	printf 'upload-payload\n' >"${UPLOADS_DIR}/hero.png"

	python3 - "${SQLITE_PATH}" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("CREATE TABLE items (id INTEGER PRIMARY KEY, title TEXT)")
c.execute("INSERT INTO items (title) VALUES ('hello-emdash-16')")
c.commit()
c.close()
PY

	# 1. Create encrypted full backup
	BACKUP_ENCRYPTION_PASSPHRASE="test-passphrase-123"
	enc_archive="$(create_backup_archive 1 1)"
	[[ "${enc_archive}" == *.tar.gz.enc ]] || { printf '[ERROR] expected .enc archive\n' >&2; exit 1; }
	local mode
	mode="$(stat -c '%a' "${enc_archive}")"
	[[ "${mode}" == "600" ]] || { printf '[ERROR] expected 600 mode, got %s\n' "${mode}" >&2; exit 1; }

	# Decrypt and inspect structure (verify manifest, site source included, node_modules/dist excluded)
	local inspect_dir="${tmpdir}/inspect"
	mkdir -p "${inspect_dir}"
	BACKUP_ENCRYPTION_PASSPHRASE="${BACKUP_ENCRYPTION_PASSPHRASE}" openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass env:BACKUP_ENCRYPTION_PASSPHRASE -in "${enc_archive}" | tar -C "${inspect_dir}" -xzf -
	[[ -f "${inspect_dir}/meta/manifest.json" ]] || { printf '[ERROR] missing manifest.json\n' >&2; exit 1; }
	[[ -f "${inspect_dir}/site/src/custom.astro" ]] || { printf '[ERROR] missing site source in backup\n' >&2; exit 1; }
	[[ ! -e "${inspect_dir}/site/node_modules" ]] || { printf '[ERROR] node_modules should be excluded\n' >&2; exit 1; }
	[[ ! -e "${inspect_dir}/site/dist" ]] || { printf '[ERROR] dist should be excluded\n' >&2; exit 1; }
	[[ -f "${inspect_dir}/scripts/emdash-build.sh" ]] || { printf '[ERROR] full backup missing scripts\n' >&2; exit 1; }

	# 2. Test restore --with-site --with-secrets preserves target host DOMAIN while merging secrets
	cat >"${APP_ENV_FILE}" <<EOF
DOMAIN="target-host.example.org"
APP_PUBLIC_URL="https://target-host.example.org"
EMDASH_ENCRYPTION_KEY="${key2}"
EMDASH_PREVIEW_SECRET="preview-secret-2"
DB_DRIVER="sqlite"
EOF
	EMDASH_ENCRYPTION_KEY="${key2}"
	rm -f "${SITE_DIR}/src/custom.astro"
	systemctl() { return 0; }
	wait_http_ok() { return 0; }

	restore_command "${enc_archive}" --with-site --with-secrets --yes

	grep -Fq 'DOMAIN="target-host.example.org"' "${APP_ENV_FILE}" || { printf '[ERROR] host DOMAIN was overwritten during restore\n' >&2; exit 1; }
	grep -Fq "EMDASH_ENCRYPTION_KEY=\"${key1}\"" "${APP_ENV_FILE}" || { printf '[ERROR] encryption key was not merged\n' >&2; exit 1; }
	grep -Fq 'custom-page-content' "${SITE_DIR}/src/custom.astro" || { printf '[ERROR] site source was not restored\n' >&2; exit 1; }

	# 3. Cross-driver restore guard
	DB_DRIVER="postgres"
	if ( restore_command "${enc_archive}" --yes ) >/dev/null 2>&1; then
		printf '[ERROR] restore unexpectedly allowed sqlite archive into postgres host\n' >&2
		exit 1
	fi

	printf '[INFO] backup/restore regression checks passed\n'
	trap - RETURN
	rm -rf "${tmpdir}"
}

test_encrypted_full_backup_and_safe_restore
