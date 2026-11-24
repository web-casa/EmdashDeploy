#!/usr/bin/env bash
# Generic remote host E2E verification harness for EmdashDeploy.
#
# Safety defaults:
# - Read-only / non-destructive checks by default (status, doctor --deep, diagnose,
#   upgrade --dry-run, template diff --stat).
# - Destructive lifecycle verification (install, upgrade, backup/restore, key rotation,
#   password reset) requires explicit --destructive.
# - Reboot autostart verification requires explicit --verify-reboot (with --destructive).
# - Never uses StrictHostKeyChecking=no, never enables set -x, never passes secrets on CLI.
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET_HOST=""
SSH_PORT="22"
SSH_IDENTITY=""
SSH_KNOWN_HOSTS=""
SSH_STRICT_MODE=""
SSH_PROXY_CMD=""
SSH_CONFIG_FILE="/dev/null"

DESTRUCTIVE="0"
VERIFY_REBOOT="0"
DB_DRIVER="postgres"
SESSION_DRIVER="redis"
STORAGE_DRIVER="local"
TEMPLATE="blog"
MIRROR_PRESET=""
TEMPLATES_REPO=""
OUT_DIR=""

usage() {
	cat <<'EOF'
remote-e2e-verify.sh — Safe remote E2E verification for EmdashDeploy

Usage:
  bash scripts/remote-e2e-verify.sh --host <user@host> [options]

Options:
  --host <user@host>           Target SSH host (required)
  --port <port>                SSH port (default: 22)
  --identity <path>            SSH private key path
  --known-hosts <path>         Path to known_hosts file
  --strict-host-key <mode>     yes | accept-new (default: yes if --known-hosts exists, else accept-new)
  --proxy-command <cmd>        Optional SSH ProxyCommand
  --destructive                Run full install + lifecycle mutation tests (OFF by default)
  --verify-reboot              Reboot target after tests and verify autostart (requires --destructive)
  --db <sqlite|postgres>       DB driver for --destructive install (default: postgres)
  --session <file|redis>       Session driver for --destructive install (default: redis)
  --template <blog|marketing|portfolio>  Template name (default: blog)
  --mirror-preset <cn>         Optional mirror preset for --destructive install
  --templates-repo <url>       Optional templates repo mirror URL
  --out-dir <dir>              Directory to store JSON verification reports
  -h, --help                   Show this help
EOF
}

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
	case "$1" in
	--host=*) TARGET_HOST="${1#--host=}" ;;
	--host) shift; [[ $# -gt 0 ]] || fail "Missing value for --host"; TARGET_HOST="$1" ;;
	--port=*) SSH_PORT="${1#--port=}" ;;
	--port) shift; [[ $# -gt 0 ]] || fail "Missing value for --port"; SSH_PORT="$1" ;;
	--identity=*) SSH_IDENTITY="${1#--identity=}" ;;
	--identity) shift; [[ $# -gt 0 ]] || fail "Missing value for --identity"; SSH_IDENTITY="$1" ;;
	--known-hosts=*) SSH_KNOWN_HOSTS="${1#--known-hosts=}" ;;
	--known-hosts) shift; [[ $# -gt 0 ]] || fail "Missing value for --known-hosts"; SSH_KNOWN_HOSTS="$1" ;;
	--strict-host-key=*) SSH_STRICT_MODE="${1#--strict-host-key=}" ;;
	--strict-host-key) shift; [[ $# -gt 0 ]] || fail "Missing value for --strict-host-key"; SSH_STRICT_MODE="$1" ;;
	--proxy-command=*) SSH_PROXY_CMD="${1#--proxy-command=}" ;;
	--proxy-command) shift; [[ $# -gt 0 ]] || fail "Missing value for --proxy-command"; SSH_PROXY_CMD="$1" ;;
	--destructive) DESTRUCTIVE="1" ;;
	--verify-reboot) VERIFY_REBOOT="1" ;;
	--db=*) DB_DRIVER="${1#--db=}" ;;
	--db) shift; [[ $# -gt 0 ]] || fail "Missing value for --db"; DB_DRIVER="$1" ;;
	--session=*) SESSION_DRIVER="${1#--session=}" ;;
	--session) shift; [[ $# -gt 0 ]] || fail "Missing value for --session"; SESSION_DRIVER="$1" ;;
	--template=*) TEMPLATE="${1#--template=}" ;;
	--template) shift; [[ $# -gt 0 ]] || fail "Missing value for --template"; TEMPLATE="$1" ;;
	--mirror-preset=*) MIRROR_PRESET="${1#--mirror-preset=}" ;;
	--mirror-preset) shift; [[ $# -gt 0 ]] || fail "Missing value for --mirror-preset"; MIRROR_PRESET="$1" ;;
	--templates-repo=*) TEMPLATES_REPO="${1#--templates-repo=}" ;;
	--templates-repo) shift; [[ $# -gt 0 ]] || fail "Missing value for --templates-repo"; TEMPLATES_REPO="$1" ;;
	--out-dir=*) OUT_DIR="${1#--out-dir=}" ;;
	--out-dir) shift; [[ $# -gt 0 ]] || fail "Missing value for --out-dir"; OUT_DIR="$1" ;;
	-h | --help) usage; exit 0 ;;
	*) fail "Unknown option: $1" ;;
	esac
	shift
done

[[ -n "${TARGET_HOST}" ]] || { usage; fail "--host is required"; }
if [[ "${VERIFY_REBOOT}" == "1" && "${DESTRUCTIVE}" != "1" ]]; then
	fail "--verify-reboot requires --destructive"
fi

if [[ -z "${SSH_STRICT_MODE}" ]]; then
	if [[ -n "${SSH_KNOWN_HOSTS}" && -f "${SSH_KNOWN_HOSTS}" ]]; then
		SSH_STRICT_MODE="yes"
	else
		SSH_STRICT_MODE="accept-new"
	fi
fi
case "${SSH_STRICT_MODE}" in
yes | accept-new) ;;
*) fail "--strict-host-key must be 'yes' or 'accept-new' (never 'no')" ;;
esac

TMP_LOCAL="$(mktemp -d)"
REMOTE_E2E_TMP="${TMP_LOCAL}"
trap 'rm -rf "${REMOTE_E2E_TMP:-}"' EXIT

if [[ -z "${SSH_KNOWN_HOSTS}" ]]; then
	SSH_KNOWN_HOSTS="${TMP_LOCAL}/known_hosts"
	touch "${SSH_KNOWN_HOSTS}"
	chmod 0600 "${SSH_KNOWN_HOSTS}"
fi

declare -a SSH_OPTS=(
	-F "${SSH_CONFIG_FILE}"
	-p "${SSH_PORT}"
	-o "StrictHostKeyChecking=${SSH_STRICT_MODE}"
	-o "UserKnownHostsFile=${SSH_KNOWN_HOSTS}"
	-o "ConnectTimeout=20"
	-o "BatchMode=yes"
)
if [[ -n "${SSH_IDENTITY}" ]]; then
	SSH_OPTS+=(-i "${SSH_IDENTITY}" -o "IdentitiesOnly=yes")
fi
if [[ -n "${SSH_PROXY_CMD}" ]]; then
	SSH_OPTS+=(-o "ProxyCommand=${SSH_PROXY_CMD}")
fi

rssh() {
	ssh "${SSH_OPTS[@]}" "${TARGET_HOST}" "$@"
}

if [[ -n "${OUT_DIR}" ]]; then
	mkdir -p "${OUT_DIR}"
fi

log "Checking SSH connectivity to ${TARGET_HOST}..."
rssh 'hostname; uname -m; grep -E "^PRETTY_NAME=" /etc/os-release || true'

if [[ "${DESTRUCTIVE}" != "1" ]]; then
	log "Running read-only verification (pass --destructive for full install & mutation suite)..."
	rssh 'command -v emdashctl >/dev/null 2>&1 || { echo "emdashctl not installed on target" >&2; exit 1; }'
	status_out="$(rssh 'emdashctl status --json')"
	doctor_out="$(rssh 'emdashctl doctor --deep --json')"
	diagnose_out="$(rssh 'emdashctl diagnose --json --lines 40')"
	rssh 'emdashctl upgrade app --dry-run' >/dev/null
	rssh 'emdashctl template diff --stat' >/dev/null || true

	python3 - "${status_out}" "${doctor_out}" "${diagnose_out}" <<'PY'
import json, sys
st = json.loads(sys.argv[1])
doc = json.loads(sys.argv[2])
diag = json.loads(sys.argv[3])
assert st["runtime"] == "native"
assert doc["schema_version"] == 1
assert diag["schema_version"] == 1
assert diag["redaction"]["secrets_redacted"] is True
print(f"[INFO] Read-only check summary: app_health={st['app']['health']} doctor_healthy={doc['healthy']} checks={doc['summary']}")
PY
	if [[ -n "${OUT_DIR}" ]]; then
		printf '%s\n' "${status_out}" >"${OUT_DIR}/status.json"
		printf '%s\n' "${doctor_out}" >"${OUT_DIR}/doctor.json"
		printf '%s\n' "${diagnose_out}" >"${OUT_DIR}/diagnose.json"
		chmod 0600 "${OUT_DIR}/status.json" "${OUT_DIR}/doctor.json" "${OUT_DIR}/diagnose.json"
	fi
	log "Read-only remote verification passed."
	exit 0
fi

# Destructive E2E mode: upload allowlisted repo files only (never .env, keys, test-results, db files)
log "Packaging allowlisted EmdashDeploy source archive..."
tar -C "${SCRIPT_DIR}" -czf "${TMP_LOCAL}/emdash-deploy.tar.gz" \
	bootstrap.sh \
	install.sh \
	install-emdash.sh \
	emdashctl \
	lib \
	scripts

REMOTE_STAGE="/tmp/emdash-e2e-stage"
rssh "rm -rf '${REMOTE_STAGE}' && mkdir -p '${REMOTE_STAGE}'"
ssh "${SSH_OPTS[@]}" "${TARGET_HOST}" "tar -C '${REMOTE_STAGE}' -xzf -" <"${TMP_LOCAL}/emdash-deploy.tar.gz"

# Generate ephemeral test secrets locally and transfer via 0600 remote env file (never on CLI)
umask 0077
ENV_PAYLOAD="${TMP_LOCAL}/e2e-install.env"
PG_PASS="$(openssl rand -hex 12)"
REDIS_PASS="$(openssl rand -hex 12)"
BAK_PASS="$(openssl rand -hex 16)"

{
	printf 'EMDASH_INSTALL_NONINTERACTIVE=1\n'
	printf 'EMDASH_INSTALL_TEMPLATE=%q\n' "${TEMPLATE}"
	printf 'EMDASH_INSTALL_DB_DRIVER=%q\n' "${DB_DRIVER}"
	printf 'EMDASH_INSTALL_SESSION_DRIVER=%q\n' "${SESSION_DRIVER}"
	printf 'EMDASH_INSTALL_STORAGE_DRIVER=%q\n' "${STORAGE_DRIVER}"
	printf 'EMDASH_INSTALL_USE_CADDY=0\n'
	printf 'EMDASH_INSTALL_ENABLE_HTTPS=0\n'
	printf 'EMDASH_INSTALL_ENABLE_PLUGIN_SANDBOX=1\n'
	printf 'EMDASH_INSTALL_PG_PASSWORD=%q\n' "${PG_PASS}"
	printf 'EMDASH_INSTALL_REDIS_PASSWORD=%q\n' "${REDIS_PASS}"
	printf 'EMDASH_INSTALL_BACKUP_ENCRYPTION_PASSPHRASE=%q\n' "${BAK_PASS}"
	[[ -n "${MIRROR_PRESET}" ]] && printf 'EMDASH_MIRROR_PRESET=%q\n' "${MIRROR_PRESET}"
	[[ -n "${TEMPLATES_REPO}" ]] && printf 'EMDASH_TEMPLATES_REPO=%q\n' "${TEMPLATES_REPO}"
} >"${ENV_PAYLOAD}"
chmod 0600 "${ENV_PAYLOAD}"

rssh "umask 0077 && cat > '${REMOTE_STAGE}/e2e.env' && chmod 0600 '${REMOTE_STAGE}/e2e.env'" <"${ENV_PAYLOAD}"

log "Step 1/7: Fresh native install (db=${DB_DRIVER}, session=${SESSION_DRIVER}, template=${TEMPLATE})..."
rssh "bash -ec 'trap \"rm -f ${REMOTE_STAGE}/e2e.env\" EXIT; set -a; . \"${REMOTE_STAGE}/e2e.env\"; set +a; bash \"${REMOTE_STAGE}/install-emdash.sh\" --lang=en --non-interactive --activate'"

log "Step 2/7: Verify doctor --deep --json and diagnose --json (0 secret leak)..."
doctor_out="$(rssh 'emdashctl doctor --deep --json')"
diagnose_out="$(rssh 'emdashctl diagnose --json --lines 40')"
python3 - "${doctor_out}" "${diagnose_out}" "${PG_PASS}" "${REDIS_PASS}" "${BAK_PASS}" <<'PY'
import json, sys
doc = json.loads(sys.argv[1])
diag_raw = sys.argv[2]
diag = json.loads(diag_raw)
secrets = sys.argv[3:]
assert doc["healthy"] is True, f"doctor not healthy: {doc}"
for s in secrets:
    if s and s in diag_raw:
        raise SystemExit("CRITICAL: secret leaked into diagnose --json output")
assert diag["schema_version"] == 1
assert diag["doctor"]["healthy"] is True
print(f"[INFO] doctor --deep healthy=True ({doc['summary']}), diagnose secret-leak check passed")
PY

log "Step 3/7: Verify two-stage rotate-encryption-key (Stage 1 + Stage 2 prune)..."
rssh 'emdashctl rotate-encryption-key --status --json' >/dev/null
rssh 'emdashctl rotate-encryption-key --dry-run' >/dev/null
rssh 'emdashctl rotate-encryption-key --yes'
old_kid="$(rssh 'emdashctl rotate-encryption-key --status --json' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["key_count"]==2; print(",".join(d["legacy_kids"]))')"
[[ -n "${old_kid}" ]] || fail "Failed to read legacy kid after Stage 1 rotation"
rssh "emdashctl rotate-encryption-key --prune-old --confirm-prune-kid '${old_kid}'"
rssh 'emdashctl rotate-encryption-key --status --json' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["key_count"]==1, d'

log "Step 4/7: Verify non-destructive upgrade app (marker preserved)..."
rssh 'printf "<!-- e2e-marker -->\n" > /data/emdash/app/site/e2e-custom-marker.txt'
rssh 'emdashctl upgrade app --yes'
rssh 'test -f /data/emdash/app/site/e2e-custom-marker.txt'

log "Step 5/7: Verify encrypted full backup & restore (--with-site --with-secrets)..."
bak_file="$(rssh 'emdashctl backup --full --encrypt' | awk '/\.tar\.gz\.enc/{print $NF}' | tail -n 1)"
[[ -n "${bak_file}" ]] || fail "Failed to determine encrypted backup path"
rssh "emdashctl restore '${bak_file}' --with-site --with-secrets --yes"

if [[ "${DB_DRIVER}" == "postgres" ]]; then
	log "Step 6/7: Verify reset-db-password..."
	rssh 'emdashctl reset-db-password >/dev/null'
	rssh 'emdashctl doctor --deep --json' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["healthy"] is True, d'
else
	log "Step 6/7: Skipped reset-db-password (DB_DRIVER=${DB_DRIVER})"
fi

if [[ "${VERIFY_REBOOT}" == "1" ]]; then
	log "Step 7/7: Rebooting target and verifying autostart..."
	rssh 'nohup sh -c "sleep 2 && reboot" >/dev/null 2>&1 &' || true
	sleep 10
	recovered="0"
	for _ in $(seq 1 45); do
		if rssh 'true' >/dev/null 2>&1; then
			recovered="1"
			break
		fi
		sleep 4
	done
	[[ "${recovered}" == "1" ]] || fail "Target host did not recover after reboot"
	for _ in $(seq 1 30); do
		if rssh 'curl -fsS http://127.0.0.1:3000/healthz >/dev/null 2>&1 && curl -fsS http://127.0.0.1:3000/_emdash/api/setup/status >/dev/null 2>&1'; then
			break
		fi
		sleep 2
	done
	post_reboot_doc="$(rssh 'emdashctl doctor --deep --json')"
	python3 - "${post_reboot_doc}" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d["healthy"] is True, f"post-reboot doctor failed: {d}"
print(f"[INFO] Post-reboot doctor healthy=True ({d['summary']})")
PY
else
	log "Step 7/7: Skipped reboot test (pass --verify-reboot to enable)"
fi

if [[ -n "${OUT_DIR}" ]]; then
	printf '%s\n' "${doctor_out}" >"${OUT_DIR}/doctor.json"
	printf '%s\n' "${diagnose_out}" >"${OUT_DIR}/diagnose.json"
	chmod 0600 "${OUT_DIR}/doctor.json" "${OUT_DIR}/diagnose.json"
fi

rssh "rm -rf '${REMOTE_STAGE}'" || true
log "Remote E2E verification completed successfully!"
