#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export EMDASH_INSTALL_LANG="ja"
exec bash "${SCRIPT_DIR}/install-emdash.sh" "$@"
