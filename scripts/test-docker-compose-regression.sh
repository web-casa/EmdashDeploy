#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "${SCRIPT_DIR}/docker/entrypoint.sh" "${SCRIPT_DIR}/docker/backup.sh" "${SCRIPT_DIR}/docker/restore.sh"

# Verify compose.yml does NOT mix build: with prebuilt image:
if grep -Eq '^\s+build:' "${SCRIPT_DIR}/docker/compose.yml"; then
	printf '[ERROR] docker/compose.yml must not declare build: alongside prebuilt GHCR image:\n' >&2
	exit 1
fi

# Verify docker/backup.sh, docker/restore.sh, and scripts/migrate-runtime.sh contracts
bash "${SCRIPT_DIR}/docker/backup.sh" --help >/dev/null
bash "${SCRIPT_DIR}/docker/restore.sh" --help >/dev/null
bash "${SCRIPT_DIR}/scripts/migrate-runtime.sh" --help >/dev/null

# Verify backup.sh preserves caller-supplied BACKUP_ENCRYPTION_PASSPHRASE before sourcing .env
grep -Fq 'CALLER_PASSPHRASE="${BACKUP_ENCRYPTION_PASSPHRASE:-}"' "${SCRIPT_DIR}/docker/backup.sh" || {
	printf '[ERROR] docker/backup.sh must preserve caller BACKUP_ENCRYPTION_PASSPHRASE\n' >&2
	exit 1
}

# Verify restore.sh filters extraction to meta/ and data/ (ignores upstream site/ symlinks),
# waits for PostgreSQL readiness, and starts valkey when SESSION_DRIVER=redis
grep -Fq 'norm.startswith("meta/")' "${SCRIPT_DIR}/docker/restore.sh" || {
	printf '[ERROR] docker/restore.sh must restrict extraction to meta/ and data/\n' >&2
	exit 1
}
grep -Fq 'pg_ready="1"' "${SCRIPT_DIR}/docker/restore.sh" || {
	printf '[ERROR] docker/restore.sh must wait for PostgreSQL readiness before createdb\n' >&2
	exit 1
}
grep -Fq 'up -d valkey' "${SCRIPT_DIR}/docker/restore.sh" || {
	printf '[ERROR] docker/restore.sh must start valkey when SESSION_DRIVER=redis\n' >&2
	exit 1
}
grep -Fq '1.6.0-hi.5-' "${SCRIPT_DIR}/scripts/migrate-runtime.sh" || {
	printf '[ERROR] scripts/migrate-runtime.sh must default to 1.6.0-hi.5 image tags\n' >&2
	exit 1
}

# Validate compose YAML combinations when docker compose is available
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
	# 1. Default SQLite single-container mode must validate with zero required env vars
	docker compose -f "${SCRIPT_DIR}/docker/compose.yml" config -q

	# 2. Default mode must NOT bind host 80/443
	if docker compose -f "${SCRIPT_DIR}/docker/compose.yml" config | grep -Eq 'published:\s*"?(80|443)"?$'; then
		printf '[ERROR] Default docker/compose.yml unexpectedly binds host port 80 or 443\n' >&2
		exit 1
	fi

	# 3. Local build overlay must validate cleanly and use local image tag
	docker compose -f "${SCRIPT_DIR}/docker/compose.yml" -f "${SCRIPT_DIR}/docker/compose.build.yml" config -q
	if ! docker compose -f "${SCRIPT_DIR}/docker/compose.yml" -f "${SCRIPT_DIR}/docker/compose.build.yml" config | grep -Eq 'image:\s*emdash-deploy:local-'; then
		printf '[ERROR] compose.build.yml must use independent local image tag\n' >&2
		exit 1
	fi

	# 4. Custom site overlay must validate cleanly
	local_custom_dir="$(mktemp -d)"
	trap 'rm -rf "${local_custom_dir}"' EXIT
	CUSTOM_SITE_DIR="${local_custom_dir}" \
		docker compose -f "${SCRIPT_DIR}/docker/compose.yml" -f "${SCRIPT_DIR}/docker/compose.custom-site.yml" config -q

	# 5. Profiles: postgres + valkey
	PG_DB_PASSWORD="test-pg-pass" REDIS_PASSWORD="test-redis-pass" \
		docker compose -f "${SCRIPT_DIR}/docker/compose.yml" --profile postgres --profile valkey config -q

	# 6. Profile: caddy
	docker compose -f "${SCRIPT_DIR}/docker/compose.yml" --profile caddy config -q

	# 7. External reverse-proxy network overlay (zero host ports)
	docker compose -f "${SCRIPT_DIR}/docker/compose.yml" -f "${SCRIPT_DIR}/docker/compose.proxy-net.yml" config -q
	if docker compose -f "${SCRIPT_DIR}/docker/compose.yml" -f "${SCRIPT_DIR}/docker/compose.proxy-net.yml" config | grep -Eq 'published:\s*"?3000"?$'; then
		printf '[ERROR] compose.proxy-net.yml should reset published host ports\n' >&2
		exit 1
	fi
else
	printf '[WARN] docker compose not available; skipped live compose YAML validation\n' >&2
fi

printf '[INFO] docker compose regression checks passed\n'
