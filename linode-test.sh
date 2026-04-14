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
LINODE_TEST_CREATE_TIMEOUT="${LINODE_TEST_CREATE_TIMEOUT:-300}"
LINODE_TEST_SSH_TIMEOUT="${LINODE_TEST_SSH_TIMEOUT:-180}"
LINODE_TEST_SSH_COMMAND_RETRIES="${LINODE_TEST_SSH_COMMAND_RETRIES:-4}"
LINODE_TEST_REMOTE_DIR="${LINODE_TEST_REMOTE_DIR:-/root/emdash-1key}"
LINODE_TEST_RESULT_FILE="${LINODE_TEST_RESULT_FILE:-${SCRIPT_DIR}/linode-test-result.json}"
LINODE_TEST_FAILURE_LOG="${LINODE_TEST_FAILURE_LOG:-${SCRIPT_DIR}/linode-test-failure.log}"
LINODE_TEST_INSTALL_TEMPLATE="${LINODE_TEST_INSTALL_TEMPLATE:-starter}"
LINODE_TEST_INSTALL_DB_DRIVER="${LINODE_TEST_INSTALL_DB_DRIVER:-sqlite}"
LINODE_TEST_INSTALL_SESSION_DRIVER="${LINODE_TEST_INSTALL_SESSION_DRIVER:-file}"
LINODE_TEST_INSTALL_STORAGE_DRIVER="${LINODE_TEST_INSTALL_STORAGE_DRIVER:-local}"
LINODE_TEST_INSTALL_USE_CADDY="${LINODE_TEST_INSTALL_USE_CADDY:-0}"
LINODE_TEST_INSTALL_ENABLE_HTTPS="${LINODE_TEST_INSTALL_ENABLE_HTTPS:-0}"
LINODE_TEST_INSTALL_PG_PASSWORD="${LINODE_TEST_INSTALL_PG_PASSWORD:-}"
LINODE_TEST_INSTALL_REDIS_PASSWORD="${LINODE_TEST_INSTALL_REDIS_PASSWORD:-}"
LINODE_TEST_INSTALL_S3_PROVIDER="${LINODE_TEST_INSTALL_S3_PROVIDER:-}"
LINODE_TEST_INSTALL_S3_ENDPOINT="${LINODE_TEST_INSTALL_S3_ENDPOINT:-}"
LINODE_TEST_INSTALL_S3_REGION="${LINODE_TEST_INSTALL_S3_REGION:-}"
LINODE_TEST_INSTALL_S3_BUCKET="${LINODE_TEST_INSTALL_S3_BUCKET:-}"
LINODE_TEST_INSTALL_S3_ACCESS_KEY_ID="${LINODE_TEST_INSTALL_S3_ACCESS_KEY_ID:-}"
LINODE_TEST_INSTALL_S3_SECRET_ACCESS_KEY="${LINODE_TEST_INSTALL_S3_SECRET_ACCESS_KEY:-}"
LINODE_TEST_INSTALL_S3_PUBLIC_URL="${LINODE_TEST_INSTALL_S3_PUBLIC_URL:-}"
LINODE_TEST_CHECK_PUBLIC_ROUTES="${LINODE_TEST_CHECK_PUBLIC_ROUTES:-1}"
LINODE_TEST_REPEAT_INSTALL="${LINODE_TEST_REPEAT_INSTALL:-0}"
LINODE_TEST_KEEP_ON_FAILURE="${LINODE_TEST_KEEP_ON_FAILURE:-1}"
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
SSH_KNOWN_HOSTS_FILE=""
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
  - 执行一轮非交互 native 安装和 smoke 测试
  - 额外检查首页、后台入口、healthz 和 setup API，避免只测健康接口
  - 可选重复安装，覆盖 git pull/pnpm install/pnpm build 回归路径
  - 默认测试完成后自动销毁实例

常用环境变量:
  LINODE_TEST_KEEP=1
  LINODE_TEST_REGION_CANDIDATES=us-lax,us-west,us-east
  LINODE_TEST_TYPE=g6-standard-1
  LINODE_TEST_IMAGE=linode/ubuntu24.04
  LINODE_TEST_INSTALL_TEMPLATE=blog
  LINODE_TEST_INSTALL_DB_DRIVER=postgres
  LINODE_TEST_INSTALL_SESSION_DRIVER=redis
  LINODE_TEST_INSTALL_USE_CADDY=1
  LINODE_TEST_INSTALL_ENABLE_HTTPS=1
  LINODE_TEST_REPEAT_INSTALL=1
  LINODE_TEST_KEEP_ON_FAILURE=1
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
	SSH_KNOWN_HOSTS_FILE="${SSH_KEY_DIR}/known_hosts"
	: >"${SSH_KNOWN_HOSTS_FILE}"
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
			-o UserKnownHostsFile="${SSH_KNOWN_HOSTS_FILE}" \
			-o GlobalKnownHostsFile=/dev/null \
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

ssh_with_retries() {
	local description="$1"
	local command="$2"
	local attempt=1
	while (( attempt <= LINODE_TEST_SSH_COMMAND_RETRIES )); do
		if ssh -i "${SSH_KEY_FILE}" \
			-o StrictHostKeyChecking=accept-new \
			-o UserKnownHostsFile="${SSH_KNOWN_HOSTS_FILE}" \
			-o GlobalKnownHostsFile=/dev/null \
			-o ConnectTimeout=10 \
			"${LINODE_TEST_SSH_USER}@${LINODE_INSTANCE_IP}" "${command}"; then
			return 0
		fi
		warn "${description} 失败 (${attempt}/${LINODE_TEST_SSH_COMMAND_RETRIES})，准备重试。"
		sleep $(( attempt * 5 ))
		attempt=$(( attempt + 1 ))
	done
	return 1
}

scp_with_retries() {
	local source="$1"
	local target="$2"
	local attempt=1
	while (( attempt <= LINODE_TEST_SSH_COMMAND_RETRIES )); do
		if scp -i "${SSH_KEY_FILE}" \
			-o StrictHostKeyChecking=accept-new \
			-o UserKnownHostsFile="${SSH_KNOWN_HOSTS_FILE}" \
			-o GlobalKnownHostsFile=/dev/null \
			-o ConnectTimeout=10 \
			"${source}" "${LINODE_TEST_SSH_USER}@${LINODE_INSTANCE_IP}:${target}"; then
			return 0
		fi
		warn "SCP 上传失败 (${attempt}/${LINODE_TEST_SSH_COMMAND_RETRIES})，准备重试。"
		sleep $(( attempt * 5 ))
		attempt=$(( attempt + 1 ))
	done
	return 1
}

push_workspace() {
	local bundle_file remote_bundle
	bundle_file="$(mktemp "${TMPDIR:-/tmp}/emdash-linode-workspace-XXXXXX.tar.gz")"
	remote_bundle="${LINODE_TEST_REMOTE_DIR}/workspace.tar.gz"
	log "推送当前安装器到远端 ${LINODE_INSTANCE_IP}"
	if ! ssh_with_retries "远端目录准备" "bash -lc '
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
'"; then
		rm -f "${bundle_file}"
		return 1
	fi
	tar -C "${SCRIPT_DIR}" \
		--exclude='.env' \
		--exclude='.git' \
		--exclude='test-results' \
		--exclude='node_modules' \
		--exclude='docker' \
		--exclude='*.db' \
		--exclude='linode-test-result.json' \
		--exclude='linode-test-failure.log' \
		-czf "${bundle_file}" .
	if ! scp_with_retries "${bundle_file}" "${remote_bundle}"; then
		rm -f "${bundle_file}"
		return 1
	fi
	if ! ssh_with_retries "远端工作区解包" "tar -xzf '${remote_bundle}' -C '${LINODE_TEST_REMOTE_DIR}' && rm -f '${remote_bundle}'"; then
		rm -f "${bundle_file}"
		return 1
	fi
	rm -f "${bundle_file}"
}

collect_remote_failure_context() {
	log "收集远端失败诊断信息"
	ssh -i "${SSH_KEY_FILE}" \
		-o StrictHostKeyChecking=accept-new \
		-o UserKnownHostsFile="${SSH_KNOWN_HOSTS_FILE}" \
		-o GlobalKnownHostsFile=/dev/null \
		"${LINODE_TEST_SSH_USER}@${LINODE_INSTANCE_IP}" "bash -lc '
set +e
if [[ -f /etc/emdash/emdash.env ]]; then
	set -a
	. /etc/emdash/emdash.env
	set +a
fi
echo \"===== os-release =====\"
cat /etc/os-release
echo
echo \"===== versions =====\"
node --version
corepack --version
pnpm --version
python3 --version
echo
echo \"===== emdashctl doctor --json =====\"
/usr/local/bin/emdashctl doctor --json
echo
echo \"===== emdashctl status --json =====\"
/usr/local/bin/emdashctl status --json
echo
echo \"===== installed postgres/valkey packages =====\"
rpm -q --qf '\''%{NAME} %{VERSION}-%{RELEASE} %{VENDOR}\n'\'' postgresql*-server valkey 2>/dev/null || true
dpkg -l postgresql-* valkey 2>/dev/null | grep '\''^ii'\'' || true
echo
echo \"===== systemctl status =====\"
for unit in emdash-app caddy valkey redis redis-server postgresql postgresql-18 postgresql@18-main; do
	systemctl status \"\${unit}\" --no-pager 2>/dev/null
	echo
done
echo \"===== local routes =====\"
for path in /healthz / /_emdash/admin /_emdash/api/setup/status; do
	echo \"--- http://127.0.0.1:\${APP_PORT:-3000}\${path}\"
	curl -k -i --max-time 20 \"http://127.0.0.1:\${APP_PORT:-3000}\${path}\"
	echo
done
if [[ -n \"\${APP_PUBLIC_URL:-}\" ]]; then
	echo \"===== public routes =====\"
	for path in /healthz / /_emdash/admin /_emdash/api/setup/status; do
		echo \"--- \${APP_PUBLIC_URL}\${path}\"
		curl -k -i --max-time 30 \"\${APP_PUBLIC_URL}\${path}\"
		echo
	done
fi
echo \"===== dist server chunks =====\"
find /data/emdash/app/site/dist/server -maxdepth 2 -type f 2>/dev/null | sort | tail -n 200
echo
echo \"===== journalctl -u emdash-app =====\"
journalctl -u emdash-app -n 300 --no-pager
echo
echo \"===== journalctl -u caddy =====\"
journalctl -u caddy -n 200 --no-pager
echo
echo \"===== journalctl database/session units =====\"
for unit in redis redis-server valkey postgresql postgresql-18 postgresql@18-main; do
	echo \"--- \${unit}\"
	journalctl -u \"\${unit}\" -n 120 --no-pager
	echo
done
'" >"${LINODE_TEST_FAILURE_LOG}" 2>&1 || true
	warn "远端失败日志已保存到 ${LINODE_TEST_FAILURE_LOG}"
}

shell_quote() {
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

emit_env_line() {
	local key="$1" val="$2"
	printf '%s=%s\n' "${key}" "$(shell_quote "${val}")"
}

emit_env_line_if_set() {
	local key="$1" val="$2"
	[[ -n "${val}" ]] && emit_env_line "${key}" "${val}"
}

build_remote_env_file() {
	local env_file="$1"
	{
		emit_env_line EMDASH_INSTALL_TEMPLATE "${LINODE_TEST_INSTALL_TEMPLATE}"
		emit_env_line EMDASH_INSTALL_ROOT_DIR /data/emdash
		emit_env_line EMDASH_INSTALL_DB_DRIVER "${LINODE_TEST_INSTALL_DB_DRIVER}"
		emit_env_line EMDASH_INSTALL_SESSION_DRIVER "${LINODE_TEST_INSTALL_SESSION_DRIVER}"
		emit_env_line EMDASH_INSTALL_STORAGE_DRIVER "${LINODE_TEST_INSTALL_STORAGE_DRIVER}"
		emit_env_line EMDASH_INSTALL_USE_CADDY "${LINODE_TEST_INSTALL_USE_CADDY}"
		emit_env_line EMDASH_INSTALL_ENABLE_HTTPS "${LINODE_TEST_INSTALL_ENABLE_HTTPS}"
		emit_env_line_if_set EMDASH_INSTALL_DOMAIN "${LINODE_TEST_INSTALL_DOMAIN}"
		emit_env_line_if_set EMDASH_INSTALL_ADMIN_EMAIL "${LINODE_TEST_INSTALL_ADMIN_EMAIL}"
		emit_env_line_if_set EMDASH_INSTALL_PG_PASSWORD "${LINODE_TEST_INSTALL_PG_PASSWORD}"
		emit_env_line_if_set EMDASH_INSTALL_REDIS_PASSWORD "${LINODE_TEST_INSTALL_REDIS_PASSWORD}"
		emit_env_line_if_set EMDASH_INSTALL_S3_PROVIDER "${LINODE_TEST_INSTALL_S3_PROVIDER}"
		emit_env_line_if_set EMDASH_INSTALL_S3_ENDPOINT "${LINODE_TEST_INSTALL_S3_ENDPOINT}"
		emit_env_line_if_set EMDASH_INSTALL_S3_REGION "${LINODE_TEST_INSTALL_S3_REGION}"
		emit_env_line_if_set EMDASH_INSTALL_S3_BUCKET "${LINODE_TEST_INSTALL_S3_BUCKET}"
		emit_env_line_if_set EMDASH_INSTALL_S3_ACCESS_KEY_ID "${LINODE_TEST_INSTALL_S3_ACCESS_KEY_ID}"
		emit_env_line_if_set EMDASH_INSTALL_S3_SECRET_ACCESS_KEY "${LINODE_TEST_INSTALL_S3_SECRET_ACCESS_KEY}"
		emit_env_line_if_set EMDASH_INSTALL_S3_PUBLIC_URL "${LINODE_TEST_INSTALL_S3_PUBLIC_URL}"
		emit_env_line_if_set EMDASH_INSTALL_BACKUP_TARGET "${LINODE_TEST_INSTALL_BACKUP_TARGET}"
		emit_env_line_if_set EMDASH_INSTALL_BACKUP_S3_ENDPOINT "${LINODE_TEST_INSTALL_BACKUP_S3_ENDPOINT}"
		emit_env_line_if_set EMDASH_INSTALL_BACKUP_S3_REGION "${LINODE_TEST_INSTALL_BACKUP_S3_REGION}"
		emit_env_line_if_set EMDASH_INSTALL_BACKUP_S3_BUCKET "${LINODE_TEST_INSTALL_BACKUP_S3_BUCKET}"
		emit_env_line_if_set EMDASH_INSTALL_BACKUP_S3_ACCESS_KEY_ID "${LINODE_TEST_INSTALL_BACKUP_S3_ACCESS_KEY_ID}"
		emit_env_line_if_set EMDASH_INSTALL_BACKUP_S3_SECRET_ACCESS_KEY "${LINODE_TEST_INSTALL_BACKUP_S3_SECRET_ACCESS_KEY}"
		emit_env_line_if_set EMDASH_INSTALL_BACKUP_S3_PREFIX "${LINODE_TEST_INSTALL_BACKUP_S3_PREFIX}"
		emit_env_line LINODE_TEST_CHECK_PUBLIC_ROUTES "${LINODE_TEST_CHECK_PUBLIC_ROUTES}"
		emit_env_line LINODE_TEST_REPEAT_INSTALL "${LINODE_TEST_REPEAT_INSTALL}"
		emit_env_line LINODE_TEST_RUN_BACKUP "${LINODE_TEST_RUN_BACKUP}"
	} >"${env_file}"
}

run_remote_test() {
	local local_env_file remote_env_file
	local_env_file="$(mktemp)"
	remote_env_file="${LINODE_TEST_REMOTE_DIR}/test.env"

	build_remote_env_file "${local_env_file}"
	if ! scp_with_retries "${local_env_file}" "${remote_env_file}"; then
		rm -f "${local_env_file}"
		return 1
	fi
	rm -f "${local_env_file}"

	log "执行远端安装和 smoke 测试"
	if ! ssh -tt -i "${SSH_KEY_FILE}" \
		-o StrictHostKeyChecking=accept-new \
		-o UserKnownHostsFile="${SSH_KNOWN_HOSTS_FILE}" \
		-o GlobalKnownHostsFile=/dev/null \
		"${LINODE_TEST_SSH_USER}@${LINODE_INSTANCE_IP}" "bash -lc $(printf '%q' "
set -Eeuo pipefail
cd '${LINODE_TEST_REMOTE_DIR}'
set -a && source test.env && set +a
chmod +x install-emdash.sh emdashctl

run_checks() {
	/usr/local/bin/emdashctl status --json
	/usr/local/bin/emdashctl doctor --json
	/usr/local/bin/emdashctl smoke --json
	set -a
	. /etc/emdash/emdash.env
	set +a
	check_url() {
		local method=\"\$1\"
		local url=\"\$2\"
		local body_file=\"\"
		local status
		if [[ \"\${method}\" == \"HEAD\" ]]; then
			status=\"\$(curl -k -sS -I --max-time 30 -o /dev/null -w '%{http_code}' \"\${url}\")\"
		else
			body_file=\"\$(mktemp)\"
			status=\"\$(curl -k -sS --max-time 30 -o \"\${body_file}\" -w '%{http_code}' \"\${url}\")\"
		fi
		case \"\${status}\" in
		2* | 3*) printf 'route ok: %s %s -> %s\n' \"\${method}\" \"\${url}\" \"\${status}\" ;;
		*) printf 'route failed: %s %s -> %s\n' \"\${method}\" \"\${url}\" \"\${status}\" >&2; [[ -n \"\${body_file}\" ]] && rm -f \"\${body_file}\"; return 1 ;;
		esac
		if [[ -n \"\${body_file}\" ]]; then
			if grep -q 'Internal server error' \"\${body_file}\"; then
				printf 'route body contains internal server error: %s %s\n' \"\${method}\" \"\${url}\" >&2
				rm -f \"\${body_file}\"
				return 1
			fi
			rm -f \"\${body_file}\"
		fi
	}
	check_url GET \"http://127.0.0.1:\${APP_PORT:-3000}/healthz\"
	check_url GET \"http://127.0.0.1:\${APP_PORT:-3000}/\"
	check_url HEAD \"http://127.0.0.1:\${APP_PORT:-3000}/_emdash/admin\"
	check_url GET \"http://127.0.0.1:\${APP_PORT:-3000}/_emdash/admin/setup\"
	check_url GET \"http://127.0.0.1:\${APP_PORT:-3000}/_emdash/api/setup/status\"
	if [[ \"\${LINODE_TEST_CHECK_PUBLIC_ROUTES}\" == \"1\" && -n \"\${APP_PUBLIC_URL:-}\" ]]; then
		check_url GET \"\${APP_PUBLIC_URL}/healthz\"
		check_url GET \"\${APP_PUBLIC_URL}/\"
		check_url HEAD \"\${APP_PUBLIC_URL}/_emdash/admin\"
		check_url GET \"\${APP_PUBLIC_URL}/_emdash/admin/setup\"
		check_url GET \"\${APP_PUBLIC_URL}/_emdash/api/setup/status\"
	fi
}

bash install-emdash.sh --non-interactive --activate
run_checks

/usr/local/bin/emdashctl upgrade app
run_checks

if [[ \"\${LINODE_TEST_REPEAT_INSTALL}\" == \"1\" ]]; then
	bash install-emdash.sh --non-interactive --activate
	run_checks
fi

if [[ \"\${LINODE_TEST_RUN_BACKUP}\" == \"1\" ]]; then
	/usr/local/bin/emdashctl backup
	if [[ \"\${EMDASH_INSTALL_BACKUP_TARGET:-}\" == \"s3\" ]]; then
		latest_backup=\"\$(ls -1t /data/emdash/backups/emdash-backup-*.tar.gz | head -n1)\"
		backup_key=\"\${EMDASH_INSTALL_BACKUP_S3_PREFIX%/}/\$(basename \"\${latest_backup}\")\"
		python3 - \"\${EMDASH_INSTALL_BACKUP_S3_ENDPOINT}\" \"\${EMDASH_INSTALL_BACKUP_S3_REGION}\" \"\${EMDASH_INSTALL_BACKUP_S3_BUCKET}\" \"\${EMDASH_INSTALL_BACKUP_S3_ACCESS_KEY_ID}\" \"\${EMDASH_INSTALL_BACKUP_S3_SECRET_ACCESS_KEY}\" \"\${backup_key}\" <<'PY'
import sys
import boto3
from botocore.config import Config

endpoint, region, bucket, access, secret, key = sys.argv[1:]
client = boto3.client(
    \"s3\",
    endpoint_url=endpoint,
    aws_access_key_id=access,
    aws_secret_access_key=secret,
    region_name=region,
    config=Config(signature_version=\"s3v4\"),
)
client.head_object(Bucket=bucket, Key=key)
PY
	fi
fi
")"; then
		collect_remote_failure_context
		if [[ "${LINODE_TEST_KEEP_ON_FAILURE}" == "1" ]]; then
			LINODE_TEST_KEEP="1"
			LINODE_TEST_KEEP_SSH_KEY="1"
		fi
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
		--arg template "${LINODE_TEST_INSTALL_TEMPLATE}" \
		--arg db "${LINODE_TEST_INSTALL_DB_DRIVER}" \
		--arg session "${LINODE_TEST_INSTALL_SESSION_DRIVER}" \
		--arg storage "${LINODE_TEST_INSTALL_STORAGE_DRIVER}" \
		--arg domain "${LINODE_TEST_INSTALL_DOMAIN}" \
		--arg check_public_routes "${LINODE_TEST_CHECK_PUBLIC_ROUTES}" \
		--arg repeat_install "${LINODE_TEST_REPEAT_INSTALL}" \
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
			template: $template,
			db_driver: $db,
			session_driver: $session,
			storage_driver: $storage,
			domain: $domain,
			check_public_routes: ($check_public_routes == "1"),
			repeat_install: ($repeat_install == "1"),
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
		if ! push_workspace; then
			warn "区域 ${region} 工作区上传失败，尝试下一个区域。"
			destroy_current_instance
			continue
		fi
		if ! run_remote_test; then
			write_result_file
			fail "远端真实安装验证失败，已收集失败上下文。"
		fi
		write_result_file
		log "Linode 临时测试完成"
		attempt_success=1
		break
	done

	[[ "${attempt_success}" == "1" ]] || fail "所有候选区域都未能完成测试。"
}

main "$@"
