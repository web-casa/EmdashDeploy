#!/usr/bin/env bash
# Shared EmDash site management helpers used by both install-emdash.sh and emdashctl.
# Deployed atomically to ${ROOT_DIR}/lib/site-common.sh.

EMDASH_LIB_SCHEMA_VERSION="1"
EMDASH_DEFAULT_PNPM_SPEC="pnpm@11.9.0"

resolve_site_pnpm_spec() {
	local site_dir="${1:-${SITE_DIR:-}}"
	local fallback="${2:-${EMDASH_DEFAULT_PNPM_SPEC}}"
	if [[ -z "${site_dir}" || ! -f "${site_dir}/package.json" ]]; then
		printf '%s\n' "${fallback}"
		return 0
	fi
	python3 - "${site_dir}/package.json" "${fallback}" <<'PY'
import json
import sys
from pathlib import Path

pkg_path = Path(sys.argv[1])
fallback = sys.argv[2]
try:
    pkg = json.loads(pkg_path.read_text())
    pm = pkg.get("packageManager")
    if isinstance(pm, str) and pm.startswith("pnpm@") and len(pm) > 5:
        print(pm.strip())
    else:
        print(fallback)
except Exception:
    print(fallback)
PY
}

strip_pnpm_spec_hash() {
	local spec="${1:-${EMDASH_DEFAULT_PNPM_SPEC}}"
	printf '%s\n' "${spec%%+*}"
}

ensure_site_pnpm() {
	local site_dir="${1:-${SITE_DIR:-}}"
	local spec=""
	local plain_spec=""
	local corepack_bin="corepack"

	export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
	if [[ -x "/usr/bin/corepack" ]]; then
		corepack_bin="/usr/bin/corepack"
	fi

	spec="$(resolve_site_pnpm_spec "${site_dir}")"
	plain_spec="$(strip_pnpm_spec_hash "${spec}")"

	"${corepack_bin}" enable >/dev/null 2>&1 || true

	if "${corepack_bin}" prepare "${spec}" --activate >/dev/null 2>&1; then
		return 0
	fi

	# When using third-party mirrors, +sha512 metadata can occasionally mismatch.
	if [[ "${plain_spec}" != "${spec}" ]]; then
		if "${corepack_bin}" prepare "${plain_spec}" --activate >/dev/null 2>&1; then
			return 0
		fi
	fi

	# Fallback without custom mirror if COREPACK_NPM_REGISTRY was set.
	if [[ -n "${COREPACK_NPM_REGISTRY:-}" ]]; then
		if env -u COREPACK_NPM_REGISTRY "${corepack_bin}" prepare "${spec}" --activate >/dev/null 2>&1; then
			return 0
		fi
		if [[ "${plain_spec}" != "${spec}" ]] && env -u COREPACK_NPM_REGISTRY "${corepack_bin}" prepare "${plain_spec}" --activate >/dev/null 2>&1; then
			return 0
		fi
	fi

	if command -v pnpm >/dev/null 2>&1; then
		return 0
	fi

	printf '[ERROR] Failed to prepare pnpm (%s) via corepack.\n' "${spec}" >&2
	return 1
}

validate_emdash_encryption_key() {
	local raw_value="${1:-}"
	[[ -n "${raw_value}" ]] || return 1
	python3 - "${raw_value}" <<'PY'
import re
import sys

raw = sys.argv[1].strip()
pattern = re.compile(r"^emdash_enc_v1_[A-Za-z0-9_-]{43}$")
parts = [p.strip() for p in raw.split(",") if p.strip()]
if not parts:
    sys.exit(1)
for part in parts:
    if not pattern.match(part):
        sys.exit(1)
sys.exit(0)
PY
}

generate_emdash_encryption_key_spec() {
	python3 - <<'PY'
import base64
import os

raw = os.urandom(32)
encoded = base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")
print(f"emdash_enc_v1_{encoded}")
PY
}

emdash_encryption_key_fingerprint() {
	local raw_value="${1:-}"
	[[ -n "${raw_value}" ]] || return 1
	python3 - "${raw_value}" <<'PY'
import base64
import hashlib
import re
import sys

raw = sys.argv[1].strip()
pattern = re.compile(r"^emdash_enc_v1_([A-Za-z0-9_-]{43})$")
kids = []
for part in [p.strip() for p in raw.split(",") if p.strip()]:
    m = pattern.match(part)
    if not m:
        sys.exit(1)
    b64 = m.group(1) + "=" * ((4 - len(m.group(1)) % 4) % 4)
    key_bytes = base64.urlsafe_b64decode(b64.encode("ascii"))
    if len(key_bytes) != 32:
        sys.exit(1)
    kids.append(hashlib.sha256(key_bytes).hexdigest()[:8])
if not kids:
    sys.exit(1)
print(",".join(kids))
PY
}

update_env_file_value() {
	local key="$1"
	local value="$2"
	local file="$3"
	KEY="${key}" VALUE="${value}" TARGET_FILE="${file}" python3 <<'PY'
from pathlib import Path
import os

def quote(value: str) -> str:
    value = value.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`").replace("\n", "\\n")
    return f'"{value}"'

path = Path(os.environ["TARGET_FILE"])
key = os.environ["KEY"]
value = os.environ["VALUE"]
lines = []
updated = False
if path.exists():
    for raw in path.read_text().splitlines():
        if raw.startswith(f"{key}="):
            lines.append(f"{key}={quote(value)}")
            updated = True
        else:
            lines.append(raw)
if not updated:
    lines.append(f"{key}={quote(value)}")
path.write_text("\n".join(lines) + "\n")
PY
}

patch_site_package_json_common() {
	local site_dir="${1:-${SITE_DIR}}"
	local project_name="${2:-${PROJECT_NAME:-emdash}}"
	local db_driver="${3:-${DB_DRIVER:-sqlite}}"
	local session_driver="${4:-${SESSION_DRIVER:-file}}"
	local storage_driver="${5:-${STORAGE_DRIVER:-local}}"
	local enable_plugin_sandbox="${6:-${ENABLE_PLUGIN_SANDBOX:-1}}"

	PROJECT_NAME="${project_name}" \
	SITE_DIR="${site_dir}" \
	DB_DRIVER="${db_driver}" \
	SESSION_DRIVER="${session_driver}" \
	STORAGE_DRIVER="${storage_driver}" \
	ENABLE_PLUGIN_SANDBOX="${enable_plugin_sandbox}" \
	python3 <<'PY'
import json
import os
from pathlib import Path

site_dir = Path(os.environ["SITE_DIR"])
pkg_path = site_dir / "package.json"
pkg = json.loads(pkg_path.read_text())

pkg["name"] = os.environ["PROJECT_NAME"]
# Respect template's own packageManager; only fill fallback when missing.
if not isinstance(pkg.get("packageManager"), str) or not pkg["packageManager"].strip():
    pkg["packageManager"] = "pnpm@11.9.0"

pkg.setdefault("emdash", {})
if (site_dir / "seed" / "seed.json").exists():
    pkg["emdash"]["seed"] = "seed/seed.json"

deps = pkg.setdefault("dependencies", {})
# Do NOT force-downgrade or inject kysely: emdash 1.6.x provides kysely@^0.29.x cleanly.
if os.environ["DB_DRIVER"] == "postgres":
    deps.setdefault("pg", "^8.16.3")
if os.environ["SESSION_DRIVER"] == "redis":
    deps.setdefault("ioredis", "^5.7.0")
if os.environ["STORAGE_DRIVER"] == "s3":
    deps.setdefault("@aws-sdk/client-s3", "^3.879.0")
    deps.setdefault("@aws-sdk/s3-request-presigner", "^3.879.0")
if os.environ.get("ENABLE_PLUGIN_SANDBOX", "1") == "1":
    deps.setdefault("@emdash-cms/sandbox-workerd", "^0.9.8")
    deps.setdefault("workerd", "^1.20260401.0")

pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")
PY
}

find_astro_patch_script() {
	local candidate=""
	for candidate in \
		"${ROOT_DIR:-}/lib/astro-patch.py" \
		"${SCRIPT_DIR:-}/lib/astro-patch.py" \
		"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/astro-patch.py"; do
		if [[ -n "${candidate}" && -f "${candidate}" ]]; then
			printf '%s\n' "${candidate}"
			return 0
		fi
	done
	return 1
}

render_site_astro_config_common() {
	local patch_script=""
	patch_script="$(find_astro_patch_script)" || {
		printf '[ERROR] astro-patch.py not found\n' >&2
		return 1
	}
	SITE_DIR="${SITE_DIR}" \
	DB_DRIVER="${DB_DRIVER}" \
	SESSION_DRIVER="${SESSION_DRIVER}" \
	STORAGE_DRIVER="${STORAGE_DRIVER}" \
	ENABLE_PLUGIN_SANDBOX="${ENABLE_PLUGIN_SANDBOX:-1}" \
		python3 "${patch_script}"
}

render_site_app_scripts_common() {
	local node_heap="${APP_NODE_MAX_OLD_SPACE_SIZE:-1536}"
	local lib_dir="${ROOT_DIR}/lib"
	mkdir -p "${SCRIPTS_DIR}"

	cat >"${APP_BUILD_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\${PATH:-}"
export NODE_OPTIONS="--max-old-space-size=${node_heap}"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
if [[ -f "${APP_ENV_FILE}" ]]; then
	set -a
	. "${APP_ENV_FILE}"
	set +a
fi
if [[ -f "${lib_dir}/site-common.sh" ]]; then
	. "${lib_dir}/site-common.sh"
	ensure_site_pnpm "${SITE_DIR}"
else
	corepack enable || true
fi
cd "${SITE_DIR}"
if [[ "\${EMDASH_BUILD_ALLOW_LOCKFILE_UPDATE:-0}" == "1" || ! -f "pnpm-lock.yaml" ]]; then
	pnpm install --no-frozen-lockfile
else
	pnpm install --frozen-lockfile
fi
pnpm build
EOF
	chmod 0755 "${APP_BUILD_SCRIPT}"

	cat >"${APP_START_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\${PATH:-}"
export NODE_OPTIONS="--max-old-space-size=${node_heap}"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
if [[ -f "${lib_dir}/site-common.sh" ]]; then
	. "${lib_dir}/site-common.sh"
	ensure_site_pnpm "${SITE_DIR}"
else
	corepack enable || true
fi
cd "${SITE_DIR}"
if [[ "\${DB_DRIVER:-sqlite}" == "sqlite" ]]; then
	mkdir -p "${SQLITE_DIR}"
	if [[ ! -f "${SQLITE_PATH}" ]]; then
		pnpm exec emdash init --database "${SQLITE_PATH}"
	fi
fi
exec pnpm start
EOF
	chmod 0755 "${APP_START_SCRIPT}"

	if id "${APP_RUN_USER:-emdash}" >/dev/null 2>&1; then
		chown "${APP_RUN_USER}:${APP_RUN_GROUP}" "${APP_BUILD_SCRIPT}" "${APP_START_SCRIPT}"
	fi
}

render_site_health_endpoint_common() {
	mkdir -p "${SITE_DIR}/src/pages"
	cat >"${SITE_DIR}/src/pages/healthz.ts" <<'EOF'
export const GET = () => {
	return new Response("OK", { status: 200 });
};
EOF
}

atomic_install_file() {
	local mode="$1"
	local src="$2"
	local dst="$3"
	local dst_dir=""
	local tmp_dst=""
	dst_dir="$(dirname "${dst}")"
	mkdir -p "${dst_dir}"
	tmp_dst="$(mktemp "${dst_dir}/.$(basename "${dst}").tmp.XXXXXX")"
	cp -f "${src}" "${tmp_dst}"
	chmod "${mode}" "${tmp_dst}"
	mv -f "${tmp_dst}" "${dst}"
}
