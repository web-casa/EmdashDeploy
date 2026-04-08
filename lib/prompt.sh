#!/usr/bin/env bash

prompt_input_source() {
	if [[ -t 0 ]]; then
		printf '/dev/stdin\n'
		return
	fi

	if [[ -r /dev/tty ]]; then
		printf '/dev/tty\n'
		return
	fi

	printf '\n'
}

prompt_value() {
	local var_name="$1"
	local label="$2"
	local default_value="$3"
	local input=""
	local prompt_source=""
	local -n ref="${var_name}"

	prompt_source="$(prompt_input_source)"
	if [[ -z "${prompt_source}" ]]; then
		ref="${default_value}"
		return
	fi

	read -r -p "${label} [${default_value}]: " input <"${prompt_source}"
	ref="${input:-${default_value}}"
}

prompt_secret() {
	local var_name="$1"
	local label="$2"
	local default_value="$3"
	local input=""
	local masked_default=""
	local prompt_source=""
	local -n ref="${var_name}"

	if [[ -n "${default_value}" ]]; then
		masked_default="$(ti set_word)"
	else
		masked_default="$(ti blank_word)"
	fi

	prompt_source="$(prompt_input_source)"
	if [[ -z "${prompt_source}" ]]; then
		ref="${default_value}"
		return
	fi

	read -r -s -p "${label} ${masked_default}: " input <"${prompt_source}"
	printf '\n'
	ref="${input:-${default_value}}"
}

prompt_yes_no() {
	local var_name="$1"
	local label="$2"
	local default_value="$3"
	local input=""
	local pretty_default="y"
	local prompt_source=""
	local -n ref="${var_name}"

	if [[ "${default_value}" != "1" ]]; then
		pretty_default="n"
	fi

	prompt_source="$(prompt_input_source)"
	if [[ -z "${prompt_source}" ]]; then
		ref="${default_value}"
		return
	fi

	while true; do
		read -r -p "${label} [y/n, $(ti default_word) ${pretty_default}]: " input <"${prompt_source}"
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
	local prompt_source=""
	local -n ref="${var_name}"

	prompt_source="$(prompt_input_source)"
	if [[ -z "${prompt_source}" ]]; then
		ref="${default_value}"
		return
	fi

	IFS=' ' read -r -a option_list <<<"${options}"

	while true; do
		read -r -p "${label} [${options}] ($(ti default_word) ${default_value}): " input <"${prompt_source}"
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

prompt_confirm_dns_ready() {
	local input=""
	local prompt_source=""

	prompt_source="$(prompt_input_source)"
	if [[ -z "${prompt_source}" ]]; then
		return
	fi

	while true; do
		read -r -p "$(ti https_dns_confirm) [y/n]: " input <"${prompt_source}"
		case "${input,,}" in
		y | yes)
			return
			;;
		n | no)
			warn "$(ti https_dns_hint)"
			;;
		*)
			warn "$(ti enter_y_or_n)"
			;;
		esac
	done
}
