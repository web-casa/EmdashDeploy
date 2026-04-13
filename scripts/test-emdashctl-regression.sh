#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${SCRIPT_DIR}/emdashctl"

assert_contains() {
	local file="$1"
	local expected="$2"
	if ! grep -Fq "${expected}" "${file}"; then
		printf '[ERROR] expected fragment not found in %s: %s\n' "${file}" "${expected}" >&2
		sed -n '1,260p' "${file}" >&2
		exit 1
	fi
}

assert_equals_file() {
	local left="$1"
	local right="$2"
	if ! cmp -s "${left}" "${right}"; then
		printf '[ERROR] files differ: %s != %s\n' "${left}" "${right}" >&2
		diff -u "${left}" "${right}" >&2 || true
		exit 1
	fi
}

write_blog_like_config() {
	local file="$1"
	cat >"${file}" <<'EOF'
import node from "@astrojs/node";
import react from "@astrojs/react";
import { auditLogPlugin } from "@emdash-cms/plugin-audit-log";
import { defineConfig, fontProviders } from "astro/config";
import emdash, { local } from "emdash/astro";
import { sqlite } from "emdash/db";

export default defineConfig({
	output: "server",
	adapter: node({
		mode: "standalone",
	}),
	image: {
		layout: "constrained",
		responsiveStyles: true,
	},
	integrations: [
		react(),
		emdash({
			database: sqlite({ url: "file:./data.db" }),
			storage: local({
				directory: "./uploads",
				baseUrl: "/_emdash/api/media/file",
			}),
			plugins: [auditLogPlugin()],
		}),
	],
	fonts: [
		{
			provider: fontProviders.google(),
			name: "Inter",
			cssVariable: "--font-sans",
			weights: [400, 500, 600, 700],
			fallbacks: ["sans-serif"],
		},
	],
	devToolbar: { enabled: false },
});
EOF
}

test_render_site_astro_config_keeps_template_behavior() {
	local tmpdir config_path
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "${tmpdir}"' RETURN
	config_path="${tmpdir}/astro.config.mjs"

	write_blog_like_config "${config_path}"

	SITE_DIR="${tmpdir}"
	DB_DRIVER="postgres"
	SESSION_DRIVER="redis"
	STORAGE_DRIVER="s3"

	render_site_astro_config

	assert_contains "${config_path}" 'import { defineConfig, fontProviders, sessionDrivers } from "astro/config";'
	assert_contains "${config_path}" 'import emdash, { local, s3 } from "emdash/astro";'
	assert_contains "${config_path}" 'import { postgres } from "emdash/db";'
	assert_contains "${config_path}" 'siteUrl: process.env.EMDASH_SITE_URL || process.env.SITE_URL || undefined,'
	assert_contains "${config_path}" 'plugins: [auditLogPlugin()],'
	assert_contains "${config_path}" 'storage: s3({'
	assert_contains "${config_path}" 'database: postgres({'

	log "emdashctl regression: astro config patch passed"
	trap - RETURN
	rm -rf "${tmpdir}"
}

test_rollback_restores_scripts_directory() {
	local tmpdir rollback_dir
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "${tmpdir}"' RETURN

	ROOT_DIR="${tmpdir}/emdash"
	SITE_DIR="${ROOT_DIR}/app/site"
	SCRIPTS_DIR="${ROOT_DIR}/scripts"
	TMP_DIR="${ROOT_DIR}/tmp"
	APP_ENV_FILE="${ROOT_DIR}/etc/emdash.env"
	APP_SYSTEMD_UNIT="${ROOT_DIR}/etc/emdash-app.service"
	APP_RUN_USER="$(id -un)"
	APP_RUN_GROUP="$(id -gn)"

	mkdir -p "${SITE_DIR}" "${SCRIPTS_DIR}" "$(dirname "${APP_ENV_FILE}")"
	printf 'site-v1\n' >"${SITE_DIR}/version.txt"
	printf 'script-v1\n' >"${SCRIPTS_DIR}/emdash-build.sh"
	printf 'env-v1\n' >"${APP_ENV_FILE}"
	printf 'unit-v1\n' >"${APP_SYSTEMD_UNIT}"

	rollback_dir="$(create_site_rollback)"

	printf 'site-v2\n' >"${SITE_DIR}/version.txt"
	printf 'script-v2\n' >"${SCRIPTS_DIR}/emdash-build.sh"
	printf 'env-v2\n' >"${APP_ENV_FILE}"
	printf 'unit-v2\n' >"${APP_SYSTEMD_UNIT}"

	restore_site_rollback "${rollback_dir}"

	printf 'site-v1\n' >"${tmpdir}/expected-site.txt"
	printf 'script-v1\n' >"${tmpdir}/expected-script.txt"
	printf 'env-v1\n' >"${tmpdir}/expected-env.txt"
	printf 'unit-v1\n' >"${tmpdir}/expected-unit.txt"
	assert_equals_file "${SITE_DIR}/version.txt" "${tmpdir}/expected-site.txt"
	assert_equals_file "${SCRIPTS_DIR}/emdash-build.sh" "${tmpdir}/expected-script.txt"
	assert_equals_file "${APP_ENV_FILE}" "${tmpdir}/expected-env.txt"
	assert_equals_file "${APP_SYSTEMD_UNIT}" "${tmpdir}/expected-unit.txt"

	log "emdashctl regression: rollback restores runtime files"
	trap - RETURN
	rm -rf "${tmpdir}"
}

test_migrate_managed_script_paths_if_legacy() {
	local tmpdir
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "${tmpdir}"' RETURN

	ENV_FILE="${tmpdir}/emdash.env"
	cat >"${ENV_FILE}" <<EOF
ROOT_DIR="${tmpdir}/emdash"
SITE_DIR="${tmpdir}/emdash/app/site"
SCRIPTS_DIR="${tmpdir}/emdash/scripts"
TMP_DIR="${tmpdir}/emdash/tmp"
APP_ENV_FILE="${ENV_FILE}"
APP_SYSTEMD_SERVICE="emdash-app"
APP_SYSTEMD_UNIT="${tmpdir}/emdash/etc/emdash-app.service"
APP_BUILD_SCRIPT="${tmpdir}/emdash/app/site/emdash-build.sh"
APP_START_SCRIPT="${tmpdir}/emdash/app/site/emdash-start.sh"
APP_RUN_USER="$(id -un)"
APP_RUN_GROUP="$(id -gn)"
EOF

	load_env
	mkdir -p "${SITE_DIR}" "${SCRIPTS_DIR}" "$(dirname "${APP_SYSTEMD_UNIT}")"
	printf 'legacy-build\n' >"${APP_BUILD_SCRIPT}"
	printf 'legacy-start\n' >"${APP_START_SCRIPT}"
	cat >"${APP_SYSTEMD_UNIT}" <<EOF
[Service]
ExecStart=/usr/bin/bash ${APP_START_SCRIPT}
EOF

	migrate_managed_script_paths_if_legacy

	assert_contains "${APP_ENV_FILE}" "SCRIPTS_DIR=\"${SCRIPTS_DIR}\""
	assert_contains "${APP_ENV_FILE}" "APP_BUILD_SCRIPT=\"${SCRIPTS_DIR}/emdash-build.sh\""
	assert_contains "${APP_ENV_FILE}" "APP_START_SCRIPT=\"${SCRIPTS_DIR}/emdash-start.sh\""
	assert_contains "${APP_SYSTEMD_UNIT}" "ExecStart=/usr/bin/bash ${SCRIPTS_DIR}/emdash-start.sh"
	assert_contains "${SCRIPTS_DIR}/emdash-build.sh" 'legacy-build'
	assert_contains "${SCRIPTS_DIR}/emdash-start.sh" 'legacy-start'

	log "emdashctl regression: legacy script path migration passed"
	trap - RETURN
	rm -rf "${tmpdir}"
}

test_migrate_managed_script_paths_preserves_non_legacy_path() {
	local tmpdir custom_start
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "${tmpdir}"' RETURN

	custom_start="${tmpdir}/custom/start-custom.sh"
	ENV_FILE="${tmpdir}/emdash.env"
	cat >"${ENV_FILE}" <<EOF
ROOT_DIR="${tmpdir}/emdash"
SITE_DIR="${tmpdir}/emdash/app/site"
SCRIPTS_DIR="${tmpdir}/emdash/scripts"
TMP_DIR="${tmpdir}/emdash/tmp"
APP_ENV_FILE="${ENV_FILE}"
APP_SYSTEMD_SERVICE="emdash-app"
APP_SYSTEMD_UNIT="${tmpdir}/emdash/etc/emdash-app.service"
APP_BUILD_SCRIPT="${tmpdir}/emdash/app/site/emdash-build.sh"
APP_START_SCRIPT="${custom_start}"
APP_RUN_USER="$(id -un)"
APP_RUN_GROUP="$(id -gn)"
EOF

	load_env
	mkdir -p "${SITE_DIR}" "${SCRIPTS_DIR}" "$(dirname "${APP_SYSTEMD_UNIT}")" "$(dirname "${custom_start}")"
	printf 'legacy-build\n' >"${APP_BUILD_SCRIPT}"
	printf 'custom-start\n' >"${custom_start}"
	cat >"${APP_SYSTEMD_UNIT}" <<EOF
[Service]
ExecStart=/usr/bin/bash ${APP_START_SCRIPT}
EOF

	migrate_managed_script_paths_if_legacy

	assert_contains "${APP_ENV_FILE}" "APP_BUILD_SCRIPT=\"${SCRIPTS_DIR}/emdash-build.sh\""
	assert_contains "${APP_ENV_FILE}" "APP_START_SCRIPT=\"${custom_start}\""
	assert_contains "${APP_SYSTEMD_UNIT}" "ExecStart=/usr/bin/bash ${custom_start}"
	assert_contains "${SCRIPTS_DIR}/emdash-build.sh" 'legacy-build'

	log "emdashctl regression: partial legacy migration preserves non-legacy path"
	trap - RETURN
	rm -rf "${tmpdir}"
}

main() {
	test_render_site_astro_config_keeps_template_behavior
	test_rollback_restores_scripts_directory
	test_migrate_managed_script_paths_if_legacy
	test_migrate_managed_script_paths_preserves_non_legacy_path
	log "emdashctl regression checks passed"
}

main "$@"
