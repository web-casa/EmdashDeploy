#!/usr/bin/env bash

init_defaults() {
	NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
	WRITE_ONLY="${WRITE_ONLY:-0}"
	ACTIVATE_STACK="${ACTIVATE_STACK:-${ACTIVATE:-0}}"

	TEMPLATES_REPO="${TEMPLATES_REPO:-https://github.com/emdash-cms/templates.git}"
	TEMPLATES_REF="${TEMPLATES_REF:-main}"

	PROJECT_NAME="emdash"
	TEMPLATE="starter"
	ROOT_DIR="/data/emdash"
	TIMEZONE="$(default_timezone_for_lang)"
	DOMAIN=""
	ADMIN_EMAIL=""
	USE_CADDY="1"
	ENABLE_HTTPS="1"

	DB_DRIVER="sqlite"
	PG_VERSION="18"
	PG_DB_NAME="emdash"
	PG_DB_USER="emdash"
	PG_DB_PASSWORD=""

	SESSION_DRIVER="file"
	REDIS_PASSWORD=""
	REDIS_DATABASE="0"

	STORAGE_DRIVER="local"
	S3_PROVIDER="custom"
	S3_ENDPOINT=""
	S3_REGION="auto"
	S3_BUCKET=""
	S3_ACCESS_KEY_ID=""
	S3_SECRET_ACCESS_KEY=""
	S3_PUBLIC_URL=""

	BACKUP_ENABLED="1"
	BACKUP_SCHEDULE="0 3 * * *"
	BACKUP_KEEP_LOCAL="7"
	BACKUP_TARGET_TYPE="local"
	BACKUP_S3_ENDPOINT=""
	BACKUP_S3_REGION="auto"
	BACKUP_S3_BUCKET=""
	BACKUP_S3_ACCESS_KEY_ID=""
	BACKUP_S3_SECRET_ACCESS_KEY=""
	BACKUP_S3_PREFIX="backups"

	OPTIMIZATION_ENABLED="0"

	LOG_APP_MAX_SIZE="10m"
	LOG_APP_MAX_FILE="5"
	LOG_PG_RETAIN_DAYS="7"
	LOG_REDIS_RETAIN_DAYS="7"
	LOG_CADDY_ROTATE_SIZE_MB="100"
	LOG_CADDY_ROTATE_KEEP="10"
	LOG_CADDY_ROTATE_KEEP_DAYS="14"
}

apply_env_overrides() {
	[[ -n "${EMDASH_INSTALL_TEMPLATE:-}" ]] && TEMPLATE="${EMDASH_INSTALL_TEMPLATE}"
	[[ -n "${EMDASH_INSTALL_ROOT_DIR:-}" ]] && ROOT_DIR="${EMDASH_INSTALL_ROOT_DIR}"
	[[ -n "${EMDASH_INSTALL_DOMAIN:-}" ]] && DOMAIN="${EMDASH_INSTALL_DOMAIN}"
	[[ -n "${EMDASH_INSTALL_ADMIN_EMAIL:-}" ]] && ADMIN_EMAIL="${EMDASH_INSTALL_ADMIN_EMAIL}"
	[[ -n "${EMDASH_INSTALL_DB_DRIVER:-}" ]] && DB_DRIVER="${EMDASH_INSTALL_DB_DRIVER}"
	[[ -n "${EMDASH_INSTALL_SESSION_DRIVER:-}" ]] && SESSION_DRIVER="${EMDASH_INSTALL_SESSION_DRIVER}"
	[[ -n "${EMDASH_INSTALL_STORAGE_DRIVER:-}" ]] && STORAGE_DRIVER="${EMDASH_INSTALL_STORAGE_DRIVER}"
	[[ -n "${EMDASH_INSTALL_USE_CADDY:-}" ]] && USE_CADDY="$(normalize_bool "${EMDASH_INSTALL_USE_CADDY}")"
	[[ -n "${EMDASH_INSTALL_ENABLE_HTTPS:-}" ]] && ENABLE_HTTPS="$(normalize_bool "${EMDASH_INSTALL_ENABLE_HTTPS}")"
	[[ -n "${EMDASH_INSTALL_PG_PASSWORD:-}" ]] && PG_DB_PASSWORD="${EMDASH_INSTALL_PG_PASSWORD}"
	[[ -n "${EMDASH_INSTALL_REDIS_PASSWORD:-}" ]] && REDIS_PASSWORD="${EMDASH_INSTALL_REDIS_PASSWORD}"
	[[ -n "${EMDASH_INSTALL_S3_PROVIDER:-}" ]] && S3_PROVIDER="${EMDASH_INSTALL_S3_PROVIDER}"
	[[ -n "${EMDASH_INSTALL_S3_ENDPOINT:-}" ]] && S3_ENDPOINT="${EMDASH_INSTALL_S3_ENDPOINT}"
	[[ -n "${EMDASH_INSTALL_S3_REGION:-}" ]] && S3_REGION="${EMDASH_INSTALL_S3_REGION}"
	[[ -n "${EMDASH_INSTALL_S3_BUCKET:-}" ]] && S3_BUCKET="${EMDASH_INSTALL_S3_BUCKET}"
	[[ -n "${EMDASH_INSTALL_S3_ACCESS_KEY_ID:-}" ]] && S3_ACCESS_KEY_ID="${EMDASH_INSTALL_S3_ACCESS_KEY_ID}"
	[[ -n "${EMDASH_INSTALL_S3_SECRET_ACCESS_KEY:-}" ]] && S3_SECRET_ACCESS_KEY="${EMDASH_INSTALL_S3_SECRET_ACCESS_KEY}"
	[[ -n "${EMDASH_INSTALL_S3_PUBLIC_URL:-}" ]] && S3_PUBLIC_URL="${EMDASH_INSTALL_S3_PUBLIC_URL}"
	[[ -n "${EMDASH_INSTALL_BACKUP_TARGET:-}" ]] && BACKUP_TARGET_TYPE="${EMDASH_INSTALL_BACKUP_TARGET}"
	[[ -n "${EMDASH_INSTALL_BACKUP_S3_ENDPOINT:-}" ]] && BACKUP_S3_ENDPOINT="${EMDASH_INSTALL_BACKUP_S3_ENDPOINT}"
	[[ -n "${EMDASH_INSTALL_BACKUP_S3_REGION:-}" ]] && BACKUP_S3_REGION="${EMDASH_INSTALL_BACKUP_S3_REGION}"
	[[ -n "${EMDASH_INSTALL_BACKUP_S3_BUCKET:-}" ]] && BACKUP_S3_BUCKET="${EMDASH_INSTALL_BACKUP_S3_BUCKET}"
	[[ -n "${EMDASH_INSTALL_BACKUP_S3_ACCESS_KEY_ID:-}" ]] && BACKUP_S3_ACCESS_KEY_ID="${EMDASH_INSTALL_BACKUP_S3_ACCESS_KEY_ID}"
	[[ -n "${EMDASH_INSTALL_BACKUP_S3_SECRET_ACCESS_KEY:-}" ]] && BACKUP_S3_SECRET_ACCESS_KEY="${EMDASH_INSTALL_BACKUP_S3_SECRET_ACCESS_KEY}"
	[[ -n "${EMDASH_INSTALL_BACKUP_S3_PREFIX:-}" ]] && BACKUP_S3_PREFIX="${EMDASH_INSTALL_BACKUP_S3_PREFIX}"
	return 0
}

derive_paths() {
	CONFIG_DIR="${CONFIG_DIR:-/etc/emdash}"
	INSTALL_YAML="${CONFIG_DIR}/install.yml"
	APP_ENV_FILE="${CONFIG_DIR}/emdash.env"
	ROOT_DIR="${ROOT_DIR%/}"
	APP_DIR="${ROOT_DIR}/app"
	SITE_DIR="${APP_DIR}/site"
	DATA_DIR="${ROOT_DIR}/data"
	LOG_DIR="${ROOT_DIR}/logs"
	BACKUP_DIR="${ROOT_DIR}/backups"
	TMP_DIR="${ROOT_DIR}/tmp"
	CADDY_DIR="${CONFIG_DIR}/caddy"
	CADDYFILE_PATH="${CADDY_DIR}/Caddyfile"
	TEMPLATE_SOURCE_DIR="${APP_DIR}/template-source"
	SQLITE_DIR="${DATA_DIR}/sqlite"
	SQLITE_PATH="${SQLITE_DIR}/data.db"
	UPLOADS_DIR="${DATA_DIR}/uploads"
	SESSIONS_DIR="${DATA_DIR}/sessions"
	POSTGRES_DIR="${DATA_DIR}/postgres"
	REDIS_DIR="${DATA_DIR}/redis"
	SCRIPTS_DIR="${ROOT_DIR}/scripts"
	APP_PORT="3000"
	APP_BIND_HOST="127.0.0.1"
	APP_SYSTEMD_SERVICE="emdash-app"
	if [[ "${WRITE_ONLY}" == "1" ]]; then
		APP_SYSTEMD_UNIT="${CONFIG_DIR}/${APP_SYSTEMD_SERVICE}.service"
	else
		APP_SYSTEMD_UNIT="/etc/systemd/system/${APP_SYSTEMD_SERVICE}.service"
	fi
	APP_RUN_USER="emdash"
	APP_RUN_GROUP="emdash"
	APP_NODE_MAX_OLD_SPACE_SIZE="1536"
	APP_BUILD_SCRIPT="${SITE_DIR}/emdash-build.sh"
	APP_START_SCRIPT="${SITE_DIR}/emdash-start.sh"
	POSTGRES_HOST="127.0.0.1"
	POSTGRES_PORT="5432"
	REDIS_HOST="127.0.0.1"
	REDIS_PORT="6379"

	EMDASH_AUTH_SECRET="${EMDASH_AUTH_SECRET:-$(random_hex 32)}"
	EMDASH_PREVIEW_SECRET="${EMDASH_PREVIEW_SECRET:-$(random_hex 32)}"
	refresh_app_public_url
}

pick_public_endpoint_host() {
	if [[ -n "${DOMAIN:-}" ]]; then
		printf '%s\n' "${DOMAIN}"
		return
	fi
	if [[ -n "${PUBLIC_IPV4:-}" ]]; then
		printf '%s\n' "${PUBLIC_IPV4}"
		return
	fi
	if [[ -n "${PUBLIC_IPV6:-}" ]]; then
		printf '[%s]\n' "${PUBLIC_IPV6}"
		return
	fi
	printf '127.0.0.1\n'
}

refresh_app_public_url() {
	if [[ "${USE_CADDY}" != "1" ]]; then
		APP_BIND_HOST="0.0.0.0"
		APP_PUBLIC_URL="http://$(pick_public_endpoint_host):${APP_PORT}"
		return
	fi

	APP_BIND_HOST="127.0.0.1"
	APP_PUBLIC_URL="http://${DOMAIN:-127.0.0.1}"
	if [[ "${ENABLE_HTTPS}" == "1" && -n "${DOMAIN}" ]]; then
		APP_PUBLIC_URL="https://${DOMAIN}"
	fi
}

validate_config() {
	case " ${TEMPLATE} " in
	" starter " | " blog " | " marketing " | " portfolio " | " blank ") ;;
	*) fail "不支持的模板: ${TEMPLATE}" ;;
	esac

	case "${DB_DRIVER}" in
	sqlite | postgres) ;;
	*) fail "不支持的数据库: ${DB_DRIVER}" ;;
	esac

	case "${SESSION_DRIVER}" in
	file | redis) ;;
	*) fail "不支持的 session 驱动: ${SESSION_DRIVER}" ;;
	esac

	case "${STORAGE_DRIVER}" in
	local | s3) ;;
	*) fail "不支持的存储驱动: ${STORAGE_DRIVER}" ;;
	esac

	case "${BACKUP_TARGET_TYPE}" in
	local | s3) ;;
	*) fail "不支持的备份目标: ${BACKUP_TARGET_TYPE}" ;;
	esac

	USE_CADDY="$(normalize_bool "${USE_CADDY}")"
	ENABLE_HTTPS="$(normalize_bool "${ENABLE_HTTPS}")"
	BACKUP_ENABLED="$(normalize_bool "${BACKUP_ENABLED}")"
	OPTIMIZATION_ENABLED="$(normalize_bool "${OPTIMIZATION_ENABLED}")"

	if [[ "${DB_DRIVER}" == "postgres" && -z "${PG_DB_PASSWORD}" ]]; then
		PG_DB_PASSWORD="$(random_hex 16)"
		warn "未提供 PostgreSQL 密码，已自动生成。"
	fi
	if [[ "${SESSION_DRIVER}" == "redis" && -z "${REDIS_PASSWORD}" ]]; then
		REDIS_PASSWORD="$(random_hex 16)"
		warn "未提供 Redis 密码，已自动生成。"
	fi

	if [[ "${DB_DRIVER}" == "postgres" ]]; then
		[[ "${PG_DB_USER}" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]] || fail "PostgreSQL 用户名仅支持字母、数字和下划线，且必须以字母或下划线开头。"
		[[ "${PG_DB_NAME}" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]] || fail "PostgreSQL 数据库名仅支持字母、数字和下划线，且必须以字母或下划线开头。"
	fi

	if [[ "${USE_CADDY}" == "1" && -z "${DOMAIN}" ]]; then
		fail "启用 Caddy 时必须提供 DOMAIN。"
	fi
	if [[ "${USE_CADDY}" == "1" && "${ENABLE_HTTPS}" == "1" && -z "${ADMIN_EMAIL}" ]]; then
		fail "启用 HTTPS 时必须提供 ADMIN_EMAIL。"
	fi

	if [[ "${STORAGE_DRIVER}" == "s3" ]]; then
		[[ -n "${S3_ENDPOINT}" ]] || fail "S3 存储必须提供 endpoint。"
		[[ -n "${S3_BUCKET}" ]] || fail "S3 存储必须提供 bucket。"
		[[ -n "${S3_ACCESS_KEY_ID}" ]] || fail "S3 存储必须提供 access key。"
		[[ -n "${S3_SECRET_ACCESS_KEY}" ]] || fail "S3 存储必须提供 secret key。"
	fi

	if [[ "${BACKUP_ENABLED}" == "1" && "${BACKUP_TARGET_TYPE}" == "s3" ]]; then
		[[ -n "${BACKUP_S3_ENDPOINT}" ]] || fail "S3 备份必须提供 endpoint。"
		[[ -n "${BACKUP_S3_BUCKET}" ]] || fail "S3 备份必须提供 bucket。"
		[[ -n "${BACKUP_S3_ACCESS_KEY_ID}" ]] || fail "S3 备份必须提供 access key。"
		[[ -n "${BACKUP_S3_SECRET_ACCESS_KEY}" ]] || fail "S3 备份必须提供 secret key。"
	fi
	return 0
}
