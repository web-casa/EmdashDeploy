#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${LINODE_TEST_MATRIX_OUTPUT_DIR:-${SCRIPT_DIR}/test-results}"
SCENARIO_FILTER="${LINODE_TEST_MATRIX_SCENARIOS:-}"
KEEP_ON_FAILURE="${LINODE_TEST_MATRIX_KEEP_ON_FAILURE:-0}"
PARALLEL="${LINODE_TEST_MATRIX_PARALLEL:-0}"
SUMMARY_JSON=""
SUMMARY_MD=""
RUN_ID=""

usage() {
	cat <<'EOF'
linode-test-matrix.sh

Usage:
  bash linode-test-matrix.sh [--list] [--scenario <name>[,<name>...]] [--output-dir <dir>] [--keep-on-failure] [--parallel]

Examples:
  bash linode-test-matrix.sh
  bash linode-test-matrix.sh --list
  bash linode-test-matrix.sh --scenario debian13-caddy-app,centos9-builder
  LINODE_TEST_INSTALL_APP_IMAGE=ghcr.io/web-casa/emdash-app:0.2.0-hi.1 bash linode-test-matrix.sh

Notes:
  - Reads linode_token from .env through linode-test.sh
  - Runs a predefined VPS scenario matrix
  - Writes per-scenario JSON result/failure logs plus a summary JSON and Markdown report
EOF
}

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

timestamp() {
	date +%Y%m%d-%H%M%S
}

list_scenarios() {
	cat <<'EOF'
debian13-caddy-app
centos9-builder
debian13-postgres-file
centos9-postgres-redis
debian13-s3-backup
alma10-postgres-redis
centos10-sqlite-file
rocky9-postgres-redis
ubuntu24-postgres-redis
EOF
}

scenario_exists() {
	case "$1" in
	debian13-caddy-app | centos9-builder | debian13-postgres-file | centos9-postgres-redis | debian13-s3-backup \
	| alma10-postgres-redis | centos10-sqlite-file | rocky9-postgres-redis | ubuntu24-postgres-redis)
		return 0
		;;
	esac
	return 1
}

setup_scenario() {
	local scenario="$1"
unset MATRIX_IMAGE MATRIX_DB MATRIX_SESSION MATRIX_STORAGE MATRIX_USE_CADDY MATRIX_ENABLE_HTTPS
unset MATRIX_DOMAIN_PROVIDER MATRIX_APP_IMAGE MATRIX_APP_BASE_IMAGE MATRIX_PG_PASSWORD MATRIX_REDIS_PASSWORD
	unset MATRIX_RUN_BACKUP MATRIX_BACKUP_TARGET MATRIX_BACKUP_S3_ENDPOINT MATRIX_BACKUP_S3_REGION MATRIX_BACKUP_S3_BUCKET MATRIX_BACKUP_S3_ACCESS_KEY_ID MATRIX_BACKUP_S3_SECRET_ACCESS_KEY MATRIX_BACKUP_S3_PREFIX

	case "${scenario}" in
		debian13-caddy-app)
		MATRIX_IMAGE="linode/debian13"
		MATRIX_DB="sqlite"
		MATRIX_SESSION="file"
		MATRIX_STORAGE="local"
		MATRIX_USE_CADDY="1"
		MATRIX_ENABLE_HTTPS="1"
			MATRIX_DOMAIN_PROVIDER="sslip.io"
			MATRIX_APP_IMAGE="${LINODE_TEST_INSTALL_APP_IMAGE:-ghcr.io/web-casa/emdash-app:0.2.0-hi.1}"
			;;
	centos9-builder)
		MATRIX_IMAGE="linode/centos-stream9"
		MATRIX_DB="sqlite"
		MATRIX_SESSION="file"
		MATRIX_STORAGE="local"
		MATRIX_USE_CADDY="0"
		MATRIX_ENABLE_HTTPS="0"
		MATRIX_APP_BASE_IMAGE="${LINODE_TEST_INSTALL_APP_BASE_IMAGE:-ghcr.io/web-casa/emdash-builder:0.2.0-hi.1}"
		;;
	debian13-postgres-file)
		MATRIX_IMAGE="linode/debian13"
		MATRIX_DB="postgres"
		MATRIX_SESSION="file"
		MATRIX_STORAGE="local"
		MATRIX_USE_CADDY="0"
		MATRIX_ENABLE_HTTPS="0"
		MATRIX_PG_PASSWORD="${LINODE_TEST_INSTALL_PG_PASSWORD:-Pg-Test-123_Complex@Value}"
		;;
		centos9-postgres-redis)
		MATRIX_IMAGE="linode/centos-stream9"
		MATRIX_DB="postgres"
		MATRIX_SESSION="redis"
		MATRIX_STORAGE="local"
		MATRIX_USE_CADDY="0"
		MATRIX_ENABLE_HTTPS="0"
			MATRIX_PG_PASSWORD="${LINODE_TEST_INSTALL_PG_PASSWORD:-Pg-Test-123_Complex@Value}"
			MATRIX_REDIS_PASSWORD="${LINODE_TEST_INSTALL_REDIS_PASSWORD:-Redis-Test-123:@Value}"
			;;
		debian13-s3-backup)
			MATRIX_IMAGE="linode/debian13"
			MATRIX_DB="sqlite"
			MATRIX_SESSION="file"
			MATRIX_STORAGE="local"
			MATRIX_USE_CADDY="0"
			MATRIX_ENABLE_HTTPS="0"
			MATRIX_RUN_BACKUP="1"
			MATRIX_BACKUP_TARGET="${LINODE_TEST_INSTALL_BACKUP_TARGET:-s3}"
			MATRIX_BACKUP_S3_ENDPOINT="${LINODE_TEST_INSTALL_BACKUP_S3_ENDPOINT:-}"
			MATRIX_BACKUP_S3_REGION="${LINODE_TEST_INSTALL_BACKUP_S3_REGION:-auto}"
			MATRIX_BACKUP_S3_BUCKET="${LINODE_TEST_INSTALL_BACKUP_S3_BUCKET:-}"
			MATRIX_BACKUP_S3_ACCESS_KEY_ID="${LINODE_TEST_INSTALL_BACKUP_S3_ACCESS_KEY_ID:-}"
			MATRIX_BACKUP_S3_SECRET_ACCESS_KEY="${LINODE_TEST_INSTALL_BACKUP_S3_SECRET_ACCESS_KEY:-}"
			MATRIX_BACKUP_S3_PREFIX="${LINODE_TEST_INSTALL_BACKUP_S3_PREFIX:-backups}"
			;;
	alma10-postgres-redis)
		MATRIX_IMAGE="linode/almalinux10"
		MATRIX_DB="postgres"
		MATRIX_SESSION="redis"
		MATRIX_STORAGE="local"
		MATRIX_USE_CADDY="0"
		MATRIX_ENABLE_HTTPS="0"
		MATRIX_PG_PASSWORD="${LINODE_TEST_INSTALL_PG_PASSWORD:-Pg-Test-123_Complex@Value}"
		MATRIX_REDIS_PASSWORD="${LINODE_TEST_INSTALL_REDIS_PASSWORD:-Redis-Test-123:@Value}"
		;;
	centos10-sqlite-file)
		MATRIX_IMAGE="linode/centos-stream10"
		MATRIX_DB="sqlite"
		MATRIX_SESSION="file"
		MATRIX_STORAGE="local"
		MATRIX_USE_CADDY="0"
		MATRIX_ENABLE_HTTPS="0"
		;;
	rocky9-postgres-redis)
		MATRIX_IMAGE="linode/rocky9"
		MATRIX_DB="postgres"
		MATRIX_SESSION="redis"
		MATRIX_STORAGE="local"
		MATRIX_USE_CADDY="0"
		MATRIX_ENABLE_HTTPS="0"
		MATRIX_PG_PASSWORD="${LINODE_TEST_INSTALL_PG_PASSWORD:-Pg-Test-123_Complex@Value}"
		MATRIX_REDIS_PASSWORD="${LINODE_TEST_INSTALL_REDIS_PASSWORD:-Redis-Test-123:@Value}"
		;;
	ubuntu24-postgres-redis)
		MATRIX_IMAGE="linode/ubuntu24.04"
		MATRIX_DB="postgres"
		MATRIX_SESSION="redis"
		MATRIX_STORAGE="local"
		MATRIX_USE_CADDY="0"
		MATRIX_ENABLE_HTTPS="0"
		MATRIX_PG_PASSWORD="${LINODE_TEST_INSTALL_PG_PASSWORD:-Pg-Test-123_Complex@Value}"
		MATRIX_REDIS_PASSWORD="${LINODE_TEST_INSTALL_REDIS_PASSWORD:-Redis-Test-123:@Value}"
		;;
	*)
		fail "Unknown scenario: ${scenario}"
		;;
	esac
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--list)
			list_scenarios
			exit 0
			;;
		--scenario)
			shift
			[[ $# -gt 0 ]] || fail "--scenario requires a value"
			SCENARIO_FILTER="$1"
			;;
		--output-dir)
			shift
			[[ $# -gt 0 ]] || fail "--output-dir requires a value"
			OUTPUT_DIR="$1"
			;;
		--keep-on-failure)
			KEEP_ON_FAILURE="1"
			;;
		--parallel)
			PARALLEL="1"
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			fail "Unknown argument: $1"
			;;
		esac
		shift
	done
}

ensure_output_dir() {
	RUN_ID="$(timestamp)"
	mkdir -p "${OUTPUT_DIR}"
	SUMMARY_JSON="${OUTPUT_DIR}/summary-${RUN_ID}.json"
	SUMMARY_MD="${OUTPUT_DIR}/summary-${RUN_ID}.md"
}

selected_scenarios() {
	local scenario
	if [[ -n "${SCENARIO_FILTER}" ]]; then
		printf '%s\n' "${SCENARIO_FILTER}" | tr ',' '\n' | sed '/^$/d'
	else
		list_scenarios
	fi

	while IFS= read -r scenario; do
		[[ -n "${scenario}" ]] || continue
		scenario_exists "${scenario}" || fail "Unknown scenario in selection: ${scenario}"
	done < <(if [[ -n "${SCENARIO_FILTER}" ]]; then printf '%s\n' "${SCENARIO_FILTER}" | tr ',' '\n' | sed '/^$/d'; else list_scenarios; fi)
}

run_scenario() {
	local scenario="$1"
	local item_file="$2"
	local result_file failure_log started_at finished_at exit_code keep_flag

	setup_scenario "${scenario}"
	started_at="$(date -Iseconds)"
	result_file="${OUTPUT_DIR}/${scenario}.json"
	failure_log="${OUTPUT_DIR}/${scenario}-failure.log"
	keep_flag="0"
	[[ "${KEEP_ON_FAILURE}" == "1" ]] && keep_flag="1"

	log "Running scenario: ${scenario}"

	if env \
		LINODE_TEST_RESULT_FILE="${result_file}" \
		LINODE_TEST_FAILURE_LOG="${failure_log}" \
		LINODE_TEST_IMAGE="${MATRIX_IMAGE}" \
		LINODE_TEST_INSTALL_DB_DRIVER="${MATRIX_DB}" \
		LINODE_TEST_INSTALL_SESSION_DRIVER="${MATRIX_SESSION}" \
		LINODE_TEST_INSTALL_STORAGE_DRIVER="${MATRIX_STORAGE}" \
		LINODE_TEST_INSTALL_USE_CADDY="${MATRIX_USE_CADDY}" \
		LINODE_TEST_INSTALL_ENABLE_HTTPS="${MATRIX_ENABLE_HTTPS}" \
		LINODE_TEST_DOMAIN_PROVIDER="${MATRIX_DOMAIN_PROVIDER:-}" \
		LINODE_TEST_INSTALL_APP_IMAGE="${MATRIX_APP_IMAGE:-}" \
		LINODE_TEST_INSTALL_APP_BASE_IMAGE="${MATRIX_APP_BASE_IMAGE:-}" \
		LINODE_TEST_INSTALL_PG_PASSWORD="${MATRIX_PG_PASSWORD:-}" \
		LINODE_TEST_INSTALL_REDIS_PASSWORD="${MATRIX_REDIS_PASSWORD:-}" \
		LINODE_TEST_RUN_BACKUP="${MATRIX_RUN_BACKUP:-0}" \
		LINODE_TEST_INSTALL_BACKUP_TARGET="${MATRIX_BACKUP_TARGET:-}" \
		LINODE_TEST_INSTALL_BACKUP_S3_ENDPOINT="${MATRIX_BACKUP_S3_ENDPOINT:-}" \
		LINODE_TEST_INSTALL_BACKUP_S3_REGION="${MATRIX_BACKUP_S3_REGION:-}" \
		LINODE_TEST_INSTALL_BACKUP_S3_BUCKET="${MATRIX_BACKUP_S3_BUCKET:-}" \
		LINODE_TEST_INSTALL_BACKUP_S3_ACCESS_KEY_ID="${MATRIX_BACKUP_S3_ACCESS_KEY_ID:-}" \
		LINODE_TEST_INSTALL_BACKUP_S3_SECRET_ACCESS_KEY="${MATRIX_BACKUP_S3_SECRET_ACCESS_KEY:-}" \
		LINODE_TEST_INSTALL_BACKUP_S3_PREFIX="${MATRIX_BACKUP_S3_PREFIX:-}" \
		LINODE_TEST_KEEP="${keep_flag}" \
		bash "${SCRIPT_DIR}/linode-test.sh"; then
		exit_code=0
	else
		exit_code=$?
		warn "Scenario failed: ${scenario}"
	fi
	finished_at="$(date -Iseconds)"

	jq -n \
		--arg scenario "${scenario}" \
		--arg image "${MATRIX_IMAGE}" \
		--arg db "${MATRIX_DB}" \
		--arg session "${MATRIX_SESSION}" \
		--arg storage "${MATRIX_STORAGE}" \
		--arg use_caddy "${MATRIX_USE_CADDY}" \
		--arg enable_https "${MATRIX_ENABLE_HTTPS}" \
		--arg backup_target "${MATRIX_BACKUP_TARGET:-}" \
		--arg app_image "${MATRIX_APP_IMAGE:-}" \
		--arg app_base_image "${MATRIX_APP_BASE_IMAGE:-}" \
		--arg started_at "${started_at}" \
		--arg finished_at "${finished_at}" \
		--arg result_file "${result_file}" \
		--arg failure_log "${failure_log}" \
		--argjson exit_code "${exit_code}" \
		'{
			scenario: $scenario,
			image: $image,
			db_driver: $db,
			session_driver: $session,
			storage_driver: $storage,
			use_caddy: ($use_caddy == "1"),
			enable_https: ($enable_https == "1"),
			backup_target: $backup_target,
			app_image: $app_image,
			app_base_image: $app_base_image,
			started_at: $started_at,
			finished_at: $finished_at,
			exit_code: $exit_code,
			passed: ($exit_code == 0),
			result_file: $result_file,
			failure_log: $failure_log
		}' >"${item_file}"
}

write_summary_markdown() {
	local summary_file="$1"
	jq -r '
		"# VPS Test Matrix Summary\n",
		"",
		"* Generated at: \(.generated_at)",
		"* Output directory: \(.output_dir)",
		"* Passed: \(.passed_count)/\(.total_count)",
		"",
		"| Scenario | Result | Image | DB | Session | Caddy | Output |",
		"|---|---|---|---|---|---|---|",
		(.results[] | "| \(.scenario) | " + (if .passed then "pass" else "fail" end) + " | \(.image) | \(.db_driver) | \(.session_driver) | " + (if .use_caddy then "yes" else "no" end) + " | `\(.result_file)` |")
	' "${summary_file}" >"${SUMMARY_MD}"
}

main() {
	local scenario
	local tmp_summary
	local item_file

	parse_args "$@"
	ensure_output_dir
	tmp_summary="$(mktemp)"
	printf '[]\n' >"${tmp_summary}"

	if [[ "${PARALLEL}" == "1" ]]; then
		local -a pids=()
		local -a item_files=()
		local -a scenarios_ordered=()
		while IFS= read -r scenario; do
			[[ -n "${scenario}" ]] || continue
			scenarios_ordered+=("${scenario}")
			item_file="${OUTPUT_DIR}/.item-${scenario}.json"
			item_files+=("${item_file}")
			run_scenario "${scenario}" "${item_file}" &
			pids+=($!)
			log "启动并行场景: ${scenario} (PID $!)"
		done < <(selected_scenarios)
		local idx=0
		for pid in "${pids[@]}"; do
			wait "${pid}" || true
			item_file="${item_files[${idx}]}"
			if [[ ! -f "${item_file}" ]]; then
				warn "场景 ${scenarios_ordered[${idx}]} 未生成结果文件，标记为失败"
				jq -n --arg scenario "${scenarios_ordered[${idx}]}" \
					'{scenario: $scenario, passed: false, exit_code: 1, image: "unknown", db_driver: "unknown", session_driver: "unknown", storage_driver: "unknown", use_caddy: false, enable_https: false, backup_target: "", app_image: "", app_base_image: "", started_at: "", finished_at: "", result_file: "", failure_log: ""}' \
					>"${item_file}"
			fi
			jq -n --slurpfile item "${item_file}" --slurpfile arr "${tmp_summary}" '$arr[0] + [$item[0]]' >"${tmp_summary}.new"
			mv "${tmp_summary}.new" "${tmp_summary}"
			rm -f "${item_file}"
			idx=$(( idx + 1 ))
		done
	else
		while IFS= read -r scenario; do
			[[ -n "${scenario}" ]] || continue
			item_file="$(mktemp)"
			run_scenario "${scenario}" "${item_file}"
			jq -n --slurpfile item "${item_file}" --slurpfile arr "${tmp_summary}" '$arr[0] + [$item[0]]' >"${tmp_summary}.new"
			mv "${tmp_summary}.new" "${tmp_summary}"
			rm -f "${item_file}"
		done < <(selected_scenarios)
	fi

	jq -n \
		--arg generated_at "$(date -Iseconds)" \
		--arg output_dir "${OUTPUT_DIR}" \
		--slurpfile results "${tmp_summary}" \
		'{
			generated_at: $generated_at,
			output_dir: $output_dir,
			results: $results[0],
			total_count: ($results[0] | length),
			passed_count: ($results[0] | map(select(.passed)) | length),
			failed_count: ($results[0] | map(select(.passed | not)) | length)
		}' >"${SUMMARY_JSON}"

	write_summary_markdown "${SUMMARY_JSON}"
	rm -f "${tmp_summary}"

	log "Summary JSON: ${SUMMARY_JSON}"
	log "Summary Markdown: ${SUMMARY_MD}"

	if jq -e '.failed_count > 0' "${SUMMARY_JSON}" >/dev/null; then
		exit 1
	fi
}

main "$@"
