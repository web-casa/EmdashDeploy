#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "${SCRIPT_DIR}/docker/entrypoint.sh"

# Validate compose YAML combinations when docker compose is available
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
	# 1. Default SQLite single-container mode must validate with zero required env vars
	docker compose -f "${SCRIPT_DIR}/docker/compose.yml" config -q

	# 2. Default mode must NOT bind host 80/443
	if docker compose -f "${SCRIPT_DIR}/docker/compose.yml" config | grep -Eq 'published:\s*"?(80|443)"?$'; then
		printf '[ERROR] Default docker/compose.yml unexpectedly binds host port 80 or 443\n' >&2
		exit 1
	fi

	# 3. Profiles: postgres + valkey
	PG_DB_PASSWORD="test-pg-pass" REDIS_PASSWORD="test-redis-pass" \
		docker compose -f "${SCRIPT_DIR}/docker/compose.yml" --profile postgres --profile valkey config -q

	# 4. Profile: caddy
	docker compose -f "${SCRIPT_DIR}/docker/compose.yml" --profile caddy config -q

	# 5. External reverse-proxy network overlay (zero host ports)
	docker compose -f "${SCRIPT_DIR}/docker/compose.yml" -f "${SCRIPT_DIR}/docker/compose.proxy-net.yml" config -q
	if docker compose -f "${SCRIPT_DIR}/docker/compose.yml" -f "${SCRIPT_DIR}/docker/compose.proxy-net.yml" config | grep -Eq 'published:\s*"?3000"?$'; then
		printf '[ERROR] compose.proxy-net.yml should reset published host ports\n' >&2
		exit 1
	fi
else
	printf '[WARN] docker compose not available; skipped live compose YAML validation\n' >&2
fi

printf '[INFO] docker compose regression checks passed\n'
