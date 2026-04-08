#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/os.sh
source "${SCRIPT_DIR}/lib/os.sh"
# shellcheck source=lib/prompt.sh
source "${SCRIPT_DIR}/lib/prompt.sh"
# shellcheck source=lib/network.sh
source "${SCRIPT_DIR}/lib/network.sh"
# shellcheck source=lib/render.sh
source "${SCRIPT_DIR}/lib/render.sh"

usage() {
	cat <<'EOF'
EmDash installer

用法:
  bash install-emdash.sh [--non-interactive] [--write-only] [--activate]

参数:
  --non-interactive  仅使用环境变量和默认值，不提问
  --write-only       只生成配置和项目文件，不启动 compose
  --activate         生成后立即 build / up
  -h, --help         显示帮助

	常用环境变量:
	  EMDASH_INSTALL_TEMPLATE
	  EMDASH_INSTALL_ROOT_DIR
	  EMDASH_INSTALL_DOMAIN
	  EMDASH_INSTALL_ADMIN_EMAIL
	  EMDASH_INSTALL_DB_DRIVER
	  EMDASH_INSTALL_SESSION_DRIVER
	  EMDASH_INSTALL_STORAGE_DRIVER
	  EMDASH_INSTALL_USE_CADDY
	  EMDASH_INSTALL_ENABLE_HTTPS
	  EMDASH_INSTALL_APP_IMAGE
	  EMDASH_INSTALL_APP_BASE_IMAGE
	  EMDASH_INSTALL_PG_PASSWORD
	  EMDASH_INSTALL_REDIS_PASSWORD
EOF
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--non-interactive)
			NON_INTERACTIVE=1
			;;
		--write-only)
			WRITE_ONLY=1
			;;
		--activate)
			ACTIVATE_STACK=1
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			fail "未知参数: $1"
			;;
		esac
		shift
	done
}

collect_configuration() {
	if [[ "${NON_INTERACTIVE}" == "1" ]]; then
		log "非交互模式，使用环境变量和默认值"
		return
	fi

	prompt_value PROJECT_NAME "项目名" "${PROJECT_NAME}"
	prompt_choice TEMPLATE "模板" "starter blog marketing portfolio blank" "${TEMPLATE}"
	prompt_value ROOT_DIR "安装根目录" "${ROOT_DIR}"
	prompt_value TIMEZONE "时区" "${TIMEZONE}"

	prompt_yes_no USE_CADDY "是否安装并配置 Caddy" "${USE_CADDY}"
	if [[ "${USE_CADDY}" == "1" ]]; then
		prompt_yes_no ENABLE_HTTPS "是否启用 HTTPS" "${ENABLE_HTTPS}"
		prompt_value DOMAIN "站点域名" "${DOMAIN}"
		prompt_value ADMIN_EMAIL "Caddy/证书邮箱" "${ADMIN_EMAIL}"
	fi

	prompt_choice DB_DRIVER "数据库" "sqlite postgres" "${DB_DRIVER}"
	if [[ "${DB_DRIVER}" == "postgres" ]]; then
		prompt_value PG_DB_NAME "PostgreSQL 数据库名" "${PG_DB_NAME}"
		prompt_value PG_DB_USER "PostgreSQL 用户名" "${PG_DB_USER}"
		prompt_secret PG_DB_PASSWORD "PostgreSQL 密码" "${PG_DB_PASSWORD}"
	fi

	prompt_choice SESSION_DRIVER "Session 驱动" "file redis" "${SESSION_DRIVER}"
	if [[ "${SESSION_DRIVER}" == "redis" ]]; then
		prompt_secret REDIS_PASSWORD "Redis 密码(可留空)" "${REDIS_PASSWORD}"
	fi

	prompt_choice STORAGE_DRIVER "媒体存储" "local s3" "${STORAGE_DRIVER}"
	if [[ "${STORAGE_DRIVER}" == "s3" ]]; then
		prompt_choice S3_PROVIDER "S3 预设" "r2 aws b2 alibaba custom" "${S3_PROVIDER}"
		prompt_value S3_ENDPOINT "S3 Endpoint" "${S3_ENDPOINT}"
		prompt_value S3_REGION "S3 Region" "${S3_REGION}"
		prompt_value S3_BUCKET "S3 Bucket" "${S3_BUCKET}"
		prompt_value S3_ACCESS_KEY_ID "S3 Access Key ID" "${S3_ACCESS_KEY_ID}"
		prompt_secret S3_SECRET_ACCESS_KEY "S3 Secret Access Key" "${S3_SECRET_ACCESS_KEY}"
		prompt_value S3_PUBLIC_URL "S3 Public URL(可留空)" "${S3_PUBLIC_URL}"
	fi

	prompt_yes_no BACKUP_ENABLED "是否启用自动备份" "${BACKUP_ENABLED}"
	if [[ "${BACKUP_ENABLED}" == "1" ]]; then
		prompt_value BACKUP_SCHEDULE "备份 cron" "${BACKUP_SCHEDULE}"
		prompt_value BACKUP_KEEP_LOCAL "本地保留份数" "${BACKUP_KEEP_LOCAL}"
		prompt_choice BACKUP_TARGET_TYPE "备份远端目标" "local s3" "${BACKUP_TARGET_TYPE}"
		if [[ "${BACKUP_TARGET_TYPE}" == "s3" ]]; then
			prompt_value BACKUP_S3_ENDPOINT "备份 S3 Endpoint" "${BACKUP_S3_ENDPOINT}"
			prompt_value BACKUP_S3_REGION "备份 S3 Region" "${BACKUP_S3_REGION}"
			prompt_value BACKUP_S3_BUCKET "备份 S3 Bucket" "${BACKUP_S3_BUCKET}"
			prompt_value BACKUP_S3_ACCESS_KEY_ID "备份 S3 Access Key ID" "${BACKUP_S3_ACCESS_KEY_ID}"
			prompt_secret BACKUP_S3_SECRET_ACCESS_KEY "备份 S3 Secret Access Key" "${BACKUP_S3_SECRET_ACCESS_KEY}"
			prompt_value BACKUP_S3_PREFIX "备份 S3 Prefix" "${BACKUP_S3_PREFIX}"
		fi
	fi

	prompt_yes_no OPTIMIZATION_ENABLED "是否启用保守优化" "${OPTIMIZATION_ENABLED}"
}

wait_for_stack_ready() {
	local local_probe_host="${APP_BIND_HOST}"
	local app_health_url=""
	local public_health_url="${APP_PUBLIC_URL}/healthz"
	local setup_status_url="${APP_PUBLIC_URL}/_emdash/api/setup/status"

	if [[ "${local_probe_host}" == "0.0.0.0" ]]; then
		local_probe_host="127.0.0.1"
	fi
	app_health_url="http://${local_probe_host}:${APP_PORT}/healthz"

	log "等待 EmDash 应用健康检查通过"
	if ! wait_for_http_ok "${app_health_url}" 120 2; then
		warn "应用本地健康检查未在预期时间内通过。"
		return 1
	fi

	if [[ "${USE_CADDY}" == "1" ]]; then
		log "等待 Caddy 代理健康检查通过"
		if ! wait_for_http_ok "${public_health_url}" 120 2; then
			warn "Caddy 代理健康检查未在预期时间内通过。"
			return 1
		fi
	fi

	log "获取 Setup 状态"
	http_get_json "${setup_status_url}" >"${ROOT_DIR}/setup-status.json" || warn "未能读取 setup status。"
	return 0
}

print_setup_guidance() {
	local setup_file="${ROOT_DIR}/setup-status.json"
	[[ -f "${setup_file}" ]] || return 0

	python3 - "${setup_file}" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    data = json.load(open(path))
    payload = data.get("data", {})
    if payload.get("needsSetup") is False:
        print("[INFO] Setup 状态: 已完成")
    else:
        step = payload.get("step", "unknown")
        auth_mode = payload.get("authMode", "passkey")
        print(f"[INFO] Setup 状态: 需要初始化，当前步骤 {step}，认证模式 {auth_mode}")
        print("[INFO] 请打开后台地址完成 Setup Wizard。")
except Exception:
    print("[WARN] 无法解析 setup-status.json")
PY
}

main() {
	parse_args "$@"
	require_root
	init_defaults
	apply_env_overrides
	detect_os_family
	choose_container_runtime
	collect_configuration
	derive_paths
	validate_config

	if [[ "${WRITE_ONLY}" != "1" ]]; then
		install_runtime_stack
	else
		warn "write-only 模式下将跳过运行时安装、对象存储上传测试和 Caddy 安装。"
	fi

	log "检测公网 IP"
	detect_public_ips
	refresh_app_public_url

	if [[ -n "${DOMAIN}" ]]; then
		validate_domain_requirements
	fi

	if [[ "${STORAGE_DRIVER}" == "s3" && "${WRITE_ONLY}" != "1" ]]; then
		test_s3_storage
	fi

	prepare_layout
	clone_template_repo
	patch_template_package_json
	render_astro_config
	render_app_dockerfile
	render_app_entrypoint
	render_health_endpoint
	render_compose_file
	render_compose_env
	render_install_yaml
	render_caddy_file
	render_first_run_note
	install_emdashctl_script
	if [[ "${WRITE_ONLY}" != "1" ]]; then
		install_backup_schedule
	fi
	if [[ "${USE_CADDY}" == "1" && "${WRITE_ONLY}" != "1" ]]; then
		install_caddy_package
	fi

	if [[ "${WRITE_ONLY}" == "1" ]]; then
		print_summary "已生成配置，未启动 compose。"
		exit 0
	fi

	if [[ "${ACTIVATE_STACK}" == "1" ]]; then
		ensure_runtime_present
		if [[ "${USE_CADDY}" != "1" ]]; then
			open_required_firewall_ports
		fi
		start_stack
		if [[ "${USE_CADDY}" == "1" ]]; then
			activate_caddy_service
		fi
		wait_for_stack_ready || warn "启动后健康检查未完全通过，请使用 emdashctl doctor 进一步排查。"
		print_setup_guidance
		print_summary "已生成配置并启动 compose。"
		exit 0
	fi

	print_summary "已生成配置。设置 ACTIVATE=1 或传入 --activate 可立即启动。"
}

main "$@"
