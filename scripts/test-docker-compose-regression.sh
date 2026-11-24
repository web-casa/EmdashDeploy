#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "${SCRIPT_DIR}/docker/entrypoint.sh" "${SCRIPT_DIR}/docker/backup.sh"

# Verify compose.yml does NOT mix build: with prebuilt image:
if grep -Eq '^\s+build:' "${SCRIPT_DIR}/docker/compose.yml"; then
	printf '[ERROR] docker/compose.yml must not declare build: alongside prebuilt GHCR image:\n' >&2
	exit 1
fi

# Verify docker/backup.sh help works cleanly
bash "${SCRIPT_DIR}/docker/backup.sh" --help >/dev/null

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
