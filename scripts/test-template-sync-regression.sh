#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=../lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=../lib/i18n.sh
source "${SCRIPT_DIR}/lib/i18n.sh"
# shellcheck source=../lib/render.sh
source "${SCRIPT_DIR}/lib/render.sh"

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

test_render_preserves_template_config() {
	local tmpdir config_path
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "${tmpdir}"' RETURN
	config_path="${tmpdir}/astro.config.mjs"

	write_blog_like_config "${config_path}"

	SITE_DIR="${tmpdir}"
	SITE_SYNC_MODE="sync"
	DB_DRIVER="postgres"
	SESSION_DRIVER="redis"
	STORAGE_DRIVER="s3"

	render_astro_config

	assert_contains "${config_path}" 'import { defineConfig, fontProviders, sessionDrivers } from "astro/config";'
	assert_contains "${config_path}" 'import emdash, { local, s3 } from "emdash/astro";'
	assert_contains "${config_path}" 'import { postgres } from "emdash/db";'
	assert_contains "${config_path}" 'sessionDrivers.redis({'
	assert_contains "${config_path}" 'siteUrl: process.env.EMDASH_SITE_URL || process.env.SITE_URL || undefined,'
	assert_contains "${config_path}" 'database: postgres({'
	assert_contains "${config_path}" 'storage: s3({'
	assert_contains "${config_path}" 'plugins: [auditLogPlugin()],'
	assert_contains "${config_path}" 'provider: fontProviders.google(),'

	log "template config patch regression: sync case passed"
	trap - RETURN
	rm -rf "${tmpdir}"
}

test_render_preserve_mode_leaves_config_untouched() {
	local tmpdir config_path package_path healthz_path original_copy original_package original_healthz
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "${tmpdir}"' RETURN
	config_path="${tmpdir}/astro.config.mjs"
	package_path="${tmpdir}/package.json"
	healthz_path="${tmpdir}/src/pages/healthz.ts"
	original_copy="${tmpdir}/astro.config.original.mjs"
	original_package="${tmpdir}/package.original.json"
	original_healthz="${tmpdir}/healthz.original.ts"

	write_blog_like_config "${config_path}"
	mkdir -p "${tmpdir}/src/pages"
	cat >"${package_path}" <<'EOF'
{"name":"custom-site","packageManager":"pnpm@9.0.0"}
EOF
	cat >"${healthz_path}" <<'EOF'
export const GET = () => new Response("CUSTOM", { status: 200 });
EOF
	cp "${config_path}" "${original_copy}"
	cp "${package_path}" "${original_package}"
	cp "${healthz_path}" "${original_healthz}"

	SITE_DIR="${tmpdir}"
	SITE_SYNC_MODE="preserve"
	PROJECT_NAME="emdash"
	DB_DRIVER="postgres"
	SESSION_DRIVER="redis"
	STORAGE_DRIVER="s3"

	render_astro_config
	patch_template_package_json
	render_health_endpoint
	assert_equals_file "${config_path}" "${original_copy}"
	assert_equals_file "${package_path}" "${original_package}"
	assert_equals_file "${healthz_path}" "${original_healthz}"

	log "template config patch regression: preserve case passed"
	trap - RETURN
	rm -rf "${tmpdir}"
}

test_prepare_site_directory_rejects_mixed_template_state() {
	local tmpdir result
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "${tmpdir}"' RETURN

	init_defaults
	ROOT_DIR="${tmpdir}/emdash"
	CONFIG_DIR="${ROOT_DIR}/etc"
	derive_paths
	prepare_layout
	ensure_dir "${SITE_DIR}"
	cat >"${SITE_DIR}/package.json" <<'EOF'
{"name":"existing-site"}
EOF
	cat >"${SITE_DIR}/astro.config.mjs" <<'EOF'
export default {};
EOF
	cat >"${INSTALL_YAML}" <<'EOF'
version: 1
project:
  template: starter
database:
  driver: sqlite
session:
  driver: file
storage:
  driver: local
EOF

	TEMPLATE="blog"
	DB_DRIVER="sqlite"
	SESSION_DRIVER="file"
	STORAGE_DRIVER="local"
	FORCE_SYNC_TEMPLATE="0"

	if ( prepare_site_directory ) >/dev/null 2>&1; then
		printf '[ERROR] prepare_site_directory unexpectedly allowed template mismatch\n' >&2
		exit 1
	fi

	log "template sync regression: mismatch guard passed"
	trap - RETURN
	rm -rf "${tmpdir}"
}

test_prepare_site_directory_rejects_unknown_existing_metadata() {
	local tmpdir
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "${tmpdir}"' RETURN

	init_defaults
	ROOT_DIR="${tmpdir}/emdash"
	CONFIG_DIR="${ROOT_DIR}/etc"
	derive_paths
	prepare_layout
	ensure_dir "${SITE_DIR}"
	cat >"${SITE_DIR}/package.json" <<'EOF'
{"name":"existing-site"}
EOF
	cat >"${SITE_DIR}/astro.config.mjs" <<'EOF'
export default {};
EOF

	TEMPLATE="starter"
	DB_DRIVER="sqlite"
	SESSION_DRIVER="file"
	STORAGE_DRIVER="local"
	FORCE_SYNC_TEMPLATE="0"

	if ( prepare_site_directory ) >/dev/null 2>&1; then
		printf '[ERROR] prepare_site_directory unexpectedly allowed unknown existing metadata\n' >&2
		exit 1
	fi

	log "template sync regression: unknown metadata guard passed"
	trap - RETURN
	rm -rf "${tmpdir}"
}

test_activation_rollback_restores_runtime_files() {
	local tmpdir rollback_dir
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "${tmpdir}"' RETURN

	ROOT_DIR="${tmpdir}/emdash"
	SITE_DIR="${ROOT_DIR}/app/site"
	SCRIPTS_DIR="${ROOT_DIR}/scripts"
	TMP_DIR="${ROOT_DIR}/tmp"
	APP_ENV_FILE="${ROOT_DIR}/etc/emdash.env"
	APP_SYSTEMD_UNIT="${ROOT_DIR}/etc/emdash-app.service"
	INSTALL_YAML="${ROOT_DIR}/etc/install.yml"
	CADDYFILE_PATH="${ROOT_DIR}/etc/caddy/Caddyfile"
	SYSTEM_CADDYFILE="${ROOT_DIR}/system/etc/caddy/Caddyfile"
	BACKUP_CRON_FILE="${ROOT_DIR}/system/etc/cron.d/emdash-backup"
	APP_RUN_USER="$(id -un)"
	APP_RUN_GROUP="$(id -gn)"
	USE_CADDY="1"
	BACKUP_ENABLED="1"

	mkdir -p "${SITE_DIR}" "${SCRIPTS_DIR}" "$(dirname "${APP_ENV_FILE}")" "$(dirname "${CADDYFILE_PATH}")" "$(dirname "${SYSTEM_CADDYFILE}")" "$(dirname "${BACKUP_CRON_FILE}")"
	printf 'site-v1\n' >"${SITE_DIR}/version.txt"
	printf 'script-v1\n' >"${SCRIPTS_DIR}/emdash-build.sh"
	printf 'env-v1\n' >"${APP_ENV_FILE}"
	printf 'unit-v1\n' >"${APP_SYSTEMD_UNIT}"
	printf 'install-v1\n' >"${INSTALL_YAML}"
	printf 'caddy-managed-v1\n' >"${CADDYFILE_PATH}"
	printf 'caddy-system-v1\n' >"${SYSTEM_CADDYFILE}"
	printf 'cron-v1\n' >"${BACKUP_CRON_FILE}"

	rollback_dir="$(create_activation_rollback)"

	printf 'site-v2\n' >"${SITE_DIR}/version.txt"
	printf 'script-v2\n' >"${SCRIPTS_DIR}/emdash-build.sh"
	printf 'env-v2\n' >"${APP_ENV_FILE}"
	printf 'unit-v2\n' >"${APP_SYSTEMD_UNIT}"
	printf 'install-v2\n' >"${INSTALL_YAML}"
	printf 'caddy-managed-v2\n' >"${CADDYFILE_PATH}"
	printf 'caddy-system-v2\n' >"${SYSTEM_CADDYFILE}"
	printf 'cron-v2\n' >"${BACKUP_CRON_FILE}"

	restore_activation_rollback "${rollback_dir}"

	printf 'site-v1\n' >"${tmpdir}/expected-site.txt"
	printf 'script-v1\n' >"${tmpdir}/expected-script.txt"
	printf 'env-v1\n' >"${tmpdir}/expected-env.txt"
	printf 'unit-v1\n' >"${tmpdir}/expected-unit.txt"
	printf 'install-v1\n' >"${tmpdir}/expected-install.txt"
	printf 'caddy-managed-v1\n' >"${tmpdir}/expected-caddy-managed.txt"
	printf 'caddy-system-v1\n' >"${tmpdir}/expected-caddy-system.txt"
	printf 'cron-v1\n' >"${tmpdir}/expected-cron.txt"
	assert_equals_file "${SITE_DIR}/version.txt" "${tmpdir}/expected-site.txt"
	assert_equals_file "${SCRIPTS_DIR}/emdash-build.sh" "${tmpdir}/expected-script.txt"
	assert_equals_file "${APP_ENV_FILE}" "${tmpdir}/expected-env.txt"
	assert_equals_file "${APP_SYSTEMD_UNIT}" "${tmpdir}/expected-unit.txt"
	assert_equals_file "${INSTALL_YAML}" "${tmpdir}/expected-install.txt"
	assert_equals_file "${CADDYFILE_PATH}" "${tmpdir}/expected-caddy-managed.txt"
	assert_equals_file "${SYSTEM_CADDYFILE}" "${tmpdir}/expected-caddy-system.txt"
	assert_equals_file "${BACKUP_CRON_FILE}" "${tmpdir}/expected-cron.txt"

	log "template sync regression: activation rollback restores runtime files"
	trap - RETURN
	rm -rf "${tmpdir}"
}

main() {
	test_render_preserves_template_config
	test_render_preserve_mode_leaves_config_untouched
	test_prepare_site_directory_rejects_mixed_template_state
	test_prepare_site_directory_rejects_unknown_existing_metadata
	test_activation_rollback_restores_runtime_files
	log "template sync regression checks passed"
}

main "$@"
