#!/usr/bin/env bash

prompt_value() {
	local var_name="$1"
	local label="$2"
	local default_value="$3"
	local input=""
	local -n ref="${var_name}"

	if [[ ! -t 0 ]]; then
		ref="${default_value}"
		return
	fi

	read -r -p "${label} [${default_value}]: " input
	ref="${input:-${default_value}}"
}

prompt_secret() {
	local var_name="$1"
	local label="$2"
	local default_value="$3"
	local input=""
	local masked_default=""
	local -n ref="${var_name}"

	if [[ -n "${default_value}" ]]; then
		masked_default="$(ti set_word)"
	else
		masked_default="$(ti blank_word)"
	fi

	if [[ ! -t 0 ]]; then
		ref="${default_value}"
		return
	fi

	read -r -s -p "${label} ${masked_default}: " input
	printf '\n'
	ref="${input:-${default_value}}"
}

prompt_yes_no() {
	local var_name="$1"
	local label="$2"
	local default_value="$3"
	local input=""
	local pretty_default="y"
	local -n ref="${var_name}"

	if [[ "${default_value}" != "1" ]]; then
		pretty_default="n"
	fi

	if [[ ! -t 0 ]]; then
		ref="${default_value}"
		return
	fi

	while true; do
		read -r -p "${label} [y/n, $(ti default_word) ${pretty_default}]: " input
		input="${input:-${pretty_default}}"
		case "${input,,}" in
		y | yes)
			ref="1"
			return
			;;
		n | no)
			ref="0"
			return
			;;
		esac
			warn "$(ti enter_y_or_n)"
		done
}

prompt_choice() {
	local var_name="$1"
	local label="$2"
	local options="$3"
	local default_value="$4"
	local input=""
	local -a option_list=()
	local -n ref="${var_name}"

	if [[ ! -t 0 ]]; then
		ref="${default_value}"
		return
	fi

	IFS=' ' read -r -a option_list <<<"${options}"

	while true; do
		read -r -p "${label} [${options}] ($(ti default_word) ${default_value}): " input
		input="${input:-${default_value}}"
		for option in "${option_list[@]}"; do
			if [[ "${input}" == "${option}" ]]; then
				ref="${input}"
				return
			fi
		done
			warn "$(ti choose_one_of) ${options}"
		done
}
