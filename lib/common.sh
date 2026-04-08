#!/usr/bin/env bash

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

log() {
	printf '[INFO] %s\n' "$*"
}

warn() {
	printf '[WARN] %s\n' "$*" >&2
}

fail() {
	printf '[ERROR] %s\n' "$*" >&2
	exit 1
}

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

require_root() {
	if [[ "${EUID}" -ne 0 ]]; then
		if declare -F ti >/dev/null 2>&1; then
			fail "$(ti require_root)"
		fi
		fail "Please run the installer as root."
	fi
}

normalize_bool() {
	local value="${1:-}"
	case "${value,,}" in
	1 | y | yes | true | on) printf '1\n' ;;
	0 | n | no | false | off) printf '0\n' ;;
	*) printf '%s\n' "${value}" ;;
	esac
}

ensure_dir() {
	mkdir -p "$1"
}

escape_sed() {
	printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

compose_cmd() {
	if [[ "${CONTAINER_RUNTIME}" == "docker" ]]; then
		printf 'docker compose'
	else
		printf 'podman compose'
	fi
}

run_compose() {
	local compose_file="$1"
	shift

	if [[ "${CONTAINER_RUNTIME}" == "docker" ]]; then
		docker compose -f "${compose_file}" "$@"
	elif [[ -n "${PODMAN_COMPOSE_PROVIDER_BIN:-}" ]]; then
		env -u PODMAN_COMPOSE_PROVIDER_BIN "${PODMAN_COMPOSE_PROVIDER_BIN}" -f "${compose_file}" "$@"
	else
		podman compose -f "${compose_file}" "$@"
	fi
}

random_hex() {
	local bytes="${1:-16}"
	openssl rand -hex "${bytes}"
}

wait_for_http_ok() {
	local url="$1"
	local max_attempts="${2:-30}"
	local sleep_seconds="${3:-2}"
	local attempt=1

	while [[ "${attempt}" -le "${max_attempts}" ]]; do
		if curl -fsS --max-time 5 "${url}" >/dev/null 2>&1; then
			return 0
		fi
		sleep "${sleep_seconds}"
		attempt=$((attempt + 1))
	done

	return 1
}

http_get_json() {
	local url="$1"
	curl -fsS --max-time 5 "${url}"
}

json_escape_file() {
	python3 -c 'import json, pathlib, sys; print(json.dumps(pathlib.Path(sys.argv[1]).read_text()))' "$1"
}
