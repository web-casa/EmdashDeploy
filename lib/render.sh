#!/usr/bin/env bash

json_literal() {
	python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

url_quote() {
	python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

prepare_layout() {
	ensure_dir "${CONFIG_DIR}"
	ensure_dir "${ROOT_DIR}"
	ensure_dir "${APP_DIR}"
	ensure_dir "${COMPOSE_DIR}"
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
}

clone_template_repo() {
	if [[ -f "${SITE_DIR}/package.json" ]]; then
		log "检测到现有 EmDash 模板目录，跳过拉取"
		return
	fi

	local tmp_repo
	tmp_repo="$(mktemp -d)"
	log "拉取 EmDash 模板 ${TEMPLATE}"
	git clone --depth 1 --branch "${TEMPLATES_REF}" "${TEMPLATES_REPO}" "${tmp_repo}/templates"
	ensure_dir "${SITE_DIR}"
	cp -a "${tmp_repo}/templates/${TEMPLATE}/." "${SITE_DIR}/"
	rm -rf "${tmp_repo}"
}

patch_template_package_json() {
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
	local session_block=""
	local session_import=""
	local storage_block=""
	local db_import=""
	local db_block=""
	local sqlite_url_literal=""
	local postgres_url_literal=""
	local redis_url_literal=""
	local s3_endpoint_literal=""
	local s3_region_literal=""
	local s3_bucket_literal=""
	local s3_access_key_literal=""
	local s3_secret_key_literal=""
	local s3_public_url_literal=""
	local pg_user_encoded=""
	local pg_password_encoded=""
	local pg_db_name_encoded=""
	local redis_password_encoded=""

	pg_user_encoded="$(url_quote "${PG_DB_USER}")"
	pg_password_encoded="$(url_quote "${PG_DB_PASSWORD}")"
	pg_db_name_encoded="$(url_quote "${PG_DB_NAME}")"
	redis_password_encoded="$(url_quote "${REDIS_PASSWORD}")"

	sqlite_url_literal="$(json_literal "file:./data/sqlite/data.db")"
	postgres_url_literal="$(json_literal "postgres://${pg_user_encoded}:${pg_password_encoded}@postgres:5432/${pg_db_name_encoded}")"
	redis_url_literal="$(json_literal "redis://:${redis_password_encoded}@redis:6379/${REDIS_DATABASE}")"
	s3_endpoint_literal="$(json_literal "${S3_ENDPOINT}")"
	s3_region_literal="$(json_literal "${S3_REGION}")"
	s3_bucket_literal="$(json_literal "${S3_BUCKET}")"
	s3_access_key_literal="$(json_literal "${S3_ACCESS_KEY_ID}")"
	s3_secret_key_literal="$(json_literal "${S3_SECRET_ACCESS_KEY}")"
	s3_public_url_literal="$(json_literal "${S3_PUBLIC_URL}")"

	if [[ "${SESSION_DRIVER}" == "redis" ]]; then
		session_import='import { defineConfig, sessionDrivers } from "astro/config";'
		session_block='	session: {
		driver: sessionDrivers.redis({
			url: '"${redis_url_literal}"',
		}),
	},
'
	else
		session_import='import { defineConfig } from "astro/config";'
		session_block=''
	fi

	if [[ "${STORAGE_DRIVER}" == "s3" ]]; then
		storage_block='storage: s3({
				endpoint: '"${s3_endpoint_literal}"',
				region: '"${s3_region_literal}"',
				bucket: '"${s3_bucket_literal}"',
				accessKeyId: '"${s3_access_key_literal}"',
				secretAccessKey: '"${s3_secret_key_literal}"',
				publicUrl: '"${s3_public_url_literal}"' || undefined,
			}),'
	else
		storage_block='storage: local({
				directory: "./uploads",
				baseUrl: "/_emdash/api/media/file",
			}),'
	fi

	if [[ "${DB_DRIVER}" == "postgres" ]]; then
		db_import='import { postgres } from "emdash/db";'
		db_block='database: postgres({
				connectionString: '"${postgres_url_literal}"',
			}),'
	else
		db_import='import { sqlite } from "emdash/db";'
		db_block='database: sqlite({
				url: '"${sqlite_url_literal}"',
			}),'
	fi

	cat >"${SITE_DIR}/astro.config.mjs" <<EOF
import node from "@astrojs/node";
import react from "@astrojs/react";
${session_import}
import emdash, { local, s3 } from "emdash/astro";
${db_import}

export default defineConfig({
	output: "server",
	adapter: node({
		mode: "standalone",
	}),
${session_block}	image: {
		layout: "constrained",
		responsiveStyles: true,
	},
	integrations: [
		react(),
		emdash({
			${db_block}
			${storage_block}
		}),
	],
	devToolbar: { enabled: false },
});
EOF
}

render_app_dockerfile() {
	cat >"${SITE_DIR}/Dockerfile" <<'EOF'
ARG EMDASH_BASE_IMAGE=node:24-bookworm-slim
FROM ${EMDASH_BASE_IMAGE} AS base
WORKDIR /app
ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN if ! command -v python3 >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1 || ! command -v g++ >/dev/null 2>&1; then \
		apt-get update \
		&& apt-get install -y --no-install-recommends python3 make g++ \
		&& rm -rf /var/lib/apt/lists/*; \
	fi
RUN corepack enable || true

COPY . .
RUN corepack prepare pnpm@10.28.0 --activate && pnpm install --no-frozen-lockfile && pnpm build

ENV HOST=0.0.0.0
ENV PORT=3000
EXPOSE 3000
CMD ["./docker-entrypoint.sh"]
EOF
}

render_app_entrypoint() {
	cat >"${SITE_DIR}/docker-entrypoint.sh" <<'EOF'
#!/usr/bin/env sh
set -eu

if [ "${DB_DRIVER:-sqlite}" = "sqlite" ]; then
	db_path="${DATABASE_PATH:-./data/sqlite/data.db}"
	db_dir="$(dirname "${db_path}")"
	mkdir -p "${db_dir}"
	if [ ! -f "${db_path}" ]; then
		pnpm exec emdash init --database "${db_path}"
	fi
fi

exec node ./dist/server/entry.mjs
EOF
	chmod 0755 "${SITE_DIR}/docker-entrypoint.sh"
}

render_health_endpoint() {
	ensure_dir "${SITE_DIR}/src/pages"
	cat >"${SITE_DIR}/src/pages/healthz.ts" <<'EOF'
export const GET = () => {
	return new Response("OK", { status: 200 });
};
EOF
}

render_compose_file() {
	local postgres_service=""
	local redis_service=""
	local mount_suffix=""
	local depends_on_block=""
	local app_build_block=""
	local app_image_block=""

	if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
		mount_suffix=":Z"
	fi

	if [[ "${DB_DRIVER}" == "postgres" || "${SESSION_DRIVER}" == "redis" ]]; then
		depends_on_block="    depends_on:"
		if [[ "${DB_DRIVER}" == "postgres" ]]; then
			depends_on_block+=$'\n'"      postgres:"
			depends_on_block+=$'\n'"        condition: service_healthy"
		fi
		if [[ "${SESSION_DRIVER}" == "redis" ]]; then
			depends_on_block+=$'\n'"      redis:"
			depends_on_block+=$'\n'"        condition: service_started"
		fi
	fi

	if [[ "${DB_DRIVER}" == "postgres" ]]; then
		postgres_service=$(cat <<EOF
  postgres:
    image: docker.io/library/postgres:${PG_VERSION}
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${PG_DB_NAME}
      POSTGRES_USER: ${PG_DB_USER}
      POSTGRES_PASSWORD: ${PG_DB_PASSWORD}
      TZ: ${TIMEZONE}
    volumes:
      - ${POSTGRES_DIR}:/var/lib/postgresql${mount_suffix}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${PG_DB_USER} -d ${PG_DB_NAME}"]
      interval: 15s
      timeout: 5s
      retries: 10
EOF
)
	fi

	if [[ "${SESSION_DRIVER}" == "redis" ]]; then
		redis_service=$(cat <<EOF
  redis:
    image: docker.io/library/redis:7.4-alpine
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes", "--requirepass", "${REDIS_PASSWORD}"]
    volumes:
      - ${REDIS_DIR}:/data${mount_suffix}
EOF
)
	fi

	app_build_block=$(cat <<EOF
    build:
      context: ${SITE_DIR}
      dockerfile: Dockerfile
      args:
        EMDASH_BASE_IMAGE: ${APP_BASE_IMAGE}
EOF
)

	if [[ -n "${APP_IMAGE}" ]]; then
		app_image_block="    image: ${APP_IMAGE}"
	fi

	cat >"${COMPOSE_FILE}" <<EOF
services:
  app:
${app_image_block}
${app_build_block}
    restart: unless-stopped
    env_file:
      - ${COMPOSE_ENV_FILE}
    ports:
      - "${APP_BIND_HOST}:${APP_PORT}:3000"
    volumes:
      - ${UPLOADS_DIR}:/app/uploads${mount_suffix}
      - ${SQLITE_DIR}:/app/data/sqlite${mount_suffix}
      - ${SESSIONS_DIR}:/app/sessions${mount_suffix}
    healthcheck:
      test: ["CMD-SHELL", "node -e \"fetch('http://127.0.0.1:3000/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\""]
      interval: 20s
      timeout: 5s
      retries: 10
${depends_on_block}
${postgres_service}
${redis_service}
EOF
}

render_compose_env() {
	local pg_user_encoded=""
	local pg_password_encoded=""
	local pg_db_name_encoded=""
	local redis_password_encoded=""

	pg_user_encoded="$(url_quote "${PG_DB_USER}")"
	pg_password_encoded="$(url_quote "${PG_DB_PASSWORD}")"
	pg_db_name_encoded="$(url_quote "${PG_DB_NAME}")"
	redis_password_encoded="$(url_quote "${REDIS_PASSWORD}")"

	cat >"${COMPOSE_ENV_FILE}" <<EOF
HOST=0.0.0.0
PORT=3000
DATABASE_PATH=./data/sqlite/data.db
PROJECT_NAME=${PROJECT_NAME}
ROOT_DIR=${ROOT_DIR}
COMPOSE_FILE=${COMPOSE_FILE}
CONTAINER_RUNTIME=${CONTAINER_RUNTIME}
TIMEZONE=${TIMEZONE}
APP_PORT=${APP_PORT}
APP_BIND_HOST=${APP_BIND_HOST}
APP_PUBLIC_URL=${APP_PUBLIC_URL}
APP_IMAGE=${APP_IMAGE}
APP_BASE_IMAGE=${APP_BASE_IMAGE}
DB_DRIVER=${DB_DRIVER}
SESSION_DRIVER=${SESSION_DRIVER}
STORAGE_DRIVER=${STORAGE_DRIVER}
USE_CADDY=${USE_CADDY}
DOMAIN=${DOMAIN}
ADMIN_EMAIL=${ADMIN_EMAIL}
EMDASH_AUTH_SECRET=${EMDASH_AUTH_SECRET}
EMDASH_PREVIEW_SECRET=${EMDASH_PREVIEW_SECRET}
SQLITE_PATH=${SQLITE_PATH}
UPLOADS_DIR=${UPLOADS_DIR}
SESSIONS_DIR=${SESSIONS_DIR}
POSTGRES_DIR=${POSTGRES_DIR}
REDIS_DIR=${REDIS_DIR}
DATABASE_URL=$( [[ "${DB_DRIVER}" == "postgres" ]] && printf 'postgres://%s:%s@postgres:5432/%s' "${pg_user_encoded}" "${pg_password_encoded}" "${pg_db_name_encoded}" )
PG_DB_NAME=${PG_DB_NAME}
PG_DB_USER=${PG_DB_USER}
PG_DB_PASSWORD=${PG_DB_PASSWORD}
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_DB=${REDIS_DATABASE}
REDIS_URL=redis://:${redis_password_encoded}@redis:6379/${REDIS_DATABASE}
PODMAN_COMPOSE_PROVIDER_BIN=${PODMAN_COMPOSE_PROVIDER_BIN:-}
S3_PROVIDER=${S3_PROVIDER}
S3_ENDPOINT=${S3_ENDPOINT}
S3_REGION=${S3_REGION}
S3_BUCKET=${S3_BUCKET}
S3_ACCESS_KEY_ID=${S3_ACCESS_KEY_ID}
S3_SECRET_ACCESS_KEY=${S3_SECRET_ACCESS_KEY}
S3_PUBLIC_URL=${S3_PUBLIC_URL}
BACKUP_ENABLED=${BACKUP_ENABLED}
BACKUP_SCHEDULE="${BACKUP_SCHEDULE}"
BACKUP_KEEP_LOCAL=${BACKUP_KEEP_LOCAL}
BACKUP_TARGET_TYPE=${BACKUP_TARGET_TYPE}
BACKUP_S3_ENDPOINT=${BACKUP_S3_ENDPOINT}
BACKUP_S3_REGION=${BACKUP_S3_REGION}
BACKUP_S3_BUCKET=${BACKUP_S3_BUCKET}
BACKUP_S3_ACCESS_KEY_ID=${BACKUP_S3_ACCESS_KEY_ID}
BACKUP_S3_SECRET_ACCESS_KEY=${BACKUP_S3_SECRET_ACCESS_KEY}
BACKUP_S3_PREFIX=${BACKUP_S3_PREFIX}
EOF
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
  container_runtime: ${CONTAINER_RUNTIME}
network:
  public_ipv4: ${PUBLIC_IPV4}
  public_ipv6: ${PUBLIC_IPV6}
  bind_host: ${APP_BIND_HOST}
  app_port: ${APP_PORT}
web:
  use_caddy: ${USE_CADDY}
  enable_https: ${ENABLE_HTTPS}
app:
  image: ${APP_IMAGE}
  base_image: ${APP_BASE_IMAGE}
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
    s3_access_key_id: ${BACKUP_S3_ACCESS_KEY_ID}
    s3_secret_access_key_set: $( [[ -n "${BACKUP_S3_SECRET_ACCESS_KEY}" ]] && printf 'true' || printf 'false' )
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
		output file ${LOG_DIR}/caddy-access.log {
			roll_size ${LOG_CADDY_ROTATE_SIZE_MB}MiB
			roll_keep ${LOG_CADDY_ROTATE_KEEP}
			roll_keep_for ${LOG_CADDY_ROTATE_KEEP_DAYS}d
		}
	}

	reverse_proxy 127.0.0.1:${APP_PORT}
}
EOF
}

install_emdashctl_script() {
	install -m 0755 "${SCRIPT_DIR}/emdashctl" /usr/local/bin/emdashctl
	local wrapper
	for wrapper in \
		emdashctl.en.sh \
		emdashctl.ja.sh \
		emdashctl.ko.sh \
		emdashctl.es.sh \
		emdashctl.de.sh \
		emdashctl.fr.sh \
		emdashctl.zh-CN.sh \
		emdashctl.zh-TW.sh \
		emdashctl.pt.sh; do
		if [[ -f "${SCRIPT_DIR}/${wrapper}" ]]; then
			install -m 0755 "${SCRIPT_DIR}/${wrapper}" "/usr/local/bin/${wrapper}"
		fi
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

start_stack() {
	log "启动 EmDash compose stack"
	if [[ -n "${APP_IMAGE:-}" ]]; then
		log "尝试拉取预构建 app 镜像 ${APP_IMAGE}"
		if run_compose "${COMPOSE_FILE}" pull app; then
			run_compose "${COMPOSE_FILE}" up -d
			return 0
		fi
		warn "预构建 app 镜像拉取失败，回退本地 build"
	fi
	run_compose "${COMPOSE_FILE}" up -d --build
}

print_summary() {
	local message="$1"
	cat <<EOF

${message}

$(ti summary_config_files)
  ${INSTALL_YAML}
  ${COMPOSE_ENV_FILE}

$(ti summary_project_paths)
  ${ROOT_DIR}
  ${SITE_DIR}
  ${COMPOSE_FILE}

$(ti summary_control_commands)
  emdashctl status
  emdashctl logs app
  emdashctl restart app
EOF

	if [[ "${ACTIVATE_STACK:-0}" != "1" && "${WRITE_ONLY:-0}" != "1" ]]; then
		cat <<EOF

$(ti summary_start_services)
  cd ${COMPOSE_DIR}
  $(compose_cmd) up -d
EOF
	fi

	cat <<EOF

$(ti summary_access_urls)
  $(ti summary_site): ${APP_PUBLIC_URL}
  $(ti summary_admin): ${APP_PUBLIC_URL}/_emdash/admin
EOF
}
