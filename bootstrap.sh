#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

REPO_OWNER="${EMDASH_BOOTSTRAP_OWNER:-web-casa}"
REPO_NAME="${EMDASH_BOOTSTRAP_REPO:-EmdashDeploy}"
REPO_REF="${EMDASH_BOOTSTRAP_REF:-main}"
INSTALL_LANG="${EMDASH_INSTALL_LANG:-en}"
KEEP_BOOTSTRAP_DIR="${EMDASH_BOOTSTRAP_KEEP:-0}"
BOOTSTRAP_TMP_DIR=""

warn() {
	printf '[WARN] %s\n' "$*" >&2
}

cleanup() {
	if [[ "${KEEP_BOOTSTRAP_DIR}" == "1" ]]; then
		return
	fi
	if [[ -n "${BOOTSTRAP_TMP_DIR:-}" && -d "${BOOTSTRAP_TMP_DIR}" ]]; then
		rm -rf "${BOOTSTRAP_TMP_DIR}"
	fi
}

archive_url() {
	printf 'https://codeload.github.com/%s/%s/tar.gz/%s\n' "${REPO_OWNER}" "${REPO_NAME}" "${REPO_REF}"
}

main() {
	local archive=""
	local repo_dir=""
	local -a raw_args=("$@")
	local -a args=()
	local has_mode_flag="0"
	local show_help="0"
	local non_interactive="0"
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
		--non-interactive)
			non_interactive="1"
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
			--ref=*)
				REPO_REF="${arg#--ref=}"
				;;
			--ref)
				idx=$((idx + 1))
				[[ "${idx}" -lt "${#raw_args[@]}" ]] || {
					printf '[ERROR] Missing value for --ref\n' >&2
					exit 1
				}
				REPO_REF="${raw_args[${idx}]}"
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

	if [[ "${REPO_REF}" == "main" ]]; then
		warn "Bootstrap is using the mutable ref 'main'. Pass --ref <tag|commit> for a reproducible install."
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
	if [[ "${show_help}" == "1" || "${non_interactive}" == "1" ]]; then
		bash "./install-emdash.sh" "${args[@]}"
		return
	fi

	if [[ -r /dev/tty ]]; then
		bash "./install-emdash.sh" "${args[@]}" </dev/tty
		return
	fi

	printf '[ERROR] Interactive bootstrap requires a terminal. Use --non-interactive or download the repository locally.\n' >&2
	exit 1
}

main "$@"
