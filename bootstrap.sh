#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

REPO_OWNER="${EMDASH_BOOTSTRAP_OWNER:-web-casa}"
REPO_NAME="${EMDASH_BOOTSTRAP_REPO:-EmdashDeploy}"
REPO_REF="${EMDASH_BOOTSTRAP_REF:-main}"
INSTALL_LANG="${EMDASH_INSTALL_LANG:-en}"
KEEP_BOOTSTRAP_DIR="${EMDASH_BOOTSTRAP_KEEP:-0}"
BOOTSTRAP_TMP_DIR=""

cleanup() {
	if [[ "${KEEP_BOOTSTRAP_DIR}" == "1" ]]; then
		return
	fi
	if [[ -n "${BOOTSTRAP_TMP_DIR:-}" && -d "${BOOTSTRAP_TMP_DIR}" ]]; then
		rm -rf "${BOOTSTRAP_TMP_DIR}"
	fi
}

archive_url() {
	if [[ "${REPO_REF}" =~ ^[0-9] ]] || [[ "${REPO_REF}" == v* ]]; then
		printf 'https://codeload.github.com/%s/%s/tar.gz/refs/tags/%s\n' "${REPO_OWNER}" "${REPO_NAME}" "${REPO_REF}"
	else
		printf 'https://codeload.github.com/%s/%s/tar.gz/refs/heads/%s\n' "${REPO_OWNER}" "${REPO_NAME}" "${REPO_REF}"
	fi
}

main() {
	local archive=""
	local repo_dir=""
	local -a raw_args=("$@")
	local -a args=()
	local has_mode_flag="0"
	local show_help="0"
	local arg=""
	local idx=0

	trap cleanup EXIT

	while [[ "${idx}" -lt "${#raw_args[@]}" ]]; do
		arg="${raw_args[${idx}]}"
		case "${arg}" in
		--activate | --write-only)
			has_mode_flag="1"
			args+=("${arg}")
			;;
		-h | --help)
			show_help="1"
			args+=("${arg}")
			;;
		--lang=*)
			INSTALL_LANG="${arg#--lang=}"
			;;
		--lang)
			idx=$((idx + 1))
			[[ "${idx}" -lt "${#raw_args[@]}" ]] || {
				printf '[ERROR] Missing value for --lang\n' >&2
				exit 1
			}
			INSTALL_LANG="${raw_args[${idx}]}"
			;;
		*)
			args+=("${arg}")
			;;
		esac
		idx=$((idx + 1))
	done

	if [[ "${has_mode_flag}" != "1" && "${show_help}" != "1" ]]; then
		args+=(--activate)
	fi

	BOOTSTRAP_TMP_DIR="$(mktemp -d)"
	archive="${BOOTSTRAP_TMP_DIR}/emdashdeploy.tar.gz"

	curl -fsSL "$(archive_url)" -o "${archive}"
	tar -xzf "${archive}" -C "${BOOTSTRAP_TMP_DIR}"
	repo_dir="$(find "${BOOTSTRAP_TMP_DIR}" -maxdepth 1 -type d -name "${REPO_NAME}-*" | head -n 1)"
	[[ -n "${repo_dir}" && -d "${repo_dir}" ]] || {
		printf '[ERROR] Failed to unpack %s\n' "${REPO_NAME}" >&2
		exit 1
	}

	cd "${repo_dir}"
	chmod +x bootstrap*.sh install-emdash*.sh emdashctl emdashctl*.sh linode-test.sh 2>/dev/null || true

	export EMDASH_INSTALL_LANG="${INSTALL_LANG}"
	bash "./install-emdash.sh" "${args[@]}"
}

main "$@"
