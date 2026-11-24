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
DEEP_CHECKS="0"
VERIFY_IDEMPOTENT="0"
VERIFY_CHAOS_RESTORE="0"
USE_CADDY="0"
DOMAIN_VALUE=""
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
  --deep-checks                Enable deep fault-injection checks (perm failure, DB kid prune block, Caddy log canary)
  --verify-idempotent          Re-run installer in preserve mode and verify user code/secrets remain untouched
  --verify-chaos-restore       Mutate site & DB after backup, then verify restore recovers clean state
  --verify-reboot              Reboot target after tests and verify autostart (requires --destructive)
  --use-caddy                  Enable native Caddy HTTP reverse proxy (USE_CADDY=1, ENABLE_HTTPS=0)
  --domain <host>              Domain/IP for Caddy mode (defaults to target host IP)
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
	--deep-checks) DEEP_CHECKS="1" ;;
	--verify-idempotent) VERIFY_IDEMPOTENT="1" ;;
	--verify-chaos-restore) VERIFY_CHAOS_RESTORE="1" ;;
	--verify-reboot) VERIFY_REBOOT="1" ;;
	--use-caddy) USE_CADDY="1" ;;
	--domain=*) DOMAIN_VALUE="${1#--domain=}" ;;
	--domain) shift; [[ $# -gt 0 ]] || fail "Missing value for --domain"; DOMAIN_VALUE="$1" ;;
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
if [[ "${VERIFY_REBOOT}" == "1" || "${DEEP_CHECKS}" == "1" || "${VERIFY_IDEMPOTENT}" == "1" || "${VERIFY_CHAOS_RESTORE}" == "1" ]] && [[ "${DESTRUCTIVE}" != "1" ]]; then
	fail "--deep-checks / --verify-idempotent / --verify-chaos-restore / --verify-reboot require --destructive"
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
	-o "ServerAliveInterval=15"
	-o "ServerAliveCountMax=6"
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

if [[ "${USE_CADDY}" == "1" && -z "${DOMAIN_VALUE}" ]]; then
	DOMAIN_VALUE="${TARGET_HOST#*@}"
fi

{
	printf 'EMDASH_INSTALL_NONINTERACTIVE=1\n'
	printf 'EMDASH_INSTALL_TEMPLATE=%q\n' "${TEMPLATE}"
	printf 'EMDASH_INSTALL_DB_DRIVER=%q\n' "${DB_DRIVER}"
	printf 'EMDASH_INSTALL_SESSION_DRIVER=%q\n' "${SESSION_DRIVER}"
	printf 'EMDASH_INSTALL_STORAGE_DRIVER=%q\n' "${STORAGE_DRIVER}"
	printf 'EMDASH_INSTALL_USE_CADDY=%q\n' "${USE_CADDY}"
	printf 'EMDASH_INSTALL_ENABLE_HTTPS=0\n'
	[[ -n "${DOMAIN_VALUE}" ]] && printf 'EMDASH_INSTALL_DOMAIN=%q\n' "${DOMAIN_VALUE}"
	printf 'EMDASH_INSTALL_ENABLE_PLUGIN_SANDBOX=1\n'
	printf 'EMDASH_INSTALL_PG_PASSWORD=%q\n' "${PG_PASS}"
	printf 'EMDASH_INSTALL_REDIS_PASSWORD=%q\n' "${REDIS_PASS}"
	printf 'EMDASH_INSTALL_BACKUP_ENCRYPTION_PASSPHRASE=%q\n' "${BAK_PASS}"
	[[ -n "${MIRROR_PRESET}" ]] && printf 'EMDASH_MIRROR_PRESET=%q\n' "${MIRROR_PRESET}"
	[[ -n "${TEMPLATES_REPO}" ]] && printf 'EMDASH_TEMPLATES_REPO=%q\n' "${TEMPLATES_REPO}"
} >"${ENV_PAYLOAD}"
chmod 0600 "${ENV_PAYLOAD}"

rssh "umask 0077 && cat > '${REMOTE_STAGE}/e2e.env' && chmod 0600 '${REMOTE_STAGE}/e2e.env'" <"${ENV_PAYLOAD}"

log "Step 1/7: Fresh native install (db=${DB_DRIVER}, session=${SESSION_DRIVER}, template=${TEMPLATE}, caddy=${USE_CADDY})..."
rssh "bash -ec 'set -a; . \"${REMOTE_STAGE}/e2e.env\"; set +a; bash \"${REMOTE_STAGE}/install-emdash.sh\" --lang=en --non-interactive --activate'"

if [[ "${USE_CADDY}" == "1" ]]; then
	log "Verifying Caddy HTTP reverse proxy (:80, Host: ${DOMAIN_VALUE})..."
	rssh "curl -fsS --max-time 10 -H 'Host: ${DOMAIN_VALUE}' http://127.0.0.1/healthz | grep -qx 'OK' && curl -fsS --max-time 10 -H 'Host: ${DOMAIN_VALUE}' http://127.0.0.1/_emdash/api/setup/status >/dev/null"
	if [[ "${DEEP_CHECKS}" == "1" ]]; then
		log "Sending canary HTTP request through Caddy to verify live log redaction..."
		rssh "curl -fsS --max-time 10 -H 'Host: ${DOMAIN_VALUE}' -H 'Authorization: Bearer E2ECaddyBearerCanary_9988' -H 'Cookie: emdash_sid=E2ECaddyCookieCanary_7766' 'http://127.0.0.1/healthz?token=E2ECaddyQueryCanary_5544' >/dev/null; sleep 1"
	fi
fi

log "Step 2/7: Verify doctor --deep --json and diagnose --json (0 secret leak)..."
doctor_out="$(rssh 'emdashctl doctor --deep --json')"
diagnose_out="$(rssh 'emdashctl diagnose --json --lines 50')"
python3 - "${doctor_out}" "${diagnose_out}" "${DB_DRIVER}" "${USE_CADDY}" "${DEEP_CHECKS}" "${PG_PASS}" "${REDIS_PASS}" "${BAK_PASS}" <<'PY'
import json, sys
doc = json.loads(sys.argv[1])
diag_raw = sys.argv[2]
db_driver, use_caddy, deep_checks = sys.argv[3], sys.argv[4], sys.argv[5]
secrets = sys.argv[6:]
assert doc["healthy"] is True, f"doctor not healthy: {doc}"
checks = {c["name"]: c for c in doc["checks"]}
assert checks["permissions"]["status"] == "ok", checks.get("permissions")
if db_driver == "sqlite":
    assert "upstream:collections" in checks, f"missing upstream:collections in {list(checks)}"
    assert checks["upstream:collections"]["status"] != "fail", checks["upstream:collections"]
    assert "upstream:users" in checks, f"missing upstream:users in {list(checks)}"
if use_caddy == "1":
    assert checks["caddy"]["status"] == "ok", checks.get("caddy")
for s in secrets:
    if s and s in diag_raw:
        raise SystemExit("CRITICAL: secret leaked into diagnose --json output")
if use_caddy == "1" and deep_checks == "1":
    for canary in ("E2ECaddyBearerCanary_9988", "E2ECaddyCookieCanary_7766", "E2ECaddyQueryCanary_5544"):
        if canary in diag_raw:
            raise SystemExit(f"CRITICAL: Caddy HTTP canary leaked into diagnose --json: {canary}")
diag = json.loads(diag_raw)
assert diag["schema_version"] == 1
assert diag["doctor"]["healthy"] is True
print(f"[INFO] doctor --deep healthy=True ({doc['summary']}), diagnose secret-leak check passed")
PY

if [[ "${DEEP_CHECKS}" == "1" ]]; then
	log "Deep checks: low-mem swap, env permission fault injection, and diagnose symlink guard..."
	rssh 'bash -ec '\''
		mem_mb="$(awk "/^MemTotal:/{print int(\$2/1024)}" /proc/meminfo)"
		if (( mem_mb < 2200 )); then
			swapon --noheadings --show=NAME | grep -qx "/swapfile.emdash" || { echo "Expected /swapfile.emdash on low-memory host (${mem_mb} MiB)" >&2; exit 1; }
			echo "[INFO] Low-memory auto swap verified (${mem_mb} MiB RAM -> /swapfile.emdash active)"
		fi

		# Fault injection: chmod 0644 emdash.env must trigger doctor permissions fail
		chmod 0644 /etc/emdash/emdash.env
		trap "chmod 0640 /etc/emdash/emdash.env" EXIT
		bad_doc="$(emdashctl doctor --deep --json)"
		python3 - "${bad_doc}" <<"PY"
import json, sys
d = json.loads(sys.argv[1])
checks = {c["name"]: c for c in d["checks"]}
assert d["healthy"] is False, "expected healthy=False on 0644 emdash.env"
assert checks["permissions"]["status"] == "fail", checks.get("permissions")
PY
		chmod 0640 /etc/emdash/emdash.env
		trap - EXIT

		# Symlink --out guard
		ln -sf /tmp/e2e-symlink-victim /tmp/e2e-diag-symlink.json
		if emdashctl diagnose --json --out /tmp/e2e-diag-symlink.json >/dev/null 2>&1; then
			echo "ERROR: diagnose --out should reject symlink" >&2
			exit 1
		fi
		rm -f /tmp/e2e-diag-symlink.json
		emdashctl diagnose --json --lines 20 --out /tmp/e2e-diag-out.json >/dev/null
		test "$(stat -c %a /tmp/e2e-diag-out.json)" = "600"
		rm -f /tmp/e2e-diag-out.json
		echo "[INFO] Deep fault-injection checks passed (permissions fail/recover + symlink guard + 0600 atomic out)"
	'\'''
fi

if [[ "${VERIFY_IDEMPOTENT}" == "1" ]]; then
	log "Verifying installer idempotency (preserve mode must keep custom files, astro.config.mjs, and encryption key)..."
	kid_before="$(rssh 'emdashctl rotate-encryption-key --status --json' | python3 -c 'import json,sys; print(json.load(sys.stdin)["primary_kid"])')"
	rssh 'printf "preserve-marker-ok\n" > /data/emdash/app/site/e2e-preserve-marker.txt && printf "\n// e2e-preserve-comment\n" >> /data/emdash/app/site/astro.config.mjs'
	rssh "bash -ec 'set -a; . \"${REMOTE_STAGE}/e2e.env\"; set +a; bash \"${REMOTE_STAGE}/install-emdash.sh\" --lang=en --non-interactive --activate'"
	rssh 'test -f /data/emdash/app/site/e2e-preserve-marker.txt && grep -Fq "e2e-preserve-comment" /data/emdash/app/site/astro.config.mjs'
	kid_after="$(rssh 'emdashctl rotate-encryption-key --status --json' | python3 -c 'import json,sys; print(json.load(sys.stdin)["primary_kid"])')"
	[[ "${kid_before}" == "${kid_after}" ]] || fail "Idempotent rerun unexpectedly changed encryption_key_kid (${kid_before} -> ${kid_after})"
	rssh 'emdashctl template diff --stat >/dev/null'
	rssh 'emdashctl doctor --deep --json' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["healthy"] is True, d'
	log "Idempotency & preserve-mode verification passed."
fi

# Clean up ephemeral remote install env file now that install/idempotency steps are done
rssh "rm -f '${REMOTE_STAGE}/e2e.env'" || true

log "Step 3/7: Verify two-stage rotate-encryption-key (Stage 1 + DB kid guard + Stage 2 prune)..."
orig_kid="$(rssh 'emdashctl rotate-encryption-key --status --json' | python3 -c 'import json,sys; print(json.load(sys.stdin)["primary_kid"])')"
rssh 'emdashctl rotate-encryption-key --dry-run' >/dev/null

if [[ "${DEEP_CHECKS}" == "1" ]]; then
	log "Injecting real encrypted-envelope record referencing kid=${orig_kid} to test prune guard..."
	if [[ "${DB_DRIVER}" == "sqlite" ]]; then
		rssh "python3 - '${orig_kid}' <<'PY'
import json, sqlite3, sys
kid = sys.argv[1]
conn = sqlite3.connect('/data/emdash/data/sqlite/data.db')
conn.execute('CREATE TABLE IF NOT EXISTS _emdash_options (key TEXT PRIMARY KEY, value TEXT)')
env = {'apiKey': {'\$emdash': 'encrypted', 'v': 1, 'kid': kid, 'iv': 'AAAAAAAAAAAAAAAA', 'ciphertext': 'BBBBBBBBBBBBBBBBBBBBBB'}}
conn.execute('INSERT OR REPLACE INTO _emdash_options (key, value) VALUES (?, ?)', ('_e2e_rotate_canary', json.dumps(env)))
conn.commit()
conn.close()
PY"
	else
		rssh "bash -ec 'set -a; . /etc/emdash/emdash.env; set +a; PGPASSWORD=\"\${PG_DB_PASSWORD}\" psql -h \"\${POSTGRES_HOST}\" -p \"\${POSTGRES_PORT}\" -U \"\${PG_DB_USER}\" -d \"\${PG_DB_NAME}\" -c \"CREATE TABLE IF NOT EXISTS _emdash_options (key TEXT PRIMARY KEY, value TEXT); INSERT INTO _emdash_options (key, value) VALUES ('\''_e2e_rotate_canary'\'', '\''{\\\"apiKey\\\":{\\\"\\\$emdash\\\":\\\"encrypted\\\",\\\"v\\\":1,\\\"kid\\\":\\\"${orig_kid}\\\",\\\"iv\\\":\\\"AAAAAAAAAAAAAAAA\\\",\\\"ciphertext\\\":\\\"BBBBBBBBBBBBBBBBBBBBBB\\\"}}'\'') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;\" >/dev/null'"
	fi
fi

rssh 'emdashctl rotate-encryption-key --yes'
old_kid="$(rssh 'emdashctl rotate-encryption-key --status --json' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["key_count"]==2; print(",".join(d["legacy_kids"]))')"
[[ -n "${old_kid}" ]] || fail "Failed to read legacy kid after Stage 1 rotation"

if [[ "${DEEP_CHECKS}" == "1" ]]; then
	log "Asserting Stage 2 --prune-old BLOCKS while DB still holds encrypted record under kid=${old_kid}..."
	if rssh "emdashctl rotate-encryption-key --prune-old --confirm-prune-kid '${old_kid}' </dev/null >/dev/null 2>&1"; then
		fail "CRITICAL: --prune-old succeeded even though DB still referenced legacy kid=${old_kid}"
	fi
	log "Prune guard correctly blocked! Clearing test encrypted record and retrying Stage 2 prune..."
	if [[ "${DB_DRIVER}" == "sqlite" ]]; then
		rssh "python3 -c \"import sqlite3; c=sqlite3.connect('/data/emdash/data/sqlite/data.db'); c.execute('DELETE FROM _emdash_options WHERE key=?', ('_e2e_rotate_canary',)); c.commit(); c.close()\""
	else
		rssh "bash -ec 'set -a; . /etc/emdash/emdash.env; set +a; PGPASSWORD=\"\${PG_DB_PASSWORD}\" psql -h \"\${POSTGRES_HOST}\" -p \"\${POSTGRES_PORT}\" -U \"\${PG_DB_USER}\" -d \"\${PG_DB_NAME}\" -c \"DELETE FROM _emdash_options WHERE key='\''_e2e_rotate_canary'\'';\" >/dev/null'"
	fi
fi

rssh "emdashctl rotate-encryption-key --prune-old --confirm-prune-kid '${old_kid}' </dev/null"
rssh 'emdashctl rotate-encryption-key --status --json' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["key_count"]==1, d'

log "Step 4/7: Verify non-destructive upgrade app (marker preserved)..."
rssh 'printf "<!-- e2e-marker -->\n" > /data/emdash/app/site/e2e-custom-marker.txt'
rssh 'emdashctl upgrade app --yes'
rssh 'test -f /data/emdash/app/site/e2e-custom-marker.txt'

log "Step 5/7: Verify encrypted full backup & restore (--with-site --with-secrets)..."
if [[ "${VERIFY_CHAOS_RESTORE}" == "1" ]]; then
	rssh 'printf "gold-state-content\n" > /data/emdash/app/site/e2e-backup-gold.txt'
	if [[ "${DB_DRIVER}" == "sqlite" ]]; then
		rssh "python3 -c \"import sqlite3; c=sqlite3.connect('/data/emdash/data/sqlite/data.db'); c.execute('CREATE TABLE IF NOT EXISTS _e2e_chaos (v TEXT)'); c.execute('DELETE FROM _e2e_chaos'); c.execute('INSERT INTO _e2e_chaos VALUES (?)', ('gold',)); c.commit(); c.close()\""
	else
		rssh "bash -ec 'set -a; . /etc/emdash/emdash.env; set +a; PGPASSWORD=\"\${PG_DB_PASSWORD}\" psql -h \"\${POSTGRES_HOST}\" -p \"\${POSTGRES_PORT}\" -U \"\${PG_DB_USER}\" -d \"\${PG_DB_NAME}\" -c \"CREATE TABLE IF NOT EXISTS _e2e_chaos (v TEXT); TRUNCATE _e2e_chaos; INSERT INTO _e2e_chaos VALUES ('\''gold'\'');\" >/dev/null'"
	fi
fi

bak_file="$(rssh 'emdashctl backup --full --encrypt' | awk '/\.tar\.gz\.enc/{print $NF}' | tail -n 1)"
[[ -n "${bak_file}" ]] || fail "Failed to determine encrypted backup path"

if [[ "${VERIFY_CHAOS_RESTORE}" == "1" ]]; then
	log "Chaos test: deleting gold site file and corrupting DB row before restore..."
	rssh 'rm -f /data/emdash/app/site/e2e-backup-gold.txt'
	if [[ "${DB_DRIVER}" == "sqlite" ]]; then
		rssh "python3 -c \"import sqlite3; c=sqlite3.connect('/data/emdash/data/sqlite/data.db'); c.execute('UPDATE _e2e_chaos SET v=?', ('corrupted',)); c.commit(); c.close()\""
	else
		rssh "bash -ec 'set -a; . /etc/emdash/emdash.env; set +a; PGPASSWORD=\"\${PG_DB_PASSWORD}\" psql -h \"\${POSTGRES_HOST}\" -p \"\${POSTGRES_PORT}\" -U \"\${PG_DB_USER}\" -d \"\${PG_DB_NAME}\" -c \"UPDATE _e2e_chaos SET v='\''corrupted'\'';\" >/dev/null'"
	fi
fi

rssh "emdashctl restore '${bak_file}' --with-site --with-secrets --yes"

if [[ "${VERIFY_CHAOS_RESTORE}" == "1" ]]; then
	rssh 'grep -qx "gold-state-content" /data/emdash/app/site/e2e-backup-gold.txt'
	if [[ "${DB_DRIVER}" == "sqlite" ]]; then
		rssh "python3 -c \"import sqlite3; c=sqlite3.connect('/data/emdash/data/sqlite/data.db'); v=c.execute('SELECT v FROM _e2e_chaos').fetchone()[0]; assert v=='gold', v; c.execute('DROP TABLE _e2e_chaos'); c.commit(); c.close()\""
	else
		rssh "bash -ec 'set -a; . /etc/emdash/emdash.env; set +a; v=\$(PGPASSWORD=\"\${PG_DB_PASSWORD}\" psql -h \"\${POSTGRES_HOST}\" -p \"\${POSTGRES_PORT}\" -U \"\${PG_DB_USER}\" -d \"\${PG_DB_NAME}\" -tAc \"SELECT v FROM _e2e_chaos;\"); test \"\$v\" = \"gold\"; PGPASSWORD=\"\${PG_DB_PASSWORD}\" psql -h \"\${POSTGRES_HOST}\" -p \"\${POSTGRES_PORT}\" -U \"\${PG_DB_USER}\" -d \"\${PG_DB_NAME}\" -c \"DROP TABLE _e2e_chaos;\" >/dev/null'"
	fi
	log "Chaos restore verified: both deleted site file and corrupted DB row fully rolled back to gold backup."
fi

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
