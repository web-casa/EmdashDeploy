#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/i18n.sh
source "${SCRIPT_DIR}/lib/i18n.sh"
# shellcheck source=lib/os.sh
source "${SCRIPT_DIR}/lib/os.sh"
# shellcheck source=lib/prompt.sh
source "${SCRIPT_DIR}/lib/prompt.sh"
# shellcheck source=lib/network.sh
source "${SCRIPT_DIR}/lib/network.sh"
# shellcheck source=lib/render.sh
source "${SCRIPT_DIR}/lib/render.sh"

usage() {
	print_usage
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--lang=*)
			EMDASH_INSTALL_LANG="$(normalize_install_lang "${1#--lang=}")"
			export EMDASH_INSTALL_LANG
			;;
		--lang)
			shift
			[[ $# -gt 0 ]] || fail "Missing value for --lang"
			EMDASH_INSTALL_LANG="$(normalize_install_lang "$1")"
			export EMDASH_INSTALL_LANG
			;;
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
			fail "$(ti unknown_arg) $1"
			;;
		esac
		shift
	done
}

collect_configuration() {
	if [[ "${NON_INTERACTIVE}" == "1" ]]; then
		log "$(ti non_interactive_mode)"
		return
	fi

	prompt_value PROJECT_NAME "$(ti project_name)" "${PROJECT_NAME}"
	prompt_choice TEMPLATE "$(ti template)" "blog marketing portfolio blank" "${TEMPLATE}"
	prompt_value ROOT_DIR "$(ti root_dir)" "${ROOT_DIR}"
	prompt_value TIMEZONE "$(ti timezone)" "${TIMEZONE}"

	prompt_yes_no USE_CADDY "$(ti use_caddy)" "${USE_CADDY}"
	if [[ "${USE_CADDY}" == "1" ]]; then
		prompt_yes_no ENABLE_HTTPS "$(ti enable_https)" "${ENABLE_HTTPS}"
		prompt_value DOMAIN "$(ti domain)" "${DOMAIN}"
		prompt_value ADMIN_EMAIL "$(ti admin_email)" "${ADMIN_EMAIL}"
		if [[ "${ENABLE_HTTPS}" == "1" && "${WRITE_ONLY}" != "1" ]]; then
			log "$(ti detect_public_ip)"
			detect_public_ips
			if [[ -n "${PUBLIC_IPV4:-}" ]]; then
				log "$(ti https_public_ip_intro): ${PUBLIC_IPV4}"
			fi
			if [[ -n "${PUBLIC_IPV6:-}" ]]; then
				log "$(ti https_public_ip_intro) (IPv6): ${PUBLIC_IPV6}"
			fi
			if [[ -z "${PUBLIC_IPV4:-}" && -z "${PUBLIC_IPV6:-}" ]]; then
				warn "$(ti https_ip_unavailable)"
			else
				log "$(ti https_dns_hint)"
			fi
			prompt_confirm_dns_ready
		fi
	fi

	prompt_choice DB_DRIVER "$(ti db_driver)" "sqlite postgres" "${DB_DRIVER}"
	if [[ "${DB_DRIVER}" == "postgres" ]]; then
		prompt_value PG_DB_NAME "$(ti pg_db_name)" "${PG_DB_NAME}"
		prompt_value PG_DB_USER "$(ti pg_db_user)" "${PG_DB_USER}"
		prompt_secret PG_DB_PASSWORD "$(ti pg_db_password)" "${PG_DB_PASSWORD}"
	fi

	prompt_choice SESSION_DRIVER "$(ti session_driver)" "file redis" "${SESSION_DRIVER}"
	if [[ "${SESSION_DRIVER}" == "redis" ]]; then
		prompt_secret REDIS_PASSWORD "$(ti redis_password)" "${REDIS_PASSWORD}"
	fi

	prompt_choice STORAGE_DRIVER "$(ti storage_driver)" "local s3" "${STORAGE_DRIVER}"
	if [[ "${STORAGE_DRIVER}" == "s3" ]]; then
		prompt_choice S3_PROVIDER "$(ti s3_provider)" "r2 aws b2 alibaba custom" "${S3_PROVIDER}"
		prompt_value S3_ENDPOINT "$(ti s3_endpoint)" "${S3_ENDPOINT}"
		prompt_value S3_REGION "$(ti s3_region)" "${S3_REGION}"
		prompt_value S3_BUCKET "$(ti s3_bucket)" "${S3_BUCKET}"
		prompt_value S3_ACCESS_KEY_ID "$(ti s3_access_key)" "${S3_ACCESS_KEY_ID}"
		prompt_secret S3_SECRET_ACCESS_KEY "$(ti s3_secret_key)" "${S3_SECRET_ACCESS_KEY}"
		prompt_value S3_PUBLIC_URL "$(ti s3_public_url)" "${S3_PUBLIC_URL}"
	fi

	prompt_yes_no BACKUP_ENABLED "$(ti backup_enabled)" "${BACKUP_ENABLED}"
	if [[ "${BACKUP_ENABLED}" == "1" ]]; then
		prompt_value BACKUP_SCHEDULE "$(ti backup_schedule)" "${BACKUP_SCHEDULE}"
		prompt_value BACKUP_KEEP_LOCAL "$(ti backup_keep_local)" "${BACKUP_KEEP_LOCAL}"
		prompt_choice BACKUP_TARGET_TYPE "$(ti backup_target)" "local s3" "${BACKUP_TARGET_TYPE}"
		if [[ "${BACKUP_TARGET_TYPE}" == "s3" ]]; then
			prompt_value BACKUP_S3_ENDPOINT "$(ti backup_s3_endpoint)" "${BACKUP_S3_ENDPOINT}"
			prompt_value BACKUP_S3_REGION "$(ti backup_s3_region)" "${BACKUP_S3_REGION}"
			prompt_value BACKUP_S3_BUCKET "$(ti backup_s3_bucket)" "${BACKUP_S3_BUCKET}"
			prompt_value BACKUP_S3_ACCESS_KEY_ID "$(ti backup_s3_access_key)" "${BACKUP_S3_ACCESS_KEY_ID}"
			prompt_secret BACKUP_S3_SECRET_ACCESS_KEY "$(ti backup_s3_secret_key)" "${BACKUP_S3_SECRET_ACCESS_KEY}"
			prompt_value BACKUP_S3_PREFIX "$(ti backup_s3_prefix)" "${BACKUP_S3_PREFIX}"
		fi
	fi

	prompt_yes_no OPTIMIZATION_ENABLED "$(ti optimization_enabled)" "${OPTIMIZATION_ENABLED}"
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

	log "$(ti wait_app_health)"
	if ! wait_for_http_ok "${app_health_url}" 120 2; then
		warn "$(ti app_health_warn)"
		return 1
	fi

	if [[ "${USE_CADDY}" == "1" ]]; then
		log "$(ti wait_proxy_health)"
		if ! wait_for_http_ok "${public_health_url}" 120 2; then
			warn "$(ti proxy_health_warn)"
			return 1
		fi
	fi

	log "$(ti fetch_setup_status)"
	http_get_json "${setup_status_url}" >"${ROOT_DIR}/setup-status.json" || warn "setup status unavailable."
	return 0
}

print_setup_guidance() {
	local setup_file="${ROOT_DIR}/setup-status.json"
	[[ -f "${setup_file}" ]] || return 0

		python3 - "${setup_file}" "${EMDASH_INSTALL_LANG:-en}" <<'PY'
import json
import sys

path = sys.argv[1]
lang = sys.argv[2]
messages = {
    "en": {
        "done": "[INFO] Setup status: complete",
        "needs": "[INFO] Setup status: setup required, current step {step}, auth mode {auth_mode}",
        "open_admin": "[INFO] Open the admin URL to complete the Setup Wizard.",
        "parse_warn": "[WARN] Unable to parse setup-status.json",
    },
    "ja": {
        "done": "[INFO] セットアップ状態: 完了",
        "needs": "[INFO] セットアップ状態: 初期化が必要です。現在のステップ {step}、認証モード {auth_mode}",
        "open_admin": "[INFO] 管理画面を開いて Setup Wizard を完了してください。",
        "parse_warn": "[WARN] setup-status.json を解析できません",
    },
    "ko": {
        "done": "[INFO] 설정 상태: 완료",
        "needs": "[INFO] 설정 상태: 초기 설정이 필요합니다. 현재 단계 {step}, 인증 모드 {auth_mode}",
        "open_admin": "[INFO] 관리자 URL을 열어 Setup Wizard를 완료하세요.",
        "parse_warn": "[WARN] setup-status.json을 해석할 수 없습니다",
    },
    "es": {
        "done": "[INFO] Estado de configuración: completado",
        "needs": "[INFO] Estado de configuración: se requiere configuración, paso actual {step}, modo de autenticación {auth_mode}",
        "open_admin": "[INFO] Abre la URL de administración para completar el asistente de configuración.",
        "parse_warn": "[WARN] No se puede analizar setup-status.json",
    },
    "de": {
        "done": "[INFO] Setup-Status: abgeschlossen",
        "needs": "[INFO] Setup-Status: Einrichtung erforderlich, aktueller Schritt {step}, Auth-Modus {auth_mode}",
        "open_admin": "[INFO] Öffne die Admin-URL, um den Setup Wizard abzuschließen.",
        "parse_warn": "[WARN] setup-status.json konnte nicht geparst werden",
    },
    "fr": {
        "done": "[INFO] État de configuration : terminé",
        "needs": "[INFO] État de configuration : configuration requise, étape actuelle {step}, mode d’authentification {auth_mode}",
        "open_admin": "[INFO] Ouvrez l’URL d’administration pour terminer l’assistant de configuration.",
        "parse_warn": "[WARN] Impossible d’analyser setup-status.json",
    },
    "zh-CN": {
        "done": "[INFO] Setup 状态: 已完成",
        "needs": "[INFO] Setup 状态: 需要初始化，当前步骤 {step}，认证模式 {auth_mode}",
        "open_admin": "[INFO] 请打开后台地址完成 Setup Wizard。",
        "parse_warn": "[WARN] 无法解析 setup-status.json",
    },
    "zh-TW": {
        "done": "[INFO] Setup 狀態：已完成",
        "needs": "[INFO] Setup 狀態：需要初始化，目前步驟 {step}，認證模式 {auth_mode}",
        "open_admin": "[INFO] 請打開後台位址完成 Setup Wizard。",
        "parse_warn": "[WARN] 無法解析 setup-status.json",
    },
    "pt": {
        "done": "[INFO] Status da configuração: concluído",
        "needs": "[INFO] Status da configuração: configuração necessária, etapa atual {step}, modo de autenticação {auth_mode}",
        "open_admin": "[INFO] Abra a URL de administração para concluir o assistente de configuração.",
        "parse_warn": "[WARN] Não foi possível analisar setup-status.json",
    },
}
msg = messages.get(lang, messages["en"])
try:
    data = json.load(open(path))
    payload = data.get("data", {})
    if payload.get("needsSetup") is False:
        print(msg["done"])
    else:
        step = payload.get("step", "unknown")
        auth_mode = payload.get("authMode", "passkey")
        print(msg["needs"].format(step=step, auth_mode=auth_mode))
        print(msg["open_admin"])
except Exception:
    print(msg["parse_warn"])
PY
}

prepare_activation_rollback() {
	if [[ "${WRITE_ONLY}" == "1" || "${ACTIVATE_STACK}" != "1" ]]; then
		return 0
	fi
	ACTIVATION_ROLLBACK_DIR="$(create_activation_rollback)"
	ACTIVATION_ROLLBACK_ACTIVE="1"
}

cleanup_activation_rollback() {
	if [[ "${ACTIVATION_ROLLBACK_ACTIVE:-0}" != "1" ]]; then
		return 0
	fi
	clear_activation_rollback "${ACTIVATION_ROLLBACK_DIR:-}"
	ACTIVATION_ROLLBACK_ACTIVE="0"
	ACTIVATION_ROLLBACK_DIR=""
}

activation_rollback_on_exit() {
	local exit_code="$1"
	if [[ "${exit_code}" -eq 0 || "${ACTIVATION_ROLLBACK_ACTIVE:-0}" != "1" || -z "${ACTIVATION_ROLLBACK_DIR:-}" ]]; then
		return 0
	fi
	ACTIVATION_ROLLBACK_ACTIVE="0"

	warn "安装失败，正在恢复安装前的站点与运行时配置。"
	restore_activation_rollback "${ACTIVATION_ROLLBACK_DIR}" \
		|| warn "回滚恢复部分失败，请手动检查。"
	if [[ "${WRITE_ONLY}" != "1" ]]; then
		systemctl daemon-reload >/dev/null 2>&1 || true
		systemctl start "${APP_SYSTEMD_SERVICE}" >/dev/null 2>&1 || true
	fi
	cleanup_activation_rollback || true
	return 0
}

main() {
	detect_install_lang
	parse_args "$@"
	require_root
	init_defaults
	apply_env_overrides
	detect_os_family
	collect_configuration
	derive_paths
	trap 'activation_rollback_on_exit "$?"' EXIT
	trap 'activation_rollback_on_exit 130; exit 130' INT
	trap 'activation_rollback_on_exit 143; exit 143' TERM
	load_existing_install_state
	validate_config

	if [[ "${WRITE_ONLY}" != "1" ]]; then
		install_runtime_stack
	else
		warn "$(ti write_only_skip)"
	fi

	if [[ "${WRITE_ONLY}" != "1" ]]; then
		log "$(ti detect_public_ip)"
		detect_public_ips
	else
		PUBLIC_IPV4="${PUBLIC_IPV4:-}"
		PUBLIC_IPV6="${PUBLIC_IPV6:-}"
	fi
	refresh_app_public_url

	if [[ "${WRITE_ONLY}" != "1" && -n "${DOMAIN}" ]]; then
		validate_domain_requirements
	fi

	if [[ "${STORAGE_DRIVER}" == "s3" && "${WRITE_ONLY}" != "1" ]]; then
		install_boto3_runtime
		test_s3_storage
	fi

	if [[ "${BACKUP_ENABLED}" == "1" && "${BACKUP_TARGET_TYPE}" == "s3" && "${WRITE_ONLY}" != "1" ]]; then
		install_boto3_runtime
	fi

	prepare_layout
	prepare_activation_rollback
	clone_template_repo
	patch_template_package_json
	render_astro_config
	render_app_scripts
	render_health_endpoint
	render_app_env
	render_install_yaml
	render_caddy_file
	render_systemd_service
	render_first_run_note
	install_emdashctl_script
	if [[ "${WRITE_ONLY}" != "1" ]]; then
		install_backup_schedule
	fi
	if [[ "${USE_CADDY}" == "1" && "${WRITE_ONLY}" != "1" ]]; then
		install_caddy_package
	fi

	if [[ "${WRITE_ONLY}" == "1" ]]; then
			print_summary "$(ti summary_generated_write_only)"
			exit 0
		fi

	if [[ "${ACTIVATE_STACK}" == "1" ]]; then
		ensure_runtime_present
		ensure_build_memory_headroom
		open_required_firewall_ports
		start_stack
		if [[ "${USE_CADDY}" == "1" ]]; then
			activate_caddy_service
		fi
		wait_for_stack_ready || warn "$(ti activate_health_warn)"
		cleanup_activation_rollback
		print_setup_guidance
		print_summary "$(ti summary_generated_started)"
		exit 0
	fi

	print_summary "$(ti summary_generated_only)"
}

main "$@"
