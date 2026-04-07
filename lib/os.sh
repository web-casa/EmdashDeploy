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

	case "${OS_ID}" in
	debian)
		case "${OS_MAJOR}" in
		12)
			CONTAINER_RUNTIME="docker"
			[[ -n "${OS_CODENAME}" ]] || OS_CODENAME="bookworm"
			;;
		13)
			CONTAINER_RUNTIME="docker"
			[[ -n "${OS_CODENAME}" ]] || OS_CODENAME="trixie"
			;;
		*) fail "仅支持 Debian 12/13，当前为 ${OS_LABEL}" ;;
		esac
		;;
	ubuntu)
		case "${OS_MAJOR}" in
		22)
			CONTAINER_RUNTIME="docker"
			[[ -n "${OS_CODENAME}" ]] || OS_CODENAME="jammy"
			;;
		24)
			CONTAINER_RUNTIME="docker"
			[[ -n "${OS_CODENAME}" ]] || OS_CODENAME="noble"
			;;
		*) fail "仅支持 Ubuntu 22/24，当前为 ${OS_LABEL}" ;;
		esac
		;;
	rocky | almalinux | rhel | ol | centos | centos_stream)
		case "${OS_MAJOR}" in
		8 | 9 | 10) CONTAINER_RUNTIME="podman" ;;
		*) fail "仅支持 EL 8/9/10，当前为 ${OS_LABEL}" ;;
		esac
		;;
	*)
		fail "当前系统不在支持范围内: ${OS_LABEL}"
		;;
	esac
}

choose_container_runtime() {
	if [[ "${CONTAINER_RUNTIME}" == "docker" ]]; then
		COMPOSE_BINARY="docker compose"
	else
		COMPOSE_BINARY="podman compose"
	fi
}

apt_update() {
	apt-get update -y
}

install_base_packages() {
	log "安装基础依赖"
	if [[ "${CONTAINER_RUNTIME}" == "docker" ]]; then
		export DEBIAN_FRONTEND=noninteractive
		apt_update
		apt-get install -y \
			ca-certificates \
			curl \
			git \
			gnupg \
			python3 \
			dnsutils \
			openssh-client \
			tar \
			jq \
			cron
		if [[ "${BACKUP_TARGET_TYPE:-local}" == "sftp" && -n "${BACKUP_SFTP_PASSWORD:-}" ]]; then
			apt-get install -y sshpass
		fi
		systemctl enable --now cron >/dev/null 2>&1 || true
		return
	fi

	if command_exists dnf; then
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
			cronie
		if [[ "${BACKUP_TARGET_TYPE:-local}" == "sftp" && -n "${BACKUP_SFTP_PASSWORD:-}" ]]; then
			dnf -y install sshpass || true
		fi
	else
		yum -y install \
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
			cronie
	fi
	systemctl enable --now crond >/dev/null 2>&1 || systemctl enable --now cronie >/dev/null 2>&1 || true
}

install_docker_engine() {
	if command_exists docker && docker compose version >/dev/null 2>&1; then
		log "Docker 和 docker compose 已安装"
		systemctl enable --now docker >/dev/null 2>&1 || true
		return
	fi

	log "安装 Docker Engine"
	apt-get remove -y docker.io docker-doc docker-compose podman-docker containerd runc || true
	apt-get install -y ca-certificates curl
	install -m 0755 -d /etc/apt/keyrings
	curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" -o /etc/apt/keyrings/docker.asc
	chmod a+r /etc/apt/keyrings/docker.asc
	cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/${OS_ID}
Suites: ${OS_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
	apt_update
	apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
	systemctl enable --now docker
}

install_podman_stack() {
	if command_exists podman; then
		log "Podman 已安装"
	else
		log "安装 Podman"
		if command_exists dnf; then
			dnf -y install podman slirp4netns fuse-overlayfs
			dnf -y install podman-plugins || true
		else
			yum -y install podman slirp4netns fuse-overlayfs
			yum -y install podman-plugins || true
		fi
	fi

	command_exists podman || fail "Podman 安装失败。"

	if podman compose version >/dev/null 2>&1; then
		PODMAN_COMPOSE_PROVIDER_BIN=""
		return
	fi

	if command_exists podman-compose; then
		PODMAN_COMPOSE_PROVIDER_BIN="$(command -v podman-compose)"
		return
	fi

	log "安装 podman compose provider"
	if command_exists dnf; then
		dnf -y install podman-compose || true
	elif command_exists yum; then
		yum -y install podman-compose || true
	fi

	if command_exists podman-compose; then
		PODMAN_COMPOSE_PROVIDER_BIN="$(command -v podman-compose)"
		return
	fi

	if [[ "${OS_MAJOR:-0}" == "8" ]]; then
		if command_exists dnf; then
			dnf -y install python39 python39-pip || true
		elif command_exists yum; then
			yum -y install python39 python39-pip || true
		fi
	fi

	if command_exists python3.9; then
		python3.9 -m pip install podman-compose
	elif command_exists pip3; then
		pip3 install podman-compose
	fi

	if command_exists podman-compose; then
		PODMAN_COMPOSE_PROVIDER_BIN="$(command -v podman-compose)"
		return
	fi

	fail "未能安装可用的 podman compose provider。"
}

install_caddy_package() {
	[[ "${USE_CADDY}" == "1" ]] || return 0

	if command_exists caddy; then
		log "Caddy 已安装"
		return
	fi

	log "安装 Caddy"
	if [[ "${CONTAINER_RUNTIME}" == "docker" ]]; then
		apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gpg
		curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
		curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
		chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
		chmod o+r /etc/apt/sources.list.d/caddy-stable.list
		apt_update
		apt-get install -y caddy
		return
	fi

	if command_exists dnf; then
		dnf -y install dnf-plugins-core
		dnf copr enable -y @caddy/caddy
		dnf -y install caddy
	else
		yum -y install dnf-plugins-core
		dnf copr enable -y @caddy/caddy
		dnf -y install caddy
	fi
}

activate_caddy_service() {
	[[ "${USE_CADDY}" == "1" ]] || return 0
	command_exists caddy || fail "未安装 caddy，无法启用服务。"
	[[ -f "${CADDYFILE_PATH}" ]] || fail "未找到 Caddyfile: ${CADDYFILE_PATH}"
	open_required_firewall_ports

	install -d -m 0755 /etc/caddy
	if id caddy >/dev/null 2>&1; then
		install -d -o caddy -g caddy -m 0755 "${LOG_DIR}"
		touch "${LOG_DIR}/caddy-access.log"
		chown caddy:caddy "${LOG_DIR}/caddy-access.log"
	fi
	if [[ -e /etc/caddy/Caddyfile && ! -L /etc/caddy/Caddyfile ]]; then
		cp -a /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.emdash.bak.$(date +%Y%m%d-%H%M%S)"
	fi

	ln -sfn "${CADDYFILE_PATH}" /etc/caddy/Caddyfile
	caddy validate --config /etc/caddy/Caddyfile
	systemctl enable caddy
	systemctl restart caddy
}

open_required_firewall_ports() {
	local ports=()
	local port

	if [[ "${USE_CADDY}" == "1" ]]; then
		ports=(80 443)
	elif [[ "${APP_BIND_HOST:-127.0.0.1}" != "127.0.0.1" ]]; then
		ports=("${APP_PORT}")
	else
		return 0
	fi

	if command_exists firewall-cmd && systemctl is-active firewalld >/dev/null 2>&1; then
		for port in "${ports[@]}"; do
			firewall-cmd --quiet --permanent --add-port="${port}/tcp" || true
		done
		firewall-cmd --reload >/dev/null 2>&1 || true
	fi

	if command_exists ufw; then
		if ufw status 2>/dev/null | grep -q "Status: active"; then
			for port in "${ports[@]}"; do
				ufw allow "${port}/tcp" >/dev/null 2>&1 || true
			done
		fi
	fi
}

install_backup_schedule() {
	[[ "${BACKUP_ENABLED}" == "1" ]] || return 0
	local emdashctl_bin="/usr/local/bin/emdashctl"
	if [[ ! -x "${emdashctl_bin}" && -n "${SCRIPT_DIR:-}" && -x "${SCRIPT_DIR}/emdashctl" ]]; then
		emdashctl_bin="${SCRIPT_DIR}/emdashctl"
	fi
	[[ -x "${emdashctl_bin}" ]] || fail "未找到 emdashctl，无法安装备份计划。"

	local cron_file="/etc/cron.d/emdash-backup"
	cat >"${cron_file}" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${BACKUP_SCHEDULE} root ${emdashctl_bin} backup >> ${LOG_DIR}/backup.log 2>&1
EOF
	chmod 0644 "${cron_file}"
}

install_runtime_stack() {
	install_base_packages
	if [[ "${CONTAINER_RUNTIME}" == "docker" ]]; then
		install_docker_engine
	else
		install_podman_stack
	fi
}

ensure_runtime_present() {
	if [[ "${CONTAINER_RUNTIME}" == "docker" ]]; then
		command_exists docker || fail "未检测到 docker。请先安装 Docker。"
		docker compose version >/dev/null 2>&1 || fail "未检测到 docker compose。"
	else
		command_exists podman || fail "未检测到 podman。请先安装 Podman。"
		if podman compose version >/dev/null 2>&1; then
			:
		elif command_exists podman-compose; then
			PODMAN_COMPOSE_PROVIDER_BIN="$(command -v podman-compose)"
		elif [[ -n "${PODMAN_COMPOSE_PROVIDER_BIN:-}" && -x "${PODMAN_COMPOSE_PROVIDER_BIN}" ]]; then
			:
		else
			fail "未检测到 podman compose provider。"
		fi
	fi

	if [[ "${USE_CADDY}" == "1" ]] && [[ ! -x /usr/local/bin/caddy ]] && ! command_exists caddy; then
		fail "未检测到 caddy。"
	fi
}
