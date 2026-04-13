#!/usr/bin/env bash

detect_os_family() {
	[[ -r /etc/os-release ]] || fail "无法读取 /etc/os-release。"
	# shellcheck disable=SC1091
	source /etc/os-release

	OS_ID="${ID:-unknown}"
	OS_VERSION_ID="${VERSION_ID:-0}"
	OS_LABEL="${PRETTY_NAME:-${OS_ID}}"
	OS_MAJOR="${OS_VERSION_ID%%.*}"
	OS_CODENAME="${VERSION_CODENAME:-}"
	POSTGRES_SERVICE="postgresql"
	REDIS_SERVICE="redis"

	case "${OS_ID}" in
	debian)
		case "${OS_MAJOR}" in
		13)
			[[ -n "${OS_CODENAME}" ]] || OS_CODENAME="trixie"
			REDIS_SERVICE="redis-server"
			;;
		*) fail "仅支持 Debian 13，当前为 ${OS_LABEL}" ;;
		esac
		;;
	ubuntu)
		case "${OS_MAJOR}" in
		24)
			[[ -n "${OS_CODENAME}" ]] || OS_CODENAME="noble"
			REDIS_SERVICE="redis-server"
			;;
		*) fail "仅支持 Ubuntu 24.04，当前为 ${OS_LABEL}" ;;
		esac
		;;
	rocky | almalinux | rhel | ol | centos | centos_stream)
		case "${OS_MAJOR}" in
		9 | 10)
			POSTGRES_SERVICE="postgresql-${PG_VERSION}"
			if [[ "${OS_MAJOR}" == "10" ]]; then
				REDIS_SERVICE="valkey"
			else
				REDIS_SERVICE="redis"
			fi
			;;
		*) fail "仅支持 EL 9/10，当前为 ${OS_LABEL}" ;;
		esac
		;;
	*)
		fail "当前系统不在支持范围内: ${OS_LABEL}"
		;;
	esac
}

choose_container_runtime() {
	:
}

apt_update() {
	apt-get update -y
}

install_base_packages() {
	log "安装基础依赖"
	if [[ "${OS_ID}" == "debian" || "${OS_ID}" == "ubuntu" ]]; then
		export DEBIAN_FRONTEND=noninteractive
		apt_update
		apt-get install -y \
			ca-certificates \
			curl \
			git \
			gnupg \
			python3 \
			python3-pip \
			dnsutils \
			openssh-client \
			tar \
			jq \
			cron \
			build-essential
		systemctl enable --now cron >/dev/null 2>&1 || true
		return
	fi

	dnf -y install \
		ca-certificates \
		curl \
		git \
		gnupg2 \
		python3 \
		python3-pip \
		bind-utils \
		openssh-clients \
		tar \
		jq \
		iproute \
		cronie \
		gcc \
		gcc-c++ \
		make
	systemctl enable --now crond >/dev/null 2>&1 || systemctl enable --now cronie >/dev/null 2>&1 || true
}

install_boto3_runtime() {
	if python3 - <<'PY' >/dev/null 2>&1; then
import importlib.util, sys
sys.exit(0 if importlib.util.find_spec("boto3") else 1)
PY
		return 0
	fi

	log "安装 Python boto3"
	if [[ "${OS_ID}" == "debian" || "${OS_ID}" == "ubuntu" ]]; then
		apt-get install -y python3-boto3
	else
		dnf -y install python3-boto3
	fi
}

install_nodesource_node() {
	local node_major=""
	if command_exists node; then
		node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)"
	fi
	if [[ "${node_major}" == "24" ]] && command_exists pnpm; then
		log "Node.js 24 和 pnpm 已安装"
		return
	fi

	log "安装 Node.js 24 (NodeSource)"
	if [[ "${OS_ID}" == "debian" || "${OS_ID}" == "ubuntu" ]]; then
		curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
		apt-get install -y nodejs
	else
		curl -fsSL https://rpm.nodesource.com/setup_24.x | bash -
		dnf -y install nodejs
	fi
	corepack enable || true
	corepack prepare pnpm@10.28.0 --activate
}

install_postgres_server() {
	[[ "${DB_DRIVER}" == "postgres" ]] || return 0

	if [[ "${OS_ID}" == "debian" || "${OS_ID}" == "ubuntu" ]]; then
		if ! dpkg -s "postgresql-${PG_VERSION}" >/dev/null 2>&1; then
			log "安装 PostgreSQL ${PG_VERSION} (PGDG)"
			install -d -m 0755 /etc/apt/keyrings
			curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg
			cat >/etc/apt/sources.list.d/pgdg.list <<EOF
deb [signed-by=/etc/apt/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt ${OS_CODENAME}-pgdg main
EOF
			apt_update
			apt-get install -y "postgresql-${PG_VERSION}" "postgresql-client-${PG_VERSION}"
		fi
		POSTGRES_SERVICE="postgresql"
	else
		if ! rpm -q "postgresql${PG_VERSION}-server" >/dev/null 2>&1; then
			log "安装 PostgreSQL ${PG_VERSION} (PGDG)"
			dnf -qy module disable postgresql || true
			dnf -y install "https://download.postgresql.org/pub/repos/yum/reporpms/EL-${OS_MAJOR}-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
			dnf -y install "postgresql${PG_VERSION}-server" "postgresql${PG_VERSION}"
		fi
		if [[ ! -f "/var/lib/pgsql/${PG_VERSION}/data/PG_VERSION" ]]; then
			"/usr/pgsql-${PG_VERSION}/bin/postgresql-${PG_VERSION}-setup" initdb
		fi
		POSTGRES_SERVICE="postgresql-${PG_VERSION}"
	fi

	systemctl enable --now "${POSTGRES_SERVICE}"
	configure_postgres_local
}

configure_postgres_local() {
	[[ "${DB_DRIVER}" == "postgres" ]] || return 0

	log "配置本机 PostgreSQL 数据库"
	PG_DB_USER_VALUE="${PG_DB_USER}" PG_DB_PASSWORD_VALUE="${PG_DB_PASSWORD}" python3 <<'PY' | runuser -u postgres -- psql postgres
import os

def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"

user = os.environ["PG_DB_USER_VALUE"]
password = os.environ["PG_DB_PASSWORD_VALUE"]

print(f"SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', {sql_literal(user)}, {sql_literal(password)})")
print(f"WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = {sql_literal(user)});")
print("\\gexec")
print(f"SELECT format('ALTER ROLE %I LOGIN PASSWORD %L', {sql_literal(user)}, {sql_literal(password)})")
print(f"WHERE EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = {sql_literal(user)});")
print("\\gexec")
PY
	if ! runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='${PG_DB_NAME}'" | grep -qx 1; then
		runuser -u postgres -- createdb -O "${PG_DB_USER}" "${PG_DB_NAME}"
	fi
}

install_redis_server() {
	[[ "${SESSION_DRIVER}" == "redis" ]] || return 0

	if [[ "${OS_ID}" == "debian" || "${OS_ID}" == "ubuntu" ]]; then
		dpkg -s redis-server >/dev/null 2>&1 || apt-get install -y redis-server
		REDIS_SERVICE="redis-server"
	elif [[ "${OS_MAJOR}" == "10" ]]; then
		rpm -q valkey >/dev/null 2>&1 || dnf -y install valkey
		REDIS_SERVICE="valkey"
	else
		rpm -q redis >/dev/null 2>&1 || dnf -y install redis
		REDIS_SERVICE="redis"
	fi

	configure_redis_local
	systemctl enable --now "${REDIS_SERVICE}"
}

configure_redis_local() {
	[[ "${SESSION_DRIVER}" == "redis" ]] || return 0

	local redis_conf=""
	for candidate in /etc/redis/redis.conf /etc/redis.conf /etc/valkey/valkey.conf /etc/valkey.conf; do
		if [[ -f "${candidate}" ]]; then
			redis_conf="${candidate}"
			break
		fi
	done
	[[ -f "${redis_conf}" ]] || fail "未找到 Redis 配置文件: ${redis_conf}"

	REDIS_CONF_PATH="${redis_conf}" REDIS_CONF_PASSWORD="${REDIS_PASSWORD}" python3 <<'PY'
from pathlib import Path
import os

path = Path(os.environ["REDIS_CONF_PATH"])
password = os.environ["REDIS_CONF_PASSWORD"]
lines = path.read_text().splitlines()

def rewrite(key, value):
    prefix = f"{key} "
    commented = f"#{key} "
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith(prefix) or stripped.startswith(commented):
            lines[idx] = f"{key} {value}"
            return
    lines.append(f"{key} {value}")

rewrite("bind", "127.0.0.1 ::1")
rewrite("protected-mode", "yes")
rewrite("requirepass", password)
rewrite("appendonly", "yes")
path.write_text("\n".join(lines) + "\n")
PY
}

install_caddy_package() {
	[[ "${USE_CADDY}" == "1" ]] || return 0

	if command_exists caddy; then
		log "Caddy 已安装"
		return
	fi

	log "安装 Caddy"
	if [[ "${OS_ID}" == "debian" || "${OS_ID}" == "ubuntu" ]]; then
		apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gpg
		curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
		curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
		chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list
		apt_update
		apt-get install -y caddy
	else
		dnf -y install dnf-plugins-core
		dnf copr enable -y @caddy/caddy
		dnf -y install caddy
	fi

	# Package postinst may auto-start caddy and occupy :80/:443 before our
	# own validation and activation flow runs.
	systemctl disable --now caddy >/dev/null 2>&1 || true
}

create_app_user() {
	if id "${APP_RUN_USER}" >/dev/null 2>&1; then
		return
	fi
	log "创建应用用户 ${APP_RUN_USER}"
	useradd --system --home-dir "${ROOT_DIR}" --create-home --shell /bin/bash "${APP_RUN_USER}"
}

ensure_build_memory_headroom() {
	local mem_kb="0"
	local swap_kb="0"
	local total_mb="0"
	local target_mb="2304"
	local create_mb="0"
	local swap_file="/swapfile.emdash"

	[[ "${WRITE_ONLY:-0}" != "1" ]] || return 0
	[[ "${ACTIVATE_STACK:-0}" == "1" ]] || return 0

	if [[ -r /proc/meminfo ]]; then
		mem_kb="$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)"
		swap_kb="$(awk '/^SwapTotal:/ { print $2 }' /proc/meminfo)"
	fi
	total_mb=$(( (mem_kb + swap_kb) / 1024 ))
	if (( total_mb >= target_mb )); then
		return 0
	fi
	if swapon --noheadings --show=NAME 2>/dev/null | grep -qx "${swap_file}"; then
		return 0
	fi

	create_mb=$(( target_mb - total_mb ))
	if (( create_mb < 1024 )); then
		create_mb=1024
	fi
	if (( create_mb > 4096 )); then
		create_mb=4096
	fi

	warn "检测到可用内存和 swap 总量较低（约 ${total_mb} MiB），为本地构建临时补充 ${create_mb} MiB swap。"
	if command_exists fallocate; then
		fallocate -l "${create_mb}M" "${swap_file}" 2>/dev/null || true
	fi
	if [[ ! -f "${swap_file}" || ! -s "${swap_file}" ]]; then
		dd if=/dev/zero of="${swap_file}" bs=1M count="${create_mb}" status=none
	fi
	chmod 0600 "${swap_file}"
	mkswap "${swap_file}" >/dev/null
	swapon "${swap_file}"
	if [[ -w /etc/fstab ]] && ! grep -Fq "${swap_file} none swap sw 0 0" /etc/fstab; then
		printf '%s\n' "${swap_file} none swap sw 0 0" >>/etc/fstab
	fi
}

activate_caddy_service() {
	[[ "${USE_CADDY}" == "1" ]] || return 0
	command_exists caddy || fail "未安装 caddy，无法启用服务。"
	[[ -f "${CADDYFILE_PATH}" ]] || fail "未找到 Caddyfile: ${CADDYFILE_PATH}"

	open_required_firewall_ports
	install -d -m 0755 /etc/caddy
	install -d -m 0755 /var/lib/caddy
	install -d -m 0755 "${CADDY_DIR}"
	chown -R caddy:caddy /var/lib/caddy "${CADDY_DIR}"
	if command_exists restorecon; then
		restorecon -RF /etc/caddy "${CADDY_DIR}" "${CADDYFILE_PATH}" /var/lib/caddy >/dev/null 2>&1 || true
	fi
	if [[ -e /etc/caddy/Caddyfile && ! -L /etc/caddy/Caddyfile ]]; then
		cp -a /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.emdash.bak.$(date +%Y%m%d-%H%M%S)"
	fi
	ln -sfn "${CADDYFILE_PATH}" /etc/caddy/Caddyfile
	caddy validate --config /etc/caddy/Caddyfile
	systemctl enable --now caddy
}

open_required_firewall_ports() {
	local ports=()
	local port

	if [[ "${USE_CADDY}" == "1" ]]; then
		ports=(80 443)
	else
		ports=("${APP_PORT}")
	fi

	if command_exists firewall-cmd && systemctl is-active firewalld >/dev/null 2>&1; then
		for port in "${ports[@]}"; do
			firewall-cmd --quiet --permanent --add-port="${port}/tcp" || true
		done
		firewall-cmd --reload >/dev/null 2>&1 || true
	fi

	if command_exists ufw && ufw status 2>/dev/null | grep -q "Status: active"; then
		for port in "${ports[@]}"; do
			ufw allow "${port}/tcp" >/dev/null 2>&1 || true
		done
	fi
}

install_backup_schedule() {
	[[ "${BACKUP_ENABLED}" == "1" ]] || return 0
	local cron_file="/etc/cron.d/emdash-backup"
	cat >"${cron_file}" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${BACKUP_SCHEDULE} root /usr/local/bin/emdashctl backup >> ${LOG_DIR}/backup.log 2>&1
EOF
	chmod 0644 "${cron_file}"
}

install_runtime_stack() {
	install_base_packages
	install_nodesource_node
	create_app_user
	install_postgres_server
	install_redis_server
	if [[ "${USE_CADDY}" == "1" ]]; then
		install_caddy_package
	fi
}

ensure_runtime_present() {
	command_exists node || fail "未检测到 node。"
	command_exists pnpm || fail "未检测到 pnpm。"
	if [[ "${DB_DRIVER}" == "postgres" ]]; then
		systemctl is-enabled "${POSTGRES_SERVICE}" >/dev/null 2>&1 || true
	fi
	if [[ "${SESSION_DRIVER}" == "redis" ]]; then
		systemctl is-enabled "${REDIS_SERVICE}" >/dev/null 2>&1 || true
	fi
	if [[ "${USE_CADDY}" == "1" ]] && ! command_exists caddy; then
		fail "未检测到 caddy。"
	fi
}
