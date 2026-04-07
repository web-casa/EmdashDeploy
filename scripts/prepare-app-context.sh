#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=../lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=../lib/render.sh
source "${SCRIPT_DIR}/lib/render.sh"

main() {
	init_defaults
	apply_env_overrides

	# App image publishing is only safe by default for the local SQLite profile.
	TEMPLATE="${EMDASH_INSTALL_TEMPLATE:-${TEMPLATE}}"
	DB_DRIVER="${EMDASH_INSTALL_DB_DRIVER:-sqlite}"
	SESSION_DRIVER="${EMDASH_INSTALL_SESSION_DRIVER:-file}"
	STORAGE_DRIVER="${EMDASH_INSTALL_STORAGE_DRIVER:-local}"
	USE_CADDY="0"
	ENABLE_HTTPS="0"
	APP_IMAGE=""
	CONTAINER_RUNTIME="docker"
	OS_LABEL="github-actions"
	PUBLIC_IPV4=""
	PUBLIC_IPV6=""
	ROOT_DIR="${BUILD_ROOT:-$(mktemp -d)/emdash-build}"
	CONFIG_DIR="${ROOT_DIR}/etc"

	if [[ "${DB_DRIVER}" != "sqlite" || "${SESSION_DRIVER}" != "file" || "${STORAGE_DRIVER}" != "local" ]]; then
		fail "当前 app image workflow 仅支持 sqlite + file + local 组合，以避免将环境密钥写入公共镜像。"
	fi

	derive_paths
	validate_config
	prepare_layout
	clone_template_repo
	patch_template_package_json
	render_astro_config
	render_app_dockerfile
	render_app_entrypoint
	render_health_endpoint

	cat >"${SITE_DIR}/.dockerignore" <<'EOF'
.git
.github
node_modules
dist
.env
EOF

	log "已生成 app image build context: ${SITE_DIR}"

	if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
		{
			printf 'site_dir=%s\n' "${SITE_DIR}"
			printf 'template=%s\n' "${TEMPLATE}"
			printf 'profile=%s\n' "${TEMPLATE}-sqlite-file-local"
		} >>"${GITHUB_OUTPUT}"
	else
		printf '%s\n' "${SITE_DIR}"
	fi
}

main "$@"
