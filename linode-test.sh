#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-${SCRIPT_DIR}/.env}"
LINODE_API_BASE="${LINODE_API_BASE:-https://api.linode.com/v4}"
LINODE_TEST_IMAGE="${LINODE_TEST_IMAGE:-linode/ubuntu24.04}"
LINODE_TEST_TYPE="${LINODE_TEST_TYPE:-g6-standard-1}"
LINODE_TEST_REGION_CANDIDATES="${LINODE_TEST_REGION_CANDIDATES:-us-lax,us-west,us-east}"
LINODE_TEST_LABEL_PREFIX="${LINODE_TEST_LABEL_PREFIX:-emdash-test}"
LINODE_TEST_KEEP="${LINODE_TEST_KEEP:-0}"
LINODE_TEST_SSH_USER="${LINODE_TEST_SSH_USER:-root}"
LINODE_TEST_CREATE_TIMEOUT="${LINODE_TEST_CREATE_TIMEOUT:-900}"
LINODE_TEST_SSH_TIMEOUT="${LINODE_TEST_SSH_TIMEOUT:-600}"
LINODE_TEST_REMOTE_DIR="${LINODE_TEST_REMOTE_DIR:-/root/emdash-1key}"
LINODE_TEST_RESULT_FILE="${LINODE_TEST_RESULT_FILE:-${SCRIPT_DIR}/linode-test-result.json}"
LINODE_TEST_FAILURE_LOG="${LINODE_TEST_FAILURE_LOG:-${SCRIPT_DIR}/linode-test-failure.log}"
LINODE_TEST_INSTALL_DB_DRIVER="${LINODE_TEST_INSTALL_DB_DRIVER:-sqlite}"
LINODE_TEST_INSTALL_SESSION_DRIVER="${LINODE_TEST_INSTALL_SESSION_DRIVER:-file}"
LINODE_TEST_INSTALL_STORAGE_DRIVER="${LINODE_TEST_INSTALL_STORAGE_DRIVER:-local}"
LINODE_TEST_INSTALL_USE_CADDY="${LINODE_TEST_INSTALL_USE_CADDY:-0}"
LINODE_TEST_INSTALL_ENABLE_HTTPS="${LINODE_TEST_INSTALL_ENABLE_HTTPS:-0}"
LINODE_TEST_INSTALL_PG_PASSWORD="${LINODE_TEST_INSTALL_PG_PASSWORD:-}"
LINODE_TEST_INSTALL_REDIS_PASSWORD="${LINODE_TEST_INSTALL_REDIS_PASSWORD:-}"
LINODE_TEST_INSTALL_APP_IMAGE="${LINODE_TEST_INSTALL_APP_IMAGE:-}"
LINODE_TEST_INSTALL_APP_BASE_IMAGE="${LINODE_TEST_INSTALL_APP_BASE_IMAGE:-}"
LINODE_TEST_INSTALL_S3_PROVIDER="${LINODE_TEST_INSTALL_S3_PROVIDER:-}"
LINODE_TEST_INSTALL_S3_ENDPOINT="${LINODE_TEST_INSTALL_S3_ENDPOINT:-}"
LINODE_TEST_INSTALL_S3_REGION="${LINODE_TEST_INSTALL_S3_REGION:-}"
LINODE_TEST_INSTALL_S3_BUCKET="${LINODE_TEST_INSTALL_S3_BUCKET:-}"
LINODE_TEST_INSTALL_S3_ACCESS_KEY_ID="${LINODE_TEST_INSTALL_S3_ACCESS_KEY_ID:-}"
LINODE_TEST_INSTALL_S3_SECRET_ACCESS_KEY="${LINODE_TEST_INSTALL_S3_SECRET_ACCESS_KEY:-}"
LINODE_TEST_INSTALL_S3_PUBLIC_URL="${LINODE_TEST_INSTALL_S3_PUBLIC_URL:-}"
LINODE_TEST_RUN_BACKUP="${LINODE_TEST_RUN_BACKUP:-0}"
LINODE_TEST_INSTALL_BACKUP_TARGET="${LINODE_TEST_INSTALL_BACKUP_TARGET:-}"
LINODE_TEST_INSTALL_BACKUP_S3_ENDPOINT="${LINODE_TEST_INSTALL_BACKUP_S3_ENDPOINT:-}"
LINODE_TEST_INSTALL_BACKUP_S3_REGION="${LINODE_TEST_INSTALL_BACKUP_S3_REGION:-}"
LINODE_TEST_INSTALL_BACKUP_S3_BUCKET="${LINODE_TEST_INSTALL_BACKUP_S3_BUCKET:-}"
LINODE_TEST_INSTALL_BACKUP_S3_ACCESS_KEY_ID="${LINODE_TEST_INSTALL_BACKUP_S3_ACCESS_KEY_ID:-}"
LINODE_TEST_INSTALL_BACKUP_S3_SECRET_ACCESS_KEY="${LINODE_TEST_INSTALL_BACKUP_S3_SECRET_ACCESS_KEY:-}"
LINODE_TEST_INSTALL_BACKUP_S3_PREFIX="${LINODE_TEST_INSTALL_BACKUP_S3_PREFIX:-}"
LINODE_TEST_KEEP_SSH_KEY="${LINODE_TEST_KEEP_SSH_KEY:-0}"
LINODE_TEST_DOMAIN_PROVIDER="${LINODE_TEST_DOMAIN_PROVIDER:-sslip.io}"
LINODE_TEST_INSTALL_DOMAIN="${LINODE_TEST_INSTALL_DOMAIN:-}"
LINODE_TEST_INSTALL_ADMIN_EMAIL="${LINODE_TEST_INSTALL_ADMIN_EMAIL:-}"

LINODE_INSTANCE_ID=""
LINODE_INSTANCE_IP=""
LINODE_INSTANCE_REGION=""
SSH_KEY_FILE=""
SSH_KEY_DIR=""
TEST_LABEL=""
LINODE_ACCOUNT_EMAIL=""
LINODE_TEST_DOMAIN_AUTO="0"
LINODE_TEST_ADMIN_EMAIL_AUTO="0"

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

usage() {
	cat <<'EOF'
linode-test.sh

用法:
  bash linode-test.sh [--keep] [--region <id>] [--type <id>] [--image <id>]

说明:
  - 从 .env 读取 linode_token
  - 创建一台临时 Linode VPS
  - 推送当前目录安装器到远端
  - 执行一轮非交互安装和 smoke 测试
  - 默认测试完成后自动销毁实例

常用环境变量:
  LINODE_TEST_KEEP=1
  LINODE_TEST_REGION_CANDIDATES=us-lax,us-west,us-east
  LINODE_TEST_TYPE=g6-standard-1
  LINODE_TEST_IMAGE=linode/ubuntu24.04
  LINODE_TEST_INSTALL_DB_DRIVER=postgres
  LINODE_TEST_INSTALL_SESSION_DRIVER=redis
  LINODE_TEST_INSTALL_APP_IMAGE=ghcr.io/web-casa/emdash-app:starter-sqlite-file-local
  LINODE_TEST_INSTALL_APP_BASE_IMAGE=ghcr.io/web-casa/emdash-builder:node24-bookworm
  LINODE_TEST_INSTALL_S3_ENDPOINT=https://s3.example.com
  LINODE_TEST_INSTALL_S3_BUCKET=my-media-bucket
  LINODE_TEST_RUN_BACKUP=1
  LINODE_TEST_INSTALL_BACKUP_TARGET=s3
EOF
}

require_commands() {
	local missing=0
	local cmd
	for cmd in curl jq python3 ssh scp ssh-keygen tar timeout; do
		if ! command -v "${cmd}" >/dev/null 2>&1; then
			warn "缺少命令: ${cmd}"
			missing=1
		fi
	done
	[[ "${missing}" == "0" ]] || fail "请先安装缺失命令。"
}

load_token() {
	[[ -f "${ENV_FILE}" ]] || fail "未找到环境文件: ${ENV_FILE}"
	# shellcheck disable=SC1090
	set -a && source "${ENV_FILE}" && set +a
	[[ -n "${linode_token:-}" ]] || fail ".env 中缺少 linode_token"
	[[ -n "${LINODE_TEST_INSTALL_S3_PROVIDER}" ]] || LINODE_TEST_INSTALL_S3_PROVIDER="${S3_PROVIDER:-custom}"
	[[ -n "${LINODE_TEST_INSTALL_S3_ENDPOINT}" ]] || LINODE_TEST_INSTALL_S3_ENDPOINT="${S3_ENDPOINT:-}"
	[[ -n "${LINODE_TEST_INSTALL_S3_REGION}" ]] || LINODE_TEST_INSTALL_S3_REGION="${S3_REGION:-auto}"
	[[ -n "${LINODE_TEST_INSTALL_S3_BUCKET}" ]] || LINODE_TEST_INSTALL_S3_BUCKET="${S3_BUCKET:-}"
	[[ -n "${LINODE_TEST_INSTALL_S3_ACCESS_KEY_ID}" ]] || LINODE_TEST_INSTALL_S3_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID:-${AWS_ACCESS_KEY_ID:-}}"
	[[ -n "${LINODE_TEST_INSTALL_S3_SECRET_ACCESS_KEY}" ]] || LINODE_TEST_INSTALL_S3_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY:-${AWS_SECRET_ACCESS_KEY:-}}"
	[[ -n "${LINODE_TEST_INSTALL_S3_PUBLIC_URL}" ]] || LINODE_TEST_INSTALL_S3_PUBLIC_URL="${S3_PUBLIC_URL:-}"
	[[ -n "${LINODE_TEST_INSTALL_BACKUP_TARGET}" ]] || LINODE_TEST_INSTALL_BACKUP_TARGET="${BACKUP_TARGET_TYPE:-}"
	[[ -n "${LINODE_TEST_INSTALL_BACKUP_S3_ENDPOINT}" ]] || LINODE_TEST_INSTALL_BACKUP_S3_ENDPOINT="${BACKUP_S3_ENDPOINT:-${S3_ENDPOINT:-}}"
	[[ -n "${LINODE_TEST_INSTALL_BACKUP_S3_REGION}" ]] || LINODE_TEST_INSTALL_BACKUP_S3_REGION="${BACKUP_S3_REGION:-${S3_REGION:-auto}}"
	[[ -n "${LINODE_TEST_INSTALL_BACKUP_S3_BUCKET}" ]] || LINODE_TEST_INSTALL_BACKUP_S3_BUCKET="${BACKUP_S3_BUCKET:-${S3_BUCKET:-}}"
	[[ -n "${LINODE_TEST_INSTALL_BACKUP_S3_ACCESS_KEY_ID}" ]] || LINODE_TEST_INSTALL_BACKUP_S3_ACCESS_KEY_ID="${BACKUP_S3_ACCESS_KEY_ID:-${AWS_ACCESS_KEY_ID:-}}"
	[[ -n "${LINODE_TEST_INSTALL_BACKUP_S3_SECRET_ACCESS_KEY}" ]] || LINODE_TEST_INSTALL_BACKUP_S3_SECRET_ACCESS_KEY="${BACKUP_S3_SECRET_ACCESS_KEY:-${AWS_SECRET_ACCESS_KEY:-}}"
	[[ -n "${LINODE_TEST_INSTALL_BACKUP_S3_PREFIX}" ]] || LINODE_TEST_INSTALL_BACKUP_S3_PREFIX="${BACKUP_S3_PREFIX:-backups}"
}

api_call() {
	local method="$1"
	local endpoint="$2"
	local data="${3:-}"
	local tmp_body http_code curl_rc attempt max_attempts
	max_attempts=4
	attempt=1

	while (( attempt <= max_attempts )); do
		tmp_body="$(mktemp)"
		http_code=""
		curl_rc=0
		if [[ -n "${data}" ]]; then
			http_code="$(curl -sS -X "${method}" \
				-H "Authorization: Bearer ${linode_token}" \
				-H "Content-Type: application/json" \
				-o "${tmp_body}" \
				-w '%{http_code}' \
				"${LINODE_API_BASE}${endpoint}" \
				-d "${data}")" || curl_rc=$?
		else
			http_code="$(curl -sS -X "${method}" \
				-H "Authorization: Bearer ${linode_token}" \
				-o "${tmp_body}" \
				-w '%{http_code}' \
				"${LINODE_API_BASE}${endpoint}")" || curl_rc=$?
		fi

		if [[ "${curl_rc}" == "0" && "${http_code}" =~ ^2 ]]; then
			cat "${tmp_body}"
			rm -f "${tmp_body}"
			return 0
		fi

		if (( attempt == max_attempts )); then
			warn "Linode API ${method} ${endpoint} 失败，HTTP ${http_code:-000}"
			[[ -s "${tmp_body}" ]] && cat "${tmp_body}" >&2
			rm -f "${tmp_body}"
			return 1
		fi

		warn "Linode API ${method} ${endpoint} 第 ${attempt}/${max_attempts} 次失败，准备重试。"
		rm -f "${tmp_body}"
		sleep $(( attempt * 2 ))
		attempt=$(( attempt + 1 ))
	done
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--keep)
			LINODE_TEST_KEEP="1"
			;;
		--region)
			shift
			[[ $# -gt 0 ]] || fail "--region 需要参数"
			LINODE_TEST_REGION_CANDIDATES="$1"
			;;
		--type)
			shift
			[[ $# -gt 0 ]] || fail "--type 需要参数"
			LINODE_TEST_TYPE="$1"
			;;
		--image)
			shift
			[[ $# -gt 0 ]] || fail "--image 需要参数"
			LINODE_TEST_IMAGE="$1"
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

cleanup() {
	local exit_code="$?"
	if [[ -n "${SSH_KEY_FILE}" && "${LINODE_TEST_KEEP_SSH_KEY}" != "1" ]]; then
		rm -f "${SSH_KEY_FILE}" "${SSH_KEY_FILE}.pub"
		[[ -n "${SSH_KEY_DIR}" ]] && rm -rf "${SSH_KEY_DIR}"
	elif [[ -n "${SSH_KEY_FILE}" ]]; then
		warn "已保留 SSH key: ${SSH_KEY_FILE}"
	fi
	if [[ -n "${LINODE_INSTANCE_ID}" && "${LINODE_TEST_KEEP}" != "1" ]]; then
		destroy_current_instance
	elif [[ -n "${LINODE_INSTANCE_ID}" ]]; then
		warn "已保留实例 ${LINODE_INSTANCE_ID} (${LINODE_INSTANCE_IP})"
	fi
	exit "${exit_code}"
}

create_temp_key() {
	SSH_KEY_DIR="$(mktemp -d "${HOME}/.ssh/emdash-linode-test-XXXXXX.d")"
	SSH_KEY_FILE="${SSH_KEY_DIR}/id_ed25519"
	ssh-keygen -q -t ed25519 -N '' -f "${SSH_KEY_FILE}" >/dev/null
}

generate_root_password() {
	python3 - <<'PY'
import secrets
print("Aa1!" + secrets.token_urlsafe(18))
PY
}

generate_test_label() {
	python3 - "$LINODE_TEST_LABEL_PREFIX" <<'PY'
import secrets
import sys
from datetime import datetime, UTC

prefix = sys.argv[1]
stamp = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
suffix = secrets.token_hex(2)
print(f"{prefix}-{stamp}-{suffix}")
PY
}

pick_regions() {
	printf '%s\n' "${LINODE_TEST_REGION_CANDIDATES}" | tr ',' '\n' | sed '/^$/d'
}

destroy_current_instance() {
	[[ -n "${LINODE_INSTANCE_ID}" ]] || return 0
	log "销毁测试实例 ${LINODE_INSTANCE_ID}"
	api_call DELETE "/linode/instances/${LINODE_INSTANCE_ID}" >/dev/null || warn "实例销毁失败，请手工检查。"
	LINODE_INSTANCE_ID=""
	LINODE_INSTANCE_IP=""
	LINODE_INSTANCE_REGION=""
}

validate_profile() {
	local profile
	profile="$(api_call GET "/profile")"
	LINODE_ACCOUNT_EMAIL="$(printf '%s\n' "${profile}" | jq -r '.email // empty')"
	printf '%s\n' "${profile}" | jq '{username: .username, email: .email}'
}

build_test_domain() {
	local ip="$1"
	local provider="${2:-sslip.io}"

	case "${provider}" in
	sslip.io | nip.io)
		printf '%s.%s\n' "${ip}" "${provider}"
		;;
	*)
		fail "不支持的测试域名 provider: ${provider}"
		;;
	esac
}

prepare_test_domain_inputs() {
	if [[ "${LINODE_TEST_INSTALL_USE_CADDY}" != "1" ]]; then
		return
	fi

	if [[ -z "${LINODE_TEST_INSTALL_DOMAIN}" ]]; then
		LINODE_TEST_INSTALL_DOMAIN="$(build_test_domain "${LINODE_INSTANCE_IP}" "${LINODE_TEST_DOMAIN_PROVIDER}")"
	fi

	if [[ "${LINODE_TEST_INSTALL_ENABLE_HTTPS}" == "1" && -z "${LINODE_TEST_INSTALL_ADMIN_EMAIL}" ]]; then
		LINODE_TEST_INSTALL_ADMIN_EMAIL="${LINODE_ACCOUNT_EMAIL:-test@example.com}"
	fi

	log "Caddy 测试域名: ${LINODE_TEST_INSTALL_DOMAIN}"
	if [[ -n "${LINODE_TEST_INSTALL_ADMIN_EMAIL}" ]]; then
		log "Caddy 证书邮箱: ${LINODE_TEST_INSTALL_ADMIN_EMAIL}"
	fi
}

validate_image_and_type() {
	api_call GET "/images/${LINODE_TEST_IMAGE}" >/dev/null
	api_call GET "/linode/types/${LINODE_TEST_TYPE}" >/dev/null
}

create_instance() {
	local region="$1"
	local payload response pubkey
	pubkey="$(tr -d '\r\n' <"${SSH_KEY_FILE}.pub")"
	log "尝试在 ${region} 创建 ${LINODE_TEST_TYPE} / ${LINODE_TEST_IMAGE}"
	payload="$(jq -n \
		--arg label "${TEST_LABEL}" \
		--arg region "${region}" \
		--arg type "${LINODE_TEST_TYPE}" \
		--arg image "${LINODE_TEST_IMAGE}" \
		--arg root_pass "$(generate_root_password)" \
		--arg pubkey "${pubkey}" \
		'{
			label: $label,
			region: $region,
			type: $type,
			image: $image,
			root_pass: $root_pass,
			booted: true,
			backups_enabled: false,
			tags: ["emdash", "installer-test"],
			authorized_keys: [$pubkey]
		}')"
	if response="$(api_call POST "/linode/instances" "${payload}")"; then
		LINODE_INSTANCE_ID="$(printf '%s\n' "${response}" | jq -r '.id')"
		LINODE_INSTANCE_IP="$(printf '%s\n' "${response}" | jq -r '.ipv4[0] // empty')"
		LINODE_INSTANCE_REGION="${region}"
		printf '%s\n' "${response}" | jq '{id, label, region, type, status, ipv4}'
		return 0
	fi
	return 1
}

wait_for_instance_running() {
	local start now response status ip
	start="$(date +%s)"
	while true; do
		response="$(api_call GET "/linode/instances/${LINODE_INSTANCE_ID}")"
		status="$(printf '%s\n' "${response}" | jq -r '.status')"
		ip="$(printf '%s\n' "${response}" | jq -r '.ipv4[0] // empty')"
		if [[ "${status}" == "running" && -n "${ip}" ]]; then
			LINODE_INSTANCE_IP="${ip}"
			log "实例已运行: ${LINODE_INSTANCE_IP}"
			return 0
		fi
		now="$(date +%s)"
		if (( now - start > LINODE_TEST_CREATE_TIMEOUT )); then
			warn "等待实例启动超时。"
			return 1
		fi
		sleep 10
	done
}

wait_for_ssh() {
	local start now
	start="$(date +%s)"
	while true; do
		if ssh -i "${SSH_KEY_FILE}" \
			-o StrictHostKeyChecking=accept-new \
			-o ConnectTimeout=5 \
			"${LINODE_TEST_SSH_USER}@${LINODE_INSTANCE_IP}" \
			'echo ok' >/dev/null 2>&1; then
			log "SSH 已就绪"
			return 0
		fi
		now="$(date +%s)"
		if (( now - start > LINODE_TEST_SSH_TIMEOUT )); then
			warn "等待 SSH 就绪超时。"
			return 1
		fi
		sleep 5
	done
}

push_workspace() {
	log "推送当前安装器到远端 ${LINODE_INSTANCE_IP}"
	ssh -i "${SSH_KEY_FILE}" -o StrictHostKeyChecking=accept-new "${LINODE_TEST_SSH_USER}@${LINODE_INSTANCE_IP}" "bash -lc '
set -e
if ! command -v tar >/dev/null 2>&1; then
	if command -v dnf >/dev/null 2>&1; then
		dnf -y install tar >/dev/null
	elif command -v yum >/dev/null 2>&1; then
		yum -y install tar >/dev/null
	elif command -v apt-get >/dev/null 2>&1; then
		apt-get update -y >/dev/null
		DEBIAN_FRONTEND=noninteractive apt-get install -y tar >/dev/null
	else
		echo \"无法安装 tar\" >&2
		exit 1
	fi
fi
rm -rf \"${LINODE_TEST_REMOTE_DIR}\"
mkdir -p \"${LINODE_TEST_REMOTE_DIR}\"
'"
	tar -C "${SCRIPT_DIR}" \
		--exclude='.env' \
		--exclude='linode-test-result.json' \
		-czf - . | ssh -i "${SSH_KEY_FILE}" -o StrictHostKeyChecking=accept-new "${LINODE_TEST_SSH_USER}@${LINODE_INSTANCE_IP}" "tar -xzf - -C '${LINODE_TEST_REMOTE_DIR}'"
}

collect_remote_failure_context() {
	log "收集远端失败诊断信息"
	ssh -i "${SSH_KEY_FILE}" -o StrictHostKeyChecking=accept-new "${LINODE_TEST_SSH_USER}@${LINODE_INSTANCE_IP}" "bash -lc '
set +e
if [[ -f /etc/emdash/compose.env ]]; then
	set -a
	. /etc/emdash/compose.env
	set +a
fi
run_compose() {
	if command -v docker >/dev/null 2>&1; then
		docker compose -f /data/emdash/compose/compose.yml \"\$@\"
	elif [[ -n \"\${PODMAN_COMPOSE_PROVIDER_BIN:-}\" && -x \"\${PODMAN_COMPOSE_PROVIDER_BIN}\" ]]; then
		env -u PODMAN_COMPOSE_PROVIDER_BIN \"\${PODMAN_COMPOSE_PROVIDER_BIN}\" -f /data/emdash/compose/compose.yml \"\$@\"
	elif command -v podman-compose >/dev/null 2>&1; then
		podman-compose -f /data/emdash/compose/compose.yml \"\$@\"
	elif command -v podman >/dev/null 2>&1; then
		podman compose -f /data/emdash/compose/compose.yml \"\$@\"
	else
		echo \"compose runtime not found\"
		return 127
	fi
}
echo \"===== docker compose ps =====\"
run_compose ps
echo
echo \"===== docker compose logs app =====\"
run_compose logs --tail 200 app
echo
echo \"===== emdashctl doctor --json =====\"
/usr/local/bin/emdashctl doctor --json
echo
echo \"===== journalctl -u caddy =====\"
journalctl -u caddy -n 200 --no-pager
'" >"${LINODE_TEST_FAILURE_LOG}" 2>&1 || true
	warn "远端失败日志已保存到 ${LINODE_TEST_FAILURE_LOG}"
}

run_remote_test() {
	local remote_cmd
	read -r -d '' remote_cmd <<'EOF' || true
set -Eeuo pipefail
cd "$1"
chmod +x install-emdash.sh emdashctl
export EMDASH_INSTALL_TEMPLATE=starter
export EMDASH_INSTALL_ROOT_DIR=/data/emdash
export EMDASH_INSTALL_DB_DRIVER="$2"
export EMDASH_INSTALL_SESSION_DRIVER="$3"
export EMDASH_INSTALL_STORAGE_DRIVER="$4"
export EMDASH_INSTALL_USE_CADDY="$5"
export EMDASH_INSTALL_ENABLE_HTTPS="$6"
if [[ -n "${12}" ]]; then
	export EMDASH_INSTALL_APP_IMAGE="${12}"
fi
if [[ -n "${13}" ]]; then
	export EMDASH_INSTALL_APP_BASE_IMAGE="${13}"
fi
if [[ -n "${10}" ]]; then
	export EMDASH_INSTALL_DOMAIN="${10}"
fi
if [[ -n "${11}" ]]; then
	export EMDASH_INSTALL_ADMIN_EMAIL="${11}"
fi
if [[ -n "$7" ]]; then
	export EMDASH_INSTALL_PG_PASSWORD="$7"
fi
if [[ -n "$8" ]]; then
	export EMDASH_INSTALL_REDIS_PASSWORD="$8"
fi
if [[ -n "${14}" ]]; then
	export EMDASH_INSTALL_BACKUP_TARGET="${14}"
fi
if [[ -n "${15}" ]]; then
	export EMDASH_INSTALL_BACKUP_S3_ENDPOINT="${15}"
fi
if [[ -n "${16}" ]]; then
	export EMDASH_INSTALL_BACKUP_S3_REGION="${16}"
fi
if [[ -n "${17}" ]]; then
	export EMDASH_INSTALL_BACKUP_S3_BUCKET="${17}"
fi
if [[ -n "${18}" ]]; then
	export EMDASH_INSTALL_BACKUP_S3_ACCESS_KEY_ID="${18}"
fi
if [[ -n "${19}" ]]; then
	export EMDASH_INSTALL_BACKUP_S3_SECRET_ACCESS_KEY="${19}"
fi
if [[ -n "${20}" ]]; then
	export EMDASH_INSTALL_BACKUP_S3_PREFIX="${20}"
fi
if [[ -n "${21}" ]]; then
	export EMDASH_INSTALL_S3_PROVIDER="${21}"
fi
if [[ -n "${22}" ]]; then
	export EMDASH_INSTALL_S3_ENDPOINT="${22}"
fi
if [[ -n "${23}" ]]; then
	export EMDASH_INSTALL_S3_REGION="${23}"
fi
if [[ -n "${24}" ]]; then
	export EMDASH_INSTALL_S3_BUCKET="${24}"
fi
if [[ -n "${25}" ]]; then
	export EMDASH_INSTALL_S3_ACCESS_KEY_ID="${25}"
fi
if [[ -n "${26}" ]]; then
	export EMDASH_INSTALL_S3_SECRET_ACCESS_KEY="${26}"
fi
if [[ -n "${27}" ]]; then
	export EMDASH_INSTALL_S3_PUBLIC_URL="${27}"
fi
bash install-emdash.sh --non-interactive --activate
/usr/local/bin/emdashctl status --json
/usr/local/bin/emdashctl doctor --json
/usr/local/bin/emdashctl smoke --json
if [[ "$9" == "1" ]]; then
	/usr/local/bin/emdashctl backup
	if [[ "${14}" == "s3" ]]; then
		latest_backup="$(ls -1 /data/emdash/backups/emdash-backup-*.tar.gz | tail -n1)"
		backup_key="${20%/}/$(basename "${latest_backup}")"
		if [[ -f /etc/emdash/compose.env ]]; then
			set -a
			. /etc/emdash/compose.env
			set +a
		fi
		runtime="${CONTAINER_RUNTIME:-docker}"
		if [[ "${runtime}" == "docker" ]]; then
			docker run --rm \
				-e AWS_ACCESS_KEY_ID="${18}" \
				-e AWS_SECRET_ACCESS_KEY="${19}" \
				amazon/aws-cli:2.22.21 \
				s3api head-object \
				--bucket "${17}" \
				--key "${backup_key}" \
				--endpoint-url "${15}" \
				--region "${16}"
		else
			podman run --rm \
				-e AWS_ACCESS_KEY_ID="${18}" \
				-e AWS_SECRET_ACCESS_KEY="${19}" \
				amazon/aws-cli:2.22.21 \
				s3api head-object \
				--bucket "${17}" \
				--key "${backup_key}" \
				--endpoint-url "${15}" \
				--region "${16}"
		fi
	fi
fi
EOF
	log "执行远端安装和 smoke 测试"
	if ! ssh -tt -i "${SSH_KEY_FILE}" -o StrictHostKeyChecking=accept-new "${LINODE_TEST_SSH_USER}@${LINODE_INSTANCE_IP}" "bash -lc $(printf '%q ' "${remote_cmd}") bash $(printf '%q' "${LINODE_TEST_REMOTE_DIR}") $(printf '%q' "${LINODE_TEST_INSTALL_DB_DRIVER}") $(printf '%q' "${LINODE_TEST_INSTALL_SESSION_DRIVER}") $(printf '%q' "${LINODE_TEST_INSTALL_STORAGE_DRIVER}") $(printf '%q' "${LINODE_TEST_INSTALL_USE_CADDY}") $(printf '%q' "${LINODE_TEST_INSTALL_ENABLE_HTTPS}") $(printf '%q' "${LINODE_TEST_INSTALL_PG_PASSWORD}") $(printf '%q' "${LINODE_TEST_INSTALL_REDIS_PASSWORD}") $(printf '%q' "${LINODE_TEST_RUN_BACKUP}") $(printf '%q' "${LINODE_TEST_INSTALL_DOMAIN}") $(printf '%q' "${LINODE_TEST_INSTALL_ADMIN_EMAIL}") $(printf '%q' "${LINODE_TEST_INSTALL_APP_IMAGE}") $(printf '%q' "${LINODE_TEST_INSTALL_APP_BASE_IMAGE}") $(printf '%q' "${LINODE_TEST_INSTALL_BACKUP_TARGET}") $(printf '%q' "${LINODE_TEST_INSTALL_BACKUP_S3_ENDPOINT}") $(printf '%q' "${LINODE_TEST_INSTALL_BACKUP_S3_REGION}") $(printf '%q' "${LINODE_TEST_INSTALL_BACKUP_S3_BUCKET}") $(printf '%q' "${LINODE_TEST_INSTALL_BACKUP_S3_ACCESS_KEY_ID}") $(printf '%q' "${LINODE_TEST_INSTALL_BACKUP_S3_SECRET_ACCESS_KEY}") $(printf '%q' "${LINODE_TEST_INSTALL_BACKUP_S3_PREFIX}") $(printf '%q' "${LINODE_TEST_INSTALL_S3_PROVIDER}") $(printf '%q' "${LINODE_TEST_INSTALL_S3_ENDPOINT}") $(printf '%q' "${LINODE_TEST_INSTALL_S3_REGION}") $(printf '%q' "${LINODE_TEST_INSTALL_S3_BUCKET}") $(printf '%q' "${LINODE_TEST_INSTALL_S3_ACCESS_KEY_ID}") $(printf '%q' "${LINODE_TEST_INSTALL_S3_SECRET_ACCESS_KEY}") $(printf '%q' "${LINODE_TEST_INSTALL_S3_PUBLIC_URL}")"; then
		collect_remote_failure_context
		return 1
	fi
}

write_result_file() {
	jq -n \
		--arg id "${LINODE_INSTANCE_ID}" \
		--arg ip "${LINODE_INSTANCE_IP}" \
		--arg region "${LINODE_INSTANCE_REGION}" \
		--arg label "${TEST_LABEL}" \
		--arg image "${LINODE_TEST_IMAGE}" \
		--arg type "${LINODE_TEST_TYPE}" \
		--arg regions "${LINODE_TEST_REGION_CANDIDATES}" \
		--arg domain "${LINODE_TEST_INSTALL_DOMAIN}" \
		--arg keep "${LINODE_TEST_KEEP}" \
		--arg keep_ssh_key "${LINODE_TEST_KEEP_SSH_KEY}" \
		--arg ssh_key_file "${SSH_KEY_FILE}" \
		'{
			instance_id: $id,
			ipv4: $ip,
			region: $region,
			label: $label,
			image: $image,
			type: $type,
			region_candidates: $regions,
			domain: $domain,
			keep: ($keep == "1"),
			keep_ssh_key: ($keep_ssh_key == "1"),
			ssh_key_file: (if $keep_ssh_key == "1" then $ssh_key_file else "" end)
		}' >"${LINODE_TEST_RESULT_FILE}"
	log "已写入结果文件: ${LINODE_TEST_RESULT_FILE}"
}

main() {
	local region attempt_success=0
	parse_args "$@"
	require_commands
	load_token
	trap cleanup EXIT
	rm -f "${LINODE_TEST_RESULT_FILE}"

	log "验证 Linode token"
	validate_profile
	validate_image_and_type
	create_temp_key
	TEST_LABEL="$(generate_test_label)"
	[[ -z "${LINODE_TEST_INSTALL_DOMAIN}" ]] && LINODE_TEST_DOMAIN_AUTO="1"
	[[ -z "${LINODE_TEST_INSTALL_ADMIN_EMAIL}" ]] && LINODE_TEST_ADMIN_EMAIL_AUTO="1"

	for region in $(pick_regions); do
		if ! create_instance "${region}"; then
			warn "区域 ${region} 创建失败，尝试下一个区域。"
			continue
		fi
		if ! wait_for_instance_running; then
			warn "区域 ${region} 实例启动失败，尝试下一个区域。"
			destroy_current_instance
			continue
		fi
		if [[ "${LINODE_TEST_DOMAIN_AUTO}" == "1" ]]; then
			LINODE_TEST_INSTALL_DOMAIN=""
		fi
		if [[ "${LINODE_TEST_ADMIN_EMAIL_AUTO}" == "1" ]]; then
			LINODE_TEST_INSTALL_ADMIN_EMAIL=""
		fi
		prepare_test_domain_inputs
		if ! wait_for_ssh; then
			warn "区域 ${region} SSH 未就绪，尝试下一个区域。"
			destroy_current_instance
			continue
		fi
		push_workspace
		run_remote_test
		write_result_file
		log "Linode 临时测试完成"
		attempt_success=1
		break
	done

	[[ "${attempt_success}" == "1" ]] || fail "所有候选区域都未能完成测试。"
}

main "$@"
