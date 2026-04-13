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
	if ! grep -Fqx "${expected}" "${file}"; then
		printf '[ERROR] expected line not found in %s: %s\n' "${file}" "${expected}" >&2
		printf '[ERROR] file contents:\n' >&2
		sed -n '1,220p' "${file}" >&2
		exit 1
	fi
}

assert_has_fragment() {
	local file="$1"
	local expected="$2"
	if ! grep -Fq "${expected}" "${file}"; then
		printf '[ERROR] expected fragment not found in %s: %s\n' "${file}" "${expected}" >&2
		printf '[ERROR] file contents:\n' >&2
		sed -n '1,220p' "${file}" >&2
		exit 1
	fi
}

assert_not_prefix() {
	local value="$1"
	local prefix="$2"
	if [[ "${value}" == "${prefix}"* ]]; then
		printf '[ERROR] value unexpectedly uses prefix %s: %s\n' "${prefix}" "${value}" >&2
		exit 1
	fi
}

setup_case() {
	local root_dir="$1"
	local domain="$2"
	local admin_email="$3"
	local use_caddy="$4"
	local enable_https="$5"

	init_defaults
	ROOT_DIR="${root_dir}"
	CONFIG_DIR="${ROOT_DIR}/etc"
	OS_LABEL="test"
	CONTAINER_RUNTIME="docker"
	PUBLIC_IPV4="203.0.113.10"
	PUBLIC_IPV6=""
	POSTGRES_SERVICE="postgresql"
	REDIS_SERVICE="redis"
	DOMAIN="${domain}"
	ADMIN_EMAIL="${admin_email}"
	USE_CADDY="${use_caddy}"
	ENABLE_HTTPS="${enable_https}"

	derive_paths
	validate_config
	prepare_layout
	ensure_dir "${SITE_DIR}"
	cat >"${SITE_DIR}/astro.config.mjs" <<'EOF'
import node from "@astrojs/node";
import react from "@astrojs/react";
import { defineConfig } from "astro/config";
import emdash, { local } from "emdash/astro";
import { sqlite } from "emdash/db";

export default defineConfig({
	output: "server",
	adapter: node({
		mode: "standalone",
	}),
	integrations: [
		react(),
		emdash({
			database: sqlite({ url: "file:./data.db" }),
			storage: local({
				directory: "./uploads",
				baseUrl: "/_emdash/api/media/file",
			}),
		}),
	],
	devToolbar: { enabled: false },
});
EOF
	render_astro_config
	render_app_env
}

run_case_caddy_https() {
	local tmpdir
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "${tmpdir}"' RETURN

	setup_case "${tmpdir}/emdash" "cms.example.com" "ops@example.com" "1" "1"

	assert_contains "${APP_ENV_FILE}" 'APP_PUBLIC_URL="https://cms.example.com"'
	assert_contains "${APP_ENV_FILE}" 'EMDASH_SITE_URL="https://cms.example.com"'
	assert_contains "${APP_ENV_FILE}" 'SITE_URL="https://cms.example.com"'
	assert_has_fragment "${SITE_DIR}/astro.config.mjs" 'siteUrl: process.env.EMDASH_SITE_URL || process.env.SITE_URL || undefined,'
	assert_not_prefix "${APP_BUILD_SCRIPT}" "${SITE_DIR}/"
	assert_not_prefix "${APP_START_SCRIPT}" "${SITE_DIR}/"

	log "passkey origin regression: caddy https case passed"
	trap - RETURN
	rm -rf "${tmpdir}"
}

run_case_direct_http() {
	local tmpdir
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "${tmpdir}"' RETURN

	setup_case "${tmpdir}/emdash" "" "" "0" "0"

	assert_contains "${APP_ENV_FILE}" 'APP_PUBLIC_URL="http://203.0.113.10:3000"'
	assert_contains "${APP_ENV_FILE}" 'EMDASH_SITE_URL="http://203.0.113.10:3000"'
	assert_contains "${APP_ENV_FILE}" 'SITE_URL="http://203.0.113.10:3000"'
	assert_has_fragment "${SITE_DIR}/astro.config.mjs" 'siteUrl: process.env.EMDASH_SITE_URL || process.env.SITE_URL || undefined,'
	assert_not_prefix "${APP_BUILD_SCRIPT}" "${SITE_DIR}/"
	assert_not_prefix "${APP_START_SCRIPT}" "${SITE_DIR}/"

	log "passkey origin regression: direct http case passed"
	trap - RETURN
	rm -rf "${tmpdir}"
}

run_case_preserve_uses_env_origin() {
	local tmpdir original_config
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "${tmpdir}"' RETURN

	setup_case "${tmpdir}/emdash" "cms.example.com" "ops@example.com" "1" "1"
	SITE_SYNC_MODE="preserve"
	original_config="${tmpdir}/astro.config.original.mjs"
	cp "${SITE_DIR}/astro.config.mjs" "${original_config}"

	render_astro_config
	render_app_env

	assert_contains "${APP_ENV_FILE}" 'APP_PUBLIC_URL="https://cms.example.com"'
	assert_contains "${APP_ENV_FILE}" 'EMDASH_SITE_URL="https://cms.example.com"'
	assert_contains "${APP_ENV_FILE}" 'SITE_URL="https://cms.example.com"'
	assert_not_prefix "${APP_BUILD_SCRIPT}" "${SITE_DIR}/"
	assert_not_prefix "${APP_START_SCRIPT}" "${SITE_DIR}/"
	if ! cmp -s "${SITE_DIR}/astro.config.mjs" "${original_config}"; then
		printf '[ERROR] astro.config.mjs changed in preserve mode\n' >&2
		diff -u "${original_config}" "${SITE_DIR}/astro.config.mjs" >&2 || true
		exit 1
	fi

	log "passkey origin regression: preserve mode uses env origin without mutating site config"
	trap - RETURN
	rm -rf "${tmpdir}"
}

main() {
	run_case_caddy_https
	run_case_direct_http
	run_case_preserve_uses_env_origin
	log "passkey origin regression checks passed"
}

main "$@"
