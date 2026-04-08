#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export EMDASH_INSTALL_LANG="es"
exec "${SCRIPT_DIR}/emdashctl" "$@"
