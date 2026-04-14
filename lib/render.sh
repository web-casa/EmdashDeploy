#!/usr/bin/env bash

json_literal() {
	python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

url_quote() {
	python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

env_quote() {
	python3 -c 'import sys; s=sys.argv[1]; s=s.replace("\\\\","\\\\\\\\").replace("\"","\\\\\"").replace("$","\\\\$").replace("`","\\\\`").replace("\n","\\\\n"); print(f"\"{s}\"")' "$1"
}

append_env_line() {
	printf '%s=%s\n' "$1" "$(env_quote "${2-}")"
}

prepare_layout() {
	ensure_dir "${CONFIG_DIR}"
	ensure_dir "${ROOT_DIR}"
	ensure_dir "${APP_DIR}"
	ensure_dir "${TEMPLATE_SOURCE_DIR}"
	ensure_dir "${DATA_DIR}"
	ensure_dir "${LOG_DIR}"
	ensure_dir "${BACKUP_DIR}"
	ensure_dir "${TMP_DIR}"
	ensure_dir "${CADDY_DIR}"
	ensure_dir "${UPLOADS_DIR}"
	ensure_dir "${SESSIONS_DIR}"
	ensure_dir "${SQLITE_DIR}"
	ensure_dir "${POSTGRES_DIR}"
	ensure_dir "${REDIS_DIR}"
	ensure_dir "${SCRIPTS_DIR}"
}

clone_template_repo() {
	if [[ ! -d "${TEMPLATE_SOURCE_DIR}/.git" ]]; then
		rm -rf "${TEMPLATE_SOURCE_DIR}"
		log "拉取 EmDash 模板 ${TEMPLATE}"
		git clone --depth 1 --branch "${TEMPLATES_REF}" "${TEMPLATES_REPO}" "${TEMPLATE_SOURCE_DIR}"
	fi
	prepare_site_directory
}

sync_template_into_site() {
	local template_path="${TEMPLATE_SOURCE_DIR}/${TEMPLATE}"
	[[ -d "${template_path}" ]] || fail "$(printf "$(ti template_dir_missing)" "${template_path}")"
	rm -rf "${SITE_DIR}"
	ensure_dir "${SITE_DIR}"
	cp -a "${template_path}/." "${SITE_DIR}/"
}

prepare_site_directory() {
	if [[ "${FORCE_SYNC_TEMPLATE}" == "1" ]]; then
		log "已启用模板强制同步，覆盖现有站点源码"
		sync_template_into_site
		SITE_SYNC_MODE="sync"
		return
	fi

	if [[ ! -f "${SITE_DIR}/package.json" ]]; then
		sync_template_into_site
		SITE_SYNC_MODE="sync"
		return
	fi

	SITE_SYNC_MODE="preserve"

	local existing_template=""
	local existing_db_driver=""
	local existing_session_driver=""
	local existing_storage_driver=""
	existing_template="$(read_install_yaml_section_value project template || true)"
	existing_db_driver="$(read_install_yaml_section_value database driver || true)"
	existing_session_driver="$(read_install_yaml_section_value session driver || true)"
	existing_storage_driver="$(read_install_yaml_section_value storage driver || true)"

	if [[ -z "${existing_template}" && -f "${APP_ENV_FILE:-}" ]]; then
		existing_template="$(read_existing_env_value "${APP_ENV_FILE}" TEMPLATE || true)"
	fi
	if [[ -z "${existing_db_driver}" && -f "${APP_ENV_FILE:-}" ]]; then
		existing_db_driver="$(read_existing_env_value "${APP_ENV_FILE}" DB_DRIVER || true)"
	fi
	if [[ -z "${existing_session_driver}" && -f "${APP_ENV_FILE:-}" ]]; then
		existing_session_driver="$(read_existing_env_value "${APP_ENV_FILE}" SESSION_DRIVER || true)"
	fi
	if [[ -z "${existing_storage_driver}" && -f "${APP_ENV_FILE:-}" ]]; then
		existing_storage_driver="$(read_existing_env_value "${APP_ENV_FILE}" STORAGE_DRIVER || true)"
	fi

	if [[ -z "${existing_template}" && -z "${existing_db_driver}" && -z "${existing_session_driver}" && -z "${existing_storage_driver}" ]]; then
		fail "$(ti existing_site_missing_metadata)"
	fi

	if [[ -n "${existing_template}" && "${existing_template}" != "${TEMPLATE}" ]]; then
		fail "$(printf "$(ti existing_site_template_mismatch)" "${existing_template}" "${TEMPLATE}")"
	fi
	if [[ -n "${existing_db_driver}" && "${existing_db_driver}" != "${DB_DRIVER}" ]]; then
		fail "$(printf "$(ti existing_site_db_mismatch)" "${existing_db_driver}" "${DB_DRIVER}")"
	fi
	if [[ -n "${existing_session_driver}" && "${existing_session_driver}" != "${SESSION_DRIVER}" ]]; then
		fail "$(printf "$(ti existing_site_session_mismatch)" "${existing_session_driver}" "${SESSION_DRIVER}")"
	fi
	if [[ -n "${existing_storage_driver}" && "${existing_storage_driver}" != "${STORAGE_DRIVER}" ]]; then
		fail "$(printf "$(ti existing_site_storage_mismatch)" "${existing_storage_driver}" "${STORAGE_DRIVER}")"
	fi

	[[ -f "${SITE_DIR}/astro.config.mjs" ]] || fail "$(ti existing_site_missing_astro_config)"
	log "检测到现有 EmDash 站点目录，保留当前模板源码"
}

patch_template_package_json() {
	if [[ "${SITE_SYNC_MODE:-sync}" != "sync" ]]; then
		log "保留现有 package.json"
		return
	fi

	local redis_snippet='{"ioredis":"^5.7.0"}'
	local pg_snippet='{"pg":"^8.16.3"}'
	local s3_snippet='{"@aws-sdk/client-s3":"^3.879.0","@aws-sdk/s3-request-presigner":"^3.879.0"}'
	local common_runtime_snippet='{"kysely":"^0.27.6"}'
	PROJECT_NAME="${PROJECT_NAME}" SITE_DIR="${SITE_DIR}" DB_DRIVER="${DB_DRIVER}" SESSION_DRIVER="${SESSION_DRIVER}" STORAGE_DRIVER="${STORAGE_DRIVER}" REDIS_SNIPPET="${redis_snippet}" PG_SNIPPET="${pg_snippet}" S3_SNIPPET="${s3_snippet}" COMMON_RUNTIME_SNIPPET="${common_runtime_snippet}" python3 <<'PY'
import json
import os
from pathlib import Path

site_dir = Path(os.environ["SITE_DIR"])
pkg_path = site_dir / "package.json"
pkg = json.loads(pkg_path.read_text())

pkg["name"] = os.environ["PROJECT_NAME"]
pkg["packageManager"] = "pnpm@10.28.0"
pkg.setdefault("emdash", {})
if (site_dir / "seed" / "seed.json").exists():
    pkg["emdash"]["seed"] = "seed/seed.json"

deps = pkg.setdefault("dependencies", {})
deps.update(json.loads(os.environ["COMMON_RUNTIME_SNIPPET"]))
if os.environ["DB_DRIVER"] == "postgres":
    deps.update(json.loads(os.environ["PG_SNIPPET"]))
if os.environ["SESSION_DRIVER"] == "redis":
    deps.update(json.loads(os.environ["REDIS_SNIPPET"]))
if os.environ["STORAGE_DRIVER"] == "s3":
    deps.update(json.loads(os.environ["S3_SNIPPET"]))

pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")
PY
}

render_astro_config() {
	if [[ "${SITE_SYNC_MODE:-sync}" != "sync" ]]; then
		log "保留现有 astro.config.mjs，运行时通过 EMDASH_SITE_URL/SITE_URL 提供 public origin"
		return
	fi

	SITE_DIR="${SITE_DIR}" DB_DRIVER="${DB_DRIVER}" SESSION_DRIVER="${SESSION_DRIVER}" STORAGE_DRIVER="${STORAGE_DRIVER}" \
		python3 "${SCRIPT_DIR}/lib/astro-patch.py"
}

render_app_scripts() {
	cat >"${APP_BUILD_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\${PATH:-}"
export NODE_OPTIONS="--max-old-space-size=${APP_NODE_MAX_OLD_SPACE_SIZE}"
if [[ -f "${APP_ENV_FILE}" ]]; then
	set -a
	. "${APP_ENV_FILE}"
	set +a
fi
cd "${SITE_DIR}"
corepack enable || true
corepack prepare pnpm@10.28.0 --activate
pnpm install --no-frozen-lockfile
pnpm build
EOF
	chmod 0755 "${APP_BUILD_SCRIPT}"

	cat >"${APP_START_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\${PATH:-}"
export NODE_OPTIONS="--max-old-space-size=${APP_NODE_MAX_OLD_SPACE_SIZE}"
cd "${SITE_DIR}"
corepack enable || true
corepack prepare pnpm@10.28.0 --activate
if [[ "\${DB_DRIVER:-sqlite}" == "sqlite" ]]; then
	mkdir -p "${SQLITE_DIR}"
	if [[ ! -f "${SQLITE_PATH}" ]]; then
		pnpm exec emdash init --database "${SQLITE_PATH}"
	fi
fi
exec pnpm start
EOF
	chmod 0755 "${APP_START_SCRIPT}"
	if id "${APP_RUN_USER}" >/dev/null 2>&1; then
		chown "${APP_RUN_USER}:${APP_RUN_GROUP}" "${APP_BUILD_SCRIPT}" "${APP_START_SCRIPT}"
	fi
}

render_health_endpoint() {
	if [[ "${SITE_SYNC_MODE:-sync}" != "sync" ]]; then
		log "保留现有 healthz 路由实现"
		return
	fi

	ensure_dir "${SITE_DIR}/src/pages"
	cat >"${SITE_DIR}/src/pages/healthz.ts" <<'EOF'
export const GET = () => {
	return new Response("OK", { status: 200 });
};
EOF
}

render_app_env() {
	local pg_user_encoded=""
	local pg_password_encoded=""
	local pg_db_name_encoded=""
	local redis_password_encoded=""
	local database_url=""
	local redis_url=""

	pg_user_encoded="$(url_quote "${PG_DB_USER}")"
	pg_password_encoded="$(url_quote "${PG_DB_PASSWORD}")"
	pg_db_name_encoded="$(url_quote "${PG_DB_NAME}")"
	redis_password_encoded="$(url_quote "${REDIS_PASSWORD}")"
	if [[ "${DB_DRIVER}" == "postgres" ]]; then
		database_url="$(printf 'postgres://%s:%s@%s:%s/%s' "${pg_user_encoded}" "${pg_password_encoded}" "${POSTGRES_HOST}" "${POSTGRES_PORT}" "${pg_db_name_encoded}")"
	fi
	if [[ "${SESSION_DRIVER}" == "redis" ]]; then
		redis_url="$(printf 'redis://:%s@%s:%s/%s' "${redis_password_encoded}" "${REDIS_HOST}" "${REDIS_PORT}" "${REDIS_DATABASE}")"
	fi

	{
		append_env_line HOST "${APP_BIND_HOST}"
		append_env_line PORT "${APP_PORT}"
		append_env_line PROJECT_NAME "${PROJECT_NAME}"
		append_env_line ROOT_DIR "${ROOT_DIR}"
		append_env_line SITE_DIR "${SITE_DIR}"
		append_env_line TIMEZONE "${TIMEZONE}"
		append_env_line APP_PORT "${APP_PORT}"
		append_env_line APP_BIND_HOST "${APP_BIND_HOST}"
		append_env_line APP_PUBLIC_URL "${APP_PUBLIC_URL}"
		append_env_line EMDASH_SITE_URL "${APP_PUBLIC_URL}"
		append_env_line SITE_URL "${APP_PUBLIC_URL}"
		append_env_line APP_SYSTEMD_SERVICE "${APP_SYSTEMD_SERVICE}"
		append_env_line APP_SYSTEMD_UNIT "${APP_SYSTEMD_UNIT}"
		append_env_line APP_RUN_USER "${APP_RUN_USER}"
		append_env_line APP_RUN_GROUP "${APP_RUN_GROUP}"
		append_env_line APP_BUILD_SCRIPT "${APP_BUILD_SCRIPT}"
		append_env_line APP_START_SCRIPT "${APP_START_SCRIPT}"
		append_env_line TEMPLATES_REPO "${TEMPLATES_REPO}"
		append_env_line TEMPLATES_REF "${TEMPLATES_REF}"
		append_env_line TEMPLATE "${TEMPLATE}"
		append_env_line TEMPLATE_SOURCE_DIR "${TEMPLATE_SOURCE_DIR}"
		append_env_line DB_DRIVER "${DB_DRIVER}"
		append_env_line SESSION_DRIVER "${SESSION_DRIVER}"
		append_env_line STORAGE_DRIVER "${STORAGE_DRIVER}"
		append_env_line USE_CADDY "${USE_CADDY}"
		append_env_line ENABLE_HTTPS "${ENABLE_HTTPS}"
		append_env_line DOMAIN "${DOMAIN}"
		append_env_line ADMIN_EMAIL "${ADMIN_EMAIL}"
		append_env_line EMDASH_AUTH_SECRET "${EMDASH_AUTH_SECRET}"
		append_env_line EMDASH_PREVIEW_SECRET "${EMDASH_PREVIEW_SECRET}"
		append_env_line SQLITE_PATH "${SQLITE_PATH}"
		append_env_line UPLOADS_DIR "${UPLOADS_DIR}"
		append_env_line SESSIONS_DIR "${SESSIONS_DIR}"
		append_env_line POSTGRES_DIR "${POSTGRES_DIR}"
		append_env_line POSTGRES_SERVICE "${POSTGRES_SERVICE}"
		append_env_line POSTGRES_HOST "${POSTGRES_HOST}"
		append_env_line POSTGRES_PORT "${POSTGRES_PORT}"
		append_env_line DATABASE_URL "${database_url}"
		append_env_line PG_VERSION "${PG_VERSION}"
		append_env_line PG_DB_NAME "${PG_DB_NAME}"
		append_env_line PG_DB_USER "${PG_DB_USER}"
		append_env_line PG_DB_PASSWORD "${PG_DB_PASSWORD}"
		append_env_line REDIS_SERVICE "${REDIS_SERVICE}"
		append_env_line REDIS_HOST "${REDIS_HOST}"
		append_env_line REDIS_PORT "${REDIS_PORT}"
		append_env_line REDIS_PASSWORD "${REDIS_PASSWORD}"
		append_env_line REDIS_DB "${REDIS_DATABASE}"
		append_env_line REDIS_URL "${redis_url}"
		append_env_line S3_PROVIDER "${S3_PROVIDER}"
		append_env_line S3_ENDPOINT "${S3_ENDPOINT}"
		append_env_line S3_REGION "${S3_REGION}"
		append_env_line S3_BUCKET "${S3_BUCKET}"
		append_env_line S3_ACCESS_KEY_ID "${S3_ACCESS_KEY_ID}"
		append_env_line S3_SECRET_ACCESS_KEY "${S3_SECRET_ACCESS_KEY}"
		append_env_line S3_PUBLIC_URL "${S3_PUBLIC_URL}"
			append_env_line BACKUP_ENABLED "${BACKUP_ENABLED}"
			append_env_line BACKUP_SCHEDULE "${BACKUP_SCHEDULE}"
			append_env_line BACKUP_KEEP_LOCAL "${BACKUP_KEEP_LOCAL}"
			append_env_line BACKUP_DIR "${BACKUP_DIR}"
			append_env_line BACKUP_TARGET_TYPE "${BACKUP_TARGET_TYPE}"
		append_env_line BACKUP_S3_ENDPOINT "${BACKUP_S3_ENDPOINT}"
		append_env_line BACKUP_S3_REGION "${BACKUP_S3_REGION}"
		append_env_line BACKUP_S3_BUCKET "${BACKUP_S3_BUCKET}"
		append_env_line BACKUP_S3_ACCESS_KEY_ID "${BACKUP_S3_ACCESS_KEY_ID}"
		append_env_line BACKUP_S3_SECRET_ACCESS_KEY "${BACKUP_S3_SECRET_ACCESS_KEY}"
		append_env_line BACKUP_S3_PREFIX "${BACKUP_S3_PREFIX}"
	} >"${APP_ENV_FILE}"
	chmod 0640 "${APP_ENV_FILE}"
	if getent group "${APP_RUN_GROUP}" >/dev/null 2>&1; then
		chown root:"${APP_RUN_GROUP}" "${APP_ENV_FILE}"
	fi
}

render_install_yaml() {
	cat >"${INSTALL_YAML}" <<EOF
version: 1
project:
  name: ${PROJECT_NAME}
  template: ${TEMPLATE}
  root_dir: ${ROOT_DIR}
  timezone: ${TIMEZONE}
  domain: ${DOMAIN}
  admin_email: ${ADMIN_EMAIL}
platform:
  os_label: ${OS_LABEL}
  service_mode: native
network:
  public_ipv4: ${PUBLIC_IPV4}
  public_ipv6: ${PUBLIC_IPV6}
  bind_host: ${APP_BIND_HOST}
  app_port: ${APP_PORT}
web:
  use_caddy: ${USE_CADDY}
  enable_https: ${ENABLE_HTTPS}
services:
  app: ${APP_SYSTEMD_SERVICE}
  postgres: ${POSTGRES_SERVICE}
  redis: ${REDIS_SERVICE}
database:
  driver: ${DB_DRIVER}
  postgres:
    version: ${PG_VERSION}
    db_name: ${PG_DB_NAME}
    db_user: ${PG_DB_USER}
session:
  driver: ${SESSION_DRIVER}
storage:
  driver: ${STORAGE_DRIVER}
  s3:
    provider: ${S3_PROVIDER}
    endpoint: ${S3_ENDPOINT}
    region: ${S3_REGION}
    bucket: ${S3_BUCKET}
backup:
  enabled: ${BACKUP_ENABLED}
  schedule: "${BACKUP_SCHEDULE}"
  keep_local: ${BACKUP_KEEP_LOCAL}
  target:
    type: ${BACKUP_TARGET_TYPE}
    s3_endpoint: ${BACKUP_S3_ENDPOINT}
    s3_region: ${BACKUP_S3_REGION}
    s3_bucket: ${BACKUP_S3_BUCKET}
    s3_prefix: ${BACKUP_S3_PREFIX}
optimization:
  enabled: ${OPTIMIZATION_ENABLED}
logging:
  app:
    max_size: ${LOG_APP_MAX_SIZE}
    max_file: ${LOG_APP_MAX_FILE}
  postgres:
    retain_days: ${LOG_PG_RETAIN_DAYS}
  redis:
    retain_days: ${LOG_REDIS_RETAIN_DAYS}
  caddy:
    rotate_size_mb: ${LOG_CADDY_ROTATE_SIZE_MB}
    rotate_keep: ${LOG_CADDY_ROTATE_KEEP}
    rotate_keep_days: ${LOG_CADDY_ROTATE_KEEP_DAYS}
EOF
}

render_caddy_file() {
	if [[ "${USE_CADDY}" != "1" ]]; then
		return
	fi

	local site_header=""
	local global_block=""
	if [[ "${ENABLE_HTTPS}" == "1" ]]; then
		site_header="${DOMAIN}"
	else
		site_header="http://${DOMAIN}"
	fi
	if [[ -n "${ADMIN_EMAIL}" ]]; then
		global_block=$(cat <<EOF
{
	email ${ADMIN_EMAIL}
}

EOF
)
	fi

	cat >"${CADDYFILE_PATH}" <<EOF
${global_block}
${site_header} {
	encode zstd gzip

	log {
		output stdout
		format json
	}

	reverse_proxy 127.0.0.1:${APP_PORT}
}
EOF
	chmod 0644 "${CADDYFILE_PATH}"
}

render_systemd_service() {
	cat >"${APP_SYSTEMD_UNIT}" <<EOF
[Unit]
Description=EmDash App
After=network-online.target
Wants=network-online.target
$( [[ "${DB_DRIVER}" == "postgres" ]] && printf 'After=%s.service\n' "${POSTGRES_SERVICE}" )
$( [[ "${SESSION_DRIVER}" == "redis" ]] && printf 'After=%s.service\n' "${REDIS_SERVICE}" )

[Service]
Type=simple
User=${APP_RUN_USER}
Group=${APP_RUN_GROUP}
WorkingDirectory=${SITE_DIR}
EnvironmentFile=${APP_ENV_FILE}
Environment=HOME=${ROOT_DIR}
Environment=NODE_ENV=production
ExecStart=/usr/bin/bash ${APP_START_SCRIPT}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

install_emdashctl_script() {
	migrate_legacy_emdashctl_references
	install -m 0755 "${SCRIPT_DIR}/emdashctl" /usr/local/bin/emdashctl
	install -d -m 0755 "${ROOT_DIR}/lib"
	install -m 0644 "${SCRIPT_DIR}/lib/astro-patch.py" "${ROOT_DIR}/lib/astro-patch.py"
	remove_legacy_emdashctl_aliases
}

migrate_legacy_emdashctl_references() {
	local tmp_report
	tmp_report="$(mktemp)"
	TMP_REPORT="${tmp_report}" python3 <<'PY'
import os
import re
from pathlib import Path

report_path = Path(os.environ["TMP_REPORT"])

langs = ("en", "ja", "ko", "es", "de", "fr", "zh-CN", "zh-TW", "pt")
lang_alt = "|".join(re.escape(lang) for lang in langs)
absolute_pattern = re.compile(rf"/usr/local/bin/emdashctl\.({lang_alt})\.sh(?![\w.-])")
bare_pattern = re.compile(rf"(?<![\w./-])emdashctl\.({lang_alt})\.sh(?![\w.-])")
systemd_keys = {"ExecStart","ExecStartPre","ExecStartPost","ExecReload","ExecStop","ExecStopPost"}

def replace_absolute(text):
    return absolute_pattern.sub(lambda m: f"/usr/local/bin/emdashctl --lang={m.group(1)}", text)

def replace_bare(text):
    return bare_pattern.sub(lambda m: f"emdashctl --lang={m.group(1)}", text)

def migrate_cron_like(path):
    try:
        lines = path.read_text().splitlines(keepends=True)
    except (OSError, UnicodeDecodeError):
        return False
    changed = False
    out = []
    for line in lines:
        stripped = line.lstrip()
        if not stripped or stripped.startswith("#"):
            out.append(line)
            continue
        updated = replace_bare(replace_absolute(line))
        changed |= updated != line
        out.append(updated)
    if changed:
        path.write_text("".join(out))
    return changed

def migrate_systemd_unit(path):
    try:
        lines = path.read_text().splitlines(keepends=True)
    except (OSError, UnicodeDecodeError):
        return False
    changed = False
    out = []
    for line in lines:
        stripped = line.lstrip()
        if stripped.startswith("#") or "=" not in stripped:
            out.append(line)
            continue
        key, value = stripped.split("=", 1)
        if key not in systemd_keys:
            out.append(line)
            continue
        indent = line[: len(line) - len(line.lstrip())]
        updated = replace_bare(replace_absolute(value))
        new_line = f"{indent}{key}={updated}"
        changed |= new_line != line
        out.append(new_line)
    if changed:
        path.write_text("".join(out))
    return changed

targets = []
for path in [Path("/etc/crontab"), Path("/etc/anacrontab")]:
    if path.is_file():
        targets.append(("cron", path))
for candidate in Path("/etc/cron.d").glob("*"):
    if candidate.is_file():
        targets.append(("cron", candidate))
for candidate in Path("/etc/systemd/system").glob("*.service"):
    if candidate.is_file():
        targets.append(("systemd", candidate))
for candidate in Path("/etc/systemd/system").glob("*.timer"):
    if candidate.is_file():
        targets.append(("systemd", candidate))

changed = []
for kind, path in targets:
    ok = migrate_cron_like(path) if kind == "cron" else migrate_systemd_unit(path)
    if ok:
        changed.append(str(path))

report_path.write_text("\n".join(changed))
PY
	if [[ -s "${tmp_report}" ]]; then
		while IFS= read -r migrated_file; do
			[[ -n "${migrated_file}" ]] || continue
			log "迁移旧 emdashctl 多语言别名引用: ${migrated_file}"
		done <"${tmp_report}"
		systemctl daemon-reload >/dev/null 2>&1 || true
	fi
	rm -f "${tmp_report}"
}

remove_legacy_emdashctl_aliases() {
	local alias_path
	for alias_path in \
		/usr/local/bin/emdashctl.en.sh \
		/usr/local/bin/emdashctl.ja.sh \
		/usr/local/bin/emdashctl.ko.sh \
		/usr/local/bin/emdashctl.es.sh \
		/usr/local/bin/emdashctl.de.sh \
		/usr/local/bin/emdashctl.fr.sh \
		/usr/local/bin/emdashctl.zh-CN.sh \
		/usr/local/bin/emdashctl.zh-TW.sh \
		/usr/local/bin/emdashctl.pt.sh; do
		rm -f "${alias_path}"
	done
}

render_first_run_note() {
	cat >"${ROOT_DIR}/FIRST_RUN.txt" <<EOF
$(ti first_run_installed)

$(ti first_run_site_address)
  ${APP_PUBLIC_URL}

$(ti first_run_admin_address)
  ${APP_PUBLIC_URL}/_emdash/admin

$(ti first_run_health_check)
  ${APP_PUBLIC_URL}/healthz

$(ti first_run_first_visit)
  $(ti first_run_step1)
  $(ti first_run_step2)
  $(ti first_run_step3)

$(ti first_run_ops_commands)
  emdashctl status
  emdashctl doctor
  emdashctl logs app -f
EOF
}

build_site() {
	log "构建 EmDash 站点"
	install -d -o "${APP_RUN_USER}" -g "${APP_RUN_GROUP}" \
		"${APP_DIR}" "${SITE_DIR}" "${DATA_DIR}" "${TMP_DIR}" \
		"${UPLOADS_DIR}" "${SESSIONS_DIR}" "${SQLITE_DIR}"
	chown -R "${APP_RUN_USER}:${APP_RUN_GROUP}" \
		"${SITE_DIR}" "${UPLOADS_DIR}" "${SESSIONS_DIR}" "${SQLITE_DIR}" "${TMP_DIR}"
	runuser -u "${APP_RUN_USER}" -- bash -lc "${APP_BUILD_SCRIPT}"
}

create_site_rollback() {
	local rollback_dir
	install -d -m 0755 "${TMP_DIR}"
	rollback_dir="$(mktemp -d "${TMP_DIR}/site-rollback.XXXXXX")"
	if [[ -d "${SITE_DIR}" ]]; then
		mkdir -p "${rollback_dir}/site"
		cp -a "${SITE_DIR}/." "${rollback_dir}/site/"
	fi
	if [[ -d "${SCRIPTS_DIR}" ]]; then
		mkdir -p "${rollback_dir}/scripts"
		cp -a "${SCRIPTS_DIR}/." "${rollback_dir}/scripts/"
	fi
	printf '%s\n' "${rollback_dir}"
}

backup_managed_file() {
	local source_path="$1"
	local backup_dir="$2"
	mkdir -p "${backup_dir}"
	if [[ -f "${source_path}" ]]; then
		cp -a "${source_path}" "${backup_dir}/content"
	else
		: >"${backup_dir}/missing"
	fi
}

restore_managed_file() {
	local backup_dir="$1"
	local target_path="$2"
	if [[ -f "${backup_dir}/content" ]]; then
		mkdir -p "$(dirname "${target_path}")"
		cp -a "${backup_dir}/content" "${target_path}"
		return
	fi
	if [[ -f "${backup_dir}/missing" ]]; then
		rm -f "${target_path}"
	fi
}

backup_service_state() {
	local service_name="$1"
	local backup_dir="$2"
	mkdir -p "${backup_dir}"
	{
		if command -v systemctl >/dev/null 2>&1; then
			printf 'enabled=%s\n' "$(systemctl is-enabled "${service_name}" 2>/dev/null || printf 'unknown')"
			printf 'active=%s\n' "$(systemctl is-active "${service_name}" 2>/dev/null || printf 'unknown')"
		else
			printf 'enabled=unknown\n'
			printf 'active=unknown\n'
		fi
	} >"${backup_dir}/state"
}

restore_service_state() {
	local service_name="$1"
	local backup_dir="$2"
	local enabled_state=""
	local active_state=""
	[[ -f "${backup_dir}/state" ]] || return 0
	command -v systemctl >/dev/null 2>&1 || return 0

	enabled_state="$(awk -F= '$1=="enabled" {print $2}' "${backup_dir}/state")"
	active_state="$(awk -F= '$1=="active" {print $2}' "${backup_dir}/state")"

	case "${enabled_state}" in
	enabled) systemctl enable "${service_name}" >/dev/null 2>&1 || true ;;
	disabled) systemctl disable "${service_name}" >/dev/null 2>&1 || true ;;
	masked) systemctl mask "${service_name}" >/dev/null 2>&1 || true ;;
	esac

	case "${active_state}" in
	active | activating | reloading) systemctl restart "${service_name}" >/dev/null 2>&1 || true ;;
	inactive | failed | deactivating) systemctl stop "${service_name}" >/dev/null 2>&1 || true ;;
	esac
}

restore_site_rollback() {
	local rollback_dir="$1"
	if [[ -d "${rollback_dir}/site" ]]; then
		rm -rf "${SITE_DIR}"
		mkdir -p "${SITE_DIR}"
		cp -a "${rollback_dir}/site/." "${SITE_DIR}/"
		chown -R "${APP_RUN_USER}:${APP_RUN_GROUP}" "${SITE_DIR}"
	fi
	if [[ -d "${rollback_dir}/scripts" ]]; then
		rm -rf "${SCRIPTS_DIR}"
		mkdir -p "${SCRIPTS_DIR}"
		cp -a "${rollback_dir}/scripts/." "${SCRIPTS_DIR}/"
		chown -R "${APP_RUN_USER}:${APP_RUN_GROUP}" "${SCRIPTS_DIR}"
	fi
}

create_activation_rollback() {
	local rollback_dir
	rollback_dir="$(create_site_rollback)"
	backup_managed_file "${APP_ENV_FILE}" "${rollback_dir}/app-env"
	backup_managed_file "${APP_SYSTEMD_UNIT}" "${rollback_dir}/systemd-unit"
	backup_managed_file "${INSTALL_YAML}" "${rollback_dir}/install-yaml"
	if [[ "${USE_CADDY}" == "1" ]]; then
		backup_managed_file "${CADDYFILE_PATH}" "${rollback_dir}/managed-caddyfile"
		backup_managed_file "${SYSTEM_CADDYFILE}" "${rollback_dir}/system-caddyfile"
		backup_service_state "caddy" "${rollback_dir}/caddy-service"
	fi
	if [[ "${BACKUP_ENABLED}" == "1" ]]; then
		backup_managed_file "${BACKUP_CRON_FILE}" "${rollback_dir}/backup-cron"
	fi
	printf '%s\n' "${rollback_dir}"
}

restore_activation_rollback() {
	local rollback_dir="$1"
	restore_site_rollback "${rollback_dir}"
	restore_managed_file "${rollback_dir}/app-env" "${APP_ENV_FILE}"
	restore_managed_file "${rollback_dir}/systemd-unit" "${APP_SYSTEMD_UNIT}"
	restore_managed_file "${rollback_dir}/install-yaml" "${INSTALL_YAML}"
	if [[ "${USE_CADDY}" == "1" ]]; then
		restore_managed_file "${rollback_dir}/managed-caddyfile" "${CADDYFILE_PATH}"
		restore_managed_file "${rollback_dir}/system-caddyfile" "${SYSTEM_CADDYFILE}"
		restore_service_state "caddy" "${rollback_dir}/caddy-service"
	fi
	if [[ "${BACKUP_ENABLED}" == "1" ]]; then
		restore_managed_file "${rollback_dir}/backup-cron" "${BACKUP_CRON_FILE}"
	fi
}

clear_activation_rollback() {
	local rollback_dir="$1"
	[[ -n "${rollback_dir}" ]] || return 0
	rm -rf "${rollback_dir}"
}

build_site_with_rollback() {
	local rollback_dir
	rollback_dir="$(create_site_rollback)"
	if ! build_site; then
		warn "构建失败，正在恢复上一个站点目录。"
		restore_site_rollback "${rollback_dir}"
		rm -rf "${rollback_dir}"
		return 1
	fi
	rm -rf "${rollback_dir}"
}

start_stack() {
	log "启动 EmDash 原生服务"
	systemctl daemon-reload
	if systemctl is-active --quiet "${APP_SYSTEMD_SERVICE}"; then
		systemctl stop "${APP_SYSTEMD_SERVICE}"
	fi
	if [[ "${DB_DRIVER}" == "postgres" ]]; then
		systemctl enable --now "${POSTGRES_SERVICE}"
	fi
	if [[ "${SESSION_DRIVER}" == "redis" ]]; then
		systemctl enable "${REDIS_SERVICE}" >/dev/null
		systemctl restart "${REDIS_SERVICE}"
	fi
	if ! build_site_with_rollback; then
		systemctl start "${APP_SYSTEMD_SERVICE}" || true
		return 1
	fi
	systemctl enable "${APP_SYSTEMD_SERVICE}" >/dev/null
	systemctl restart "${APP_SYSTEMD_SERVICE}"
}

print_summary() {
	local message="$1"
	cat <<EOF

${message}

$(ti summary_config_files)
  ${INSTALL_YAML}
  ${APP_ENV_FILE}

$(ti summary_project_paths)
  ${ROOT_DIR}
  ${SITE_DIR}
  ${APP_SYSTEMD_UNIT}

$(ti summary_control_commands)
  emdashctl status
  emdashctl logs app
  emdashctl restart app
EOF

	if [[ "${ACTIVATE_STACK:-0}" != "1" && "${WRITE_ONLY:-0}" != "1" ]]; then
		cat <<EOF

$(ti summary_start_services)
  systemctl daemon-reload
  systemctl enable --now ${APP_SYSTEMD_SERVICE}
EOF
	fi

	cat <<EOF

$(ti summary_access_urls)
  $(ti summary_site): ${APP_PUBLIC_URL}
  $(ti summary_admin): ${APP_PUBLIC_URL}/_emdash/admin
EOF
}
