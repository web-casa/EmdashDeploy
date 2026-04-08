#!/usr/bin/env bash

declare -a IP_SOURCES_V4=(
	"https://api.ipify.org"
	"https://ifconfig.me/ip"
	"https://checkip.amazonaws.com"
	"https://icanhazip.com"
	"https://ipv4.icanhazip.com"
	"https://ident.me"
	"https://ipecho.net/plain"
)

declare -a IP_SOURCES_V6=(
	"https://api64.ipify.org"
	"https://icanhazip.com"
	"https://ipv6.icanhazip.com"
)

validate_ip() {
	local candidate="${1:-}"
	local family="${2:-4}"
	python3 - "$candidate" "$family" <<'PY'
import ipaddress
import sys

candidate = sys.argv[1].strip()
family = int(sys.argv[2])
try:
    ip = ipaddress.ip_address(candidate)
    if ip.version == family:
        sys.exit(0)
except ValueError:
    pass
sys.exit(1)
PY
}

detect_public_ip_family() {
	local family="$1"
	local result_var="$2"
	local -n result_ref="${result_var}"
	local -a sources=()
	local -a values=()
	local raw=""
	local winner=""
	local count=""

	if [[ "${family}" == "4" ]]; then
		sources=("${IP_SOURCES_V4[@]}")
	else
		sources=("${IP_SOURCES_V6[@]}")
	fi

	for source in "${sources[@]}"; do
		raw="$(curl -${family} -fsSL --max-time 4 "${source}" 2>/dev/null | tr -d '\r' | tr -d '\n' || true)"
		if [[ -n "${raw}" ]] && validate_ip "${raw}" "${family}"; then
			values+=("${raw}")
		fi
	done

	if [[ "${#values[@]}" -eq 0 ]]; then
		result_ref=""
		return
	fi

	winner="$(printf '%s\n' "${values[@]}" | sort | uniq -c | sort -nr | awk 'NR==1 { print $2 }')"
	count="$(printf '%s\n' "${values[@]}" | grep -c "^${winner}$" || true)"

	if [[ "${count}" -ge 2 || "${#values[@]}" -eq 1 ]]; then
		result_ref="${winner}"
	else
		result_ref=""
	fi
}

detect_public_ips() {
	PUBLIC_IPV4=""
	PUBLIC_IPV6=""
	detect_public_ip_family 4 PUBLIC_IPV4
	detect_public_ip_family 6 PUBLIC_IPV6

	if [[ -z "${PUBLIC_IPV4}" ]]; then
		warn "未能可靠识别公网 IPv4。"
	fi
	if [[ -z "${PUBLIC_IPV6}" ]]; then
		warn "未能可靠识别公网 IPv6。"
	fi
}

port_in_use() {
	local port="$1"
	ss -ltn "( sport = :${port} )" 2>/dev/null | tail -n +2 | grep -q .
}

resolve_record() {
	local domain="$1"
	local family="$2"

	if command_exists dig; then
		if [[ "${family}" == "A" ]]; then
			dig +short A "${domain}" | sed '/^$/d'
		else
			dig +short AAAA "${domain}" | sed '/^$/d'
		fi
		return
	fi

	if [[ "${family}" == "A" ]]; then
		getent ahostsv4 "${domain}" | awk '{print $1}' | sort -u
	else
		getent ahostsv6 "${domain}" | awk '{print $1}' | sort -u
	fi
}

validate_domain_requirements() {
	if [[ "${USE_CADDY}" != "1" || -z "${DOMAIN}" ]]; then
		return
	fi

	if port_in_use 80; then
		fail "检测到 80 端口已被占用，无法为 Caddy 提供 HTTP/HTTPS。"
	fi
	if port_in_use 443; then
		fail "检测到 443 端口已被占用，无法为 Caddy 提供 HTTP/HTTPS。"
	fi

	local a_records=""
	local aaaa_records=""
	local has_match=0
	a_records="$(resolve_record "${DOMAIN}" A || true)"
	aaaa_records="$(resolve_record "${DOMAIN}" AAAA || true)"

	if [[ -z "${a_records}" && -z "${aaaa_records}" ]]; then
		fail "域名 ${DOMAIN} 没有可用的 A/AAAA 解析记录。"
	fi

	if [[ -n "${a_records}" ]]; then
		[[ -n "${PUBLIC_IPV4}" ]] || fail "域名 ${DOMAIN} 存在 A 记录，但当前主机未检测到公网 IPv4。"
		if printf '%s\n' "${a_records}" | grep -qx "${PUBLIC_IPV4}"; then
			has_match=1
		else
			fail "域名 A 记录未解析到本机 IPv4 ${PUBLIC_IPV4}。"
		fi
	fi

	if [[ -n "${aaaa_records}" ]]; then
		[[ -n "${PUBLIC_IPV6}" ]] || fail "域名 ${DOMAIN} 存在 AAAA 记录，但当前主机未检测到公网 IPv6。"
		if printf '%s\n' "${aaaa_records}" | grep -qx "${PUBLIC_IPV6}"; then
			has_match=1
		else
			fail "域名 AAAA 记录未解析到本机 IPv6 ${PUBLIC_IPV6}。"
		fi
	fi

	if [[ "${has_match}" != "1" ]]; then
		fail "域名 ${DOMAIN} 未解析到当前服务器。"
	fi
}

test_s3_storage() {
	ensure_runtime_present

	local test_key="emdash-installer-test-$(date +%s).txt"
	local tmp_file
	tmp_file="$(mktemp)"
	printf 'emdash-storage-check\n' >"${tmp_file}"

	log "执行对象存储上传测试"

	python3 - "${S3_ENDPOINT}" "${S3_REGION}" "${S3_BUCKET}" "${S3_ACCESS_KEY_ID}" "${S3_SECRET_ACCESS_KEY}" "${test_key}" "${tmp_file}" <<'PY'
import sys
import boto3
from botocore.config import Config

endpoint, region, bucket, access, secret, key, body_path = sys.argv[1:]
client = boto3.client(
    "s3",
    endpoint_url=endpoint,
    aws_access_key_id=access,
    aws_secret_access_key=secret,
    region_name=region,
    config=Config(signature_version="s3v4"),
)
with open(body_path, "rb") as fh:
    client.put_object(Bucket=bucket, Key=key, Body=fh)
client.delete_object(Bucket=bucket, Key=key)
PY

	rm -f "${tmp_file}"
	log "对象存储上传测试通过"
}
