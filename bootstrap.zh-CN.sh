#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export EMDASH_INSTALL_LANG="zh-CN"
exec bash "${SCRIPT_DIR}/bootstrap.sh" "$@"
