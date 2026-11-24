#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEST_TMP_DIR}"' EXIT

# 1. Test validate_instance_name, derive_paths, find_available_app_port, and modular Caddy rendering
(
	# shellcheck source=../lib/common.sh
	source "${SCRIPT_DIR}/lib/common.sh"
	# shellcheck source=../lib/site-common.sh
	source "${SCRIPT_DIR}/lib/site-common.sh"
	# shellcheck source=../lib/config.sh
	source "${SCRIPT_DIR}/lib/config.sh"
	# shellcheck source=../lib/i18n.sh
	source "${SCRIPT_DIR}/lib/i18n.sh"
	# shellcheck source=../lib/render.sh
	source "${SCRIPT_DIR}/lib/render.sh"

	# Valid instance names
	validate_instance_name ""
	validate_instance_name "site2"
	validate_instance_name "blog-prod-01"

	# Invalid instance names must fail
	for bad in "default" "Site2" "2site" "bad_name" "../etc" "a/b"; do
		if (validate_instance_name "${bad}" >/dev/null 2>&1); then
			printf '[ERROR] validate_instance_name unexpectedly accepted: %s\n' "${bad}" >&2
			exit 1
		fi
	done

	export EMDASH_INSTANCES_BASE_DIR="${TEST_TMP_DIR}/etc-emdash"
	mkdir -p "${EMDASH_INSTANCES_BASE_DIR}/instances" "${EMDASH_INSTANCES_BASE_DIR}/caddy/sites.d" "${EMDASH_INSTANCES_BASE_DIR}/caddy/conf.d"
	export CADDY_ROOT_DIR="${EMDASH_INSTANCES_BASE_DIR}/caddy"

	# Default instance layout
	init_defaults
	EMDASH_INSTALL_DOMAIN="site1.example.com"
	EMDASH_INSTALL_ADMIN_EMAIL="ops@example.com"
	EMDASH_INSTALL_USE_CADDY=1
	EMDASH_INSTALL_ENABLE_HTTPS=1
	EMDASH_INSTALL_ROOT_DIR="${TEST_TMP_DIR}/data-default"
	apply_env_overrides
	CONFIG_DIR="${EMDASH_INSTANCES_BASE_DIR}"
	derive_paths
	[[ "${INSTANCE_SLUG}" == "default" ]]
	[[ "${APP_SYSTEMD_SERVICE}" == "emdash-app" ]]
	[[ "${BACKUP_CRON_FILE}" == "/etc/cron.d/emdash-backup" ]]
	[[ "${APP_PORT}" == "3000" ]]
	[[ "${CADDY_SITE_FILE}" == "${CADDY_ROOT_DIR}/sites.d/default.caddy" ]]
	render_caddy_file

	# Persist default env so find_available_app_port sees port 3000
	mkdir -p "${TEST_TMP_DIR}/data-default/app/site"
	cat >"${EMDASH_INSTANCES_BASE_DIR}/emdash.env" <<EOF
ROOT_DIR="${TEST_TMP_DIR}/data-default"
APP_PORT="3000"
APP_SYSTEMD_SERVICE="emdash-app"
APP_PUBLIC_URL="https://site1.example.com"
DB_DRIVER="sqlite"
SESSION_DRIVER="file"
USE_CADDY="1"
CADDY_DIR="${CADDY_ROOT_DIR}"
CADDY_SITES_DIR="${CADDY_ROOT_DIR}/sites.d"
CADDY_CONF_DIR="${CADDY_ROOT_DIR}/conf.d"
CADDY_SITE_FILE="${CADDY_ROOT_DIR}/sites.d/default.caddy"
BACKUP_CRON_FILE="${TEST_TMP_DIR}/cron-default"
APP_SYSTEMD_UNIT="${TEST_TMP_DIR}/emdash-app.service"
EOF
	touch "${TEST_TMP_DIR}/cron-default" "${TEST_TMP_DIR}/emdash-app.service"

	# User-owned custom snippet in conf.d must survive subsequent instance renders
	printf '# user-custom-snippet\n' >"${CADDY_ROOT_DIR}/conf.d/custom.caddy"

	# Second named instance (site2)
	unset EMDASH_INSTALL_DOMAIN EMDASH_INSTALL_ADMIN_EMAIL EMDASH_INSTALL_ROOT_DIR CONFIG_DIR
	init_defaults
	INSTANCE_NAME="site2"
	EMDASH_INSTALL_DOMAIN="site2.example.com"
	EMDASH_INSTALL_ADMIN_EMAIL="ops@example.com"
	EMDASH_INSTALL_USE_CADDY=1
	EMDASH_INSTALL_ENABLE_HTTPS=0
	EMDASH_INSTALL_ROOT_DIR="${TEST_TMP_DIR}/data-site2"
	apply_env_overrides
	CONFIG_DIR="${EMDASH_INSTANCES_BASE_DIR}/instances/site2"
	mkdir -p "${CONFIG_DIR}" "${TEST_TMP_DIR}/data-site2/app/site"
	derive_paths
	[[ "${INSTANCE_SLUG}" == "site2" ]]
	[[ "${APP_SYSTEMD_SERVICE}" == "emdash-app-site2" ]]
	[[ "${BACKUP_CRON_FILE}" == "/etc/cron.d/emdash-backup-site2" ]]
	[[ "${PG_DB_NAME}" == "emdash_site2" ]]
	[[ "${PG_DB_USER}" == "emdash_site2" ]]
	[[ "${APP_PORT}" != "3000" ]]
	[[ "${CADDY_SITE_FILE}" == "${CADDY_ROOT_DIR}/sites.d/site2.caddy" ]]
	render_caddy_file

	cat >"${CONFIG_DIR}/emdash.env" <<EOF
INSTANCE_NAME="site2"
INSTANCE_SLUG="site2"
CONFIG_DIR="${CONFIG_DIR}"
ROOT_DIR="${TEST_TMP_DIR}/data-site2"
APP_PORT="${APP_PORT}"
APP_SYSTEMD_SERVICE="emdash-app-site2"
APP_PUBLIC_URL="http://site2.example.com"
DB_DRIVER="sqlite"
SESSION_DRIVER="file"
USE_CADDY="1"
CADDY_DIR="${CADDY_ROOT_DIR}"
CADDY_SITES_DIR="${CADDY_ROOT_DIR}/sites.d"
CADDY_CONF_DIR="${CADDY_ROOT_DIR}/conf.d"
CADDY_SITE_FILE="${CADDY_ROOT_DIR}/sites.d/site2.caddy"
BACKUP_CRON_FILE="${TEST_TMP_DIR}/cron-site2"
APP_SYSTEMD_UNIT="${TEST_TMP_DIR}/emdash-app-site2.service"
EOF
	touch "${TEST_TMP_DIR}/cron-site2" "${TEST_TMP_DIR}/emdash-app-site2.service"

	# Verify modular Caddyfile has exactly one global email block and proper newline before import
	email_blocks="$(grep -c 'email ops@example.com' "${CADDY_ROOT_DIR}/Caddyfile")"
	[[ "${email_blocks}" == "1" ]]
	grep -qx "import ${CADDY_ROOT_DIR}/sites.d/\*.caddy" "${CADDY_ROOT_DIR}/Caddyfile"
	grep -qx "import ${CADDY_ROOT_DIR}/conf.d/\*.caddy" "${CADDY_ROOT_DIR}/Caddyfile"
	grep -Fq 'reverse_proxy 127.0.0.1:3000' "${CADDY_ROOT_DIR}/sites.d/default.caddy"
	grep -Fq "reverse_proxy 127.0.0.1:${APP_PORT}" "${CADDY_ROOT_DIR}/sites.d/site2.caddy"
	grep -Fq 'user-custom-snippet' "${CADDY_ROOT_DIR}/conf.d/custom.caddy"

	# Verify next instance allocates a distinct port when site2's port is recorded
	next_port="$(find_available_app_port "${APP_PORT}")"
	[[ "${next_port}" != "${APP_PORT}" ]]
)

# 2. Test install-emdash.sh --update-cli (zero-downtime CLI & lib update across all instances)
(
	export EMDASH_INSTANCES_BASE_DIR="${TEST_TMP_DIR}/etc-emdash"
	export EMDASH_BIN_PATH="${TEST_TMP_DIR}/bin/emdashctl"
	# shellcheck source=../install-emdash.sh
	source "${SCRIPT_DIR}/install-emdash.sh"
	require_root() { :; }
	remove_legacy_emdashctl_aliases() { :; }

	before_hash="$(sha256sum "${EMDASH_INSTANCES_BASE_DIR}/emdash.env" | awk '{print $1}')"
	INSTANCE_NAME=""
	update_cli_only_command >/dev/null
	after_hash="$(sha256sum "${EMDASH_INSTANCES_BASE_DIR}/emdash.env" | awk '{print $1}')"
	[[ "${before_hash}" == "${after_hash}" ]]
	[[ -x "${EMDASH_BIN_PATH}" ]]
	for root in "${TEST_TMP_DIR}/data-default" "${TEST_TMP_DIR}/data-site2"; do
		[[ -f "${root}/lib/site-common.sh" ]]
		[[ -f "${root}/lib/astro-patch.py" ]]
		[[ -f "${root}/lib/fast-fail-google-fonts.mjs" ]]
		[[ -f "${root}/lib/migrate-sqlite-to-pg.py" ]]
	done
)

# 3. Test emdashctl instances (--json and human table output)
export EMDASH_INSTANCES_BASE_DIR="${TEST_TMP_DIR}/etc-emdash"
export EMDASH_BIN_PATH="${TEST_TMP_DIR}/bin/emdashctl"
export EMDASH_LOCK_FILE="${TEST_TMP_DIR}/test.lock"

INST_JSON="$(bash "${SCRIPT_DIR}/emdashctl" instances --json)"
python3 - "${INST_JSON}" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data["schema_version"] == 1
names = [r["instance"] for r in data["instances"]]
assert names == ["default", "site2"], f"unexpected instances: {names}"
PY

INST_TABLE="$(bash "${SCRIPT_DIR}/emdashctl" instances)"
grep -Fq "INSTANCE" <<<"${INST_TABLE}"
grep -Fq "default" <<<"${INST_TABLE}"
grep -Fq "site2" <<<"${INST_TABLE}"

# 4. Test emdashctl uninstall safety guards & sibling preservation
FAKE_BIN="${TEST_TMP_DIR}/fake-bin"
mkdir -p "${FAKE_BIN}"
cat >"${FAKE_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${FAKE_BIN}/systemctl"

# 4a. Non-interactive --purge-data without --confirm-instance MUST fail even with --yes
if PATH="${FAKE_BIN}:${PATH}" bash "${SCRIPT_DIR}/emdashctl" --instance site2 uninstall --purge-data --yes </dev/null >/dev/null 2>&1; then
	printf '[ERROR] uninstall --purge-data --yes should fail without --confirm-instance\n' >&2
	exit 1
fi

# 4b. Wrong --confirm-instance MUST fail
if PATH="${FAKE_BIN}:${PATH}" bash "${SCRIPT_DIR}/emdashctl" --instance site2 uninstall --purge-data --confirm-instance wrong </dev/null >/dev/null 2>&1; then
	printf '[ERROR] uninstall with mismatched --confirm-instance should fail\n' >&2
	exit 1
fi

# 4c. Unsafe ROOT_DIR=/data MUST fail
mkdir -p "${TEST_TMP_DIR}/etc-emdash/instances/badroot"
printf 'INSTANCE_NAME="badroot"\nINSTANCE_SLUG="badroot"\nROOT_DIR="/data"\n' >"${TEST_TMP_DIR}/etc-emdash/instances/badroot/emdash.env"
if PATH="${FAKE_BIN}:${PATH}" bash "${SCRIPT_DIR}/emdashctl" --instance badroot uninstall --purge-data --confirm-instance badroot </dev/null >/dev/null 2>&1; then
	printf '[ERROR] uninstall with unsafe ROOT_DIR=/data should fail\n' >&2
	exit 1
fi
rm -rf "${TEST_TMP_DIR}/etc-emdash/instances/badroot"

# 4d. Proper uninstall of site2 preserves default, custom conf.d snippet, and emdashctl binary
PATH="${FAKE_BIN}:${PATH}" bash "${SCRIPT_DIR}/emdashctl" --instance site2 uninstall --purge-data --confirm-instance site2 </dev/null >/dev/null
[[ ! -d "${TEST_TMP_DIR}/data-site2" ]]
[[ ! -d "${TEST_TMP_DIR}/etc-emdash/instances/site2" ]]
[[ ! -f "${TEST_TMP_DIR}/cron-site2" ]]
[[ ! -f "${TEST_TMP_DIR}/emdash-app-site2.service" ]]
[[ ! -f "${TEST_TMP_DIR}/etc-emdash/caddy/sites.d/site2.caddy" ]]
# Sibling & shared assets intact
[[ -d "${TEST_TMP_DIR}/data-default" ]]
[[ -f "${TEST_TMP_DIR}/etc-emdash/emdash.env" ]]
[[ -f "${TEST_TMP_DIR}/etc-emdash/caddy/sites.d/default.caddy" ]]
[[ -f "${TEST_TMP_DIR}/etc-emdash/caddy/conf.d/custom.caddy" ]]
[[ -x "${EMDASH_BIN_PATH}" ]]

# 4e. Uninstall final default instance removes emdashctl binary too
PATH="${FAKE_BIN}:${PATH}" bash "${SCRIPT_DIR}/emdashctl" uninstall --purge-data --confirm-instance default </dev/null >/dev/null
[[ ! -d "${TEST_TMP_DIR}/data-default" ]]
[[ ! -f "${TEST_TMP_DIR}/etc-emdash/emdash.env" ]]
[[ ! -f "${EMDASH_BIN_PATH}" ]]

printf '[INFO] multi-instance, modular caddy, update-cli, and uninstall regression checks passed\n'
