#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/emdashctl"

assert_contains() {
	local file="$1" expected="$2"
	if ! grep -Fq "${expected}" "${file}"; then
		printf '[ERROR] expected fragment not found in %s: %s\n' "${file}" "${expected}" >&2
		cat "${file}" >&2
		exit 1
	fi
}

test_parse_migrate_status_json_handles_prefix_lines() {
	local out parsed
	out=$'Migration target: sqlite /data/emdash/data/sqlite/data.db\nTarget fingerprint: abc123\n{"target":{"kind":"sqlite"},"knownApplied":["001"],"pending":["099_new"],"unknownApplied":[],"executed":[]}'
	parsed="$(printf '%s\n' "${out}" | parse_migrate_status_json)"
	python3 - "${parsed}" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d["valid"] is True
assert d["pending_count"] == 1
assert d["unknown_applied_count"] == 0
PY
	printf '[INFO] upgrade regression: parse_migrate_status_json passed\n'
}

test_apply_dependency_upgrade_preserves_user_files() {
	local tmpdir plan_json
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "${tmpdir}"' RETURN

	SITE_DIR="${tmpdir}/site"
	mkdir -p "${SITE_DIR}/src/pages"
	cat >"${SITE_DIR}/package.json" <<'EOF'
{
  "name": "my-custom-blog",
  "packageManager": "pnpm@11.9.0",
  "dependencies": {
    "astro": "^7.3.2",
    "emdash": "^1.5.0",
    "@emdash-cms/sandbox-workerd": "^0.9.5",
    "my-custom-pkg": "^1.0.0"
  }
}
EOF
	printf 'export const custom = "user-owned";\n' >"${SITE_DIR}/src/pages/custom.ts"
	printf '// user customized astro config\n' >"${SITE_DIR}/astro.config.mjs"

	plan_json='{"changes":[{"section":"dependencies","name":"emdash","from":"^1.5.0","to":"^1.6.0","changed":true},{"section":"dependencies","name":"@emdash-cms/sandbox-workerd","from":"^0.9.5","to":"^0.9.8","changed":true}]}'
	apply_emdash_dependency_upgrade "${plan_json}"

	assert_contains "${SITE_DIR}/package.json" '"emdash": "^1.6.0"'
	assert_contains "${SITE_DIR}/package.json" '"@emdash-cms/sandbox-workerd": "^0.9.8"'
	assert_contains "${SITE_DIR}/package.json" '"my-custom-pkg": "^1.0.0"'
	assert_contains "${SITE_DIR}/package.json" '"packageManager": "pnpm@11.9.0"'
	assert_contains "${SITE_DIR}/src/pages/custom.ts" 'user-owned'
	assert_contains "${SITE_DIR}/astro.config.mjs" 'user customized astro config'

	printf '[INFO] upgrade regression: dependency upgrade preserves user code passed\n'
	trap - RETURN
	rm -rf "${tmpdir}"
}

test_migration_gate_rejects_unknown_applied() {
	probe_emdash_migrations() {
		printf '{"supported":true,"valid":true,"exit_code":3,"pending_count":0,"unknown_applied_count":2,"known_applied_count":97}\n'
	}
	if run_upgrade_migration_gate 1 >/dev/null 2>&1; then
		printf '[ERROR] migration gate unexpectedly passed with unknownApplied > 0\n' >&2
		exit 1
	fi
	printf '[INFO] upgrade regression: migration gate rejects unknownApplied passed\n'
}

test_migration_gate_requires_yes_on_legacy_cli() {
	probe_emdash_migrations() {
		printf '{"supported":false,"reason":"emdash migrate CLI unavailable"}\n'
	}
	if run_upgrade_migration_gate 0 >/dev/null 2>&1; then
		printf '[ERROR] migration gate unexpectedly allowed legacy CLI without --yes\n' >&2
		exit 1
	fi
	run_upgrade_migration_gate 1 >/dev/null 2>&1
	printf '[INFO] upgrade regression: migration gate legacy CLI guard passed\n'
}

test_upgrade_rollback_respects_post_migration_boundary() {
	local tmpdir rollback_dir
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "${tmpdir}"' RETURN

	ROOT_DIR="${tmpdir}/emdash"
	SITE_DIR="${ROOT_DIR}/app/site"
	SCRIPTS_DIR="${ROOT_DIR}/scripts"
	TMP_DIR="${ROOT_DIR}/tmp"
	BACKUP_DIR="${ROOT_DIR}/backups"
	APP_ENV_FILE="${ROOT_DIR}/etc/emdash.env"
	APP_SYSTEMD_SERVICE="emdash-app"
	APP_SYSTEMD_UNIT="${ROOT_DIR}/etc/emdash-app.service"
	APP_BUILD_SCRIPT="${SCRIPTS_DIR}/emdash-build.sh"
	APP_START_SCRIPT="${SCRIPTS_DIR}/emdash-start.sh"
	APP_RUN_USER="$(id -un)"
	APP_RUN_GROUP="$(id -gn)"

	mkdir -p "${SITE_DIR}/src" "${SCRIPTS_DIR}" "${ROOT_DIR}/lib" "$(dirname "${APP_ENV_FILE}")" "${BACKUP_DIR}"
	cat >"${SITE_DIR}/package.json" <<'EOF'
{"name":"blog","dependencies":{"emdash":"^1.5.0"}}
EOF
	printf 'custom-v1\n' >"${SITE_DIR}/src/custom.txt"
	printf 'APP_PORT=3000\n' >"${APP_ENV_FILE}"
	printf '[Service]\n' >"${APP_SYSTEMD_UNIT}"
	cat >"${APP_BUILD_SCRIPT}" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
	chmod +x "${APP_BUILD_SCRIPT}"

	# Stub external commands for offline unit test
	systemctl() { return 0; }
	plan_emdash_dependency_upgrade() {
		printf '{"changes":[{"section":"dependencies","name":"emdash","from":"^1.5.0","to":"^1.6.0","changed":true}]}\n'
	}

	# Case 1: failure BEFORE migration must auto-rollback package.json & keep custom.txt
	if ( upgrade_app_command --skip-backup --yes ) >/dev/null 2>&1; then
		printf '[ERROR] upgrade_app_command unexpectedly succeeded on failing build\n' >&2
		exit 1
	fi
	assert_contains "${SITE_DIR}/package.json" '"emdash":"^1.5.0"'
	assert_contains "${SITE_DIR}/src/custom.txt" 'custom-v1'

	# Case 2: failure AFTER migration must NOT silently roll back and must print restore instruction
	cat >"${APP_BUILD_SCRIPT}" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "${APP_BUILD_SCRIPT}"
	run_upgrade_migration_gate() {
		UPGRADE_MIGRATION_ATTEMPTED="1"
		return 1
	}
	create_backup_archive() {
		printf '%s/emdash-backup-mock.tar.gz\n' "${BACKUP_DIR}"
	}
	local stderr_out=""
	stderr_out="$( ( upgrade_app_command --yes ) 2>&1 || true )"
	printf '%s\n' "${stderr_out}" | grep -Fq "emdashctl restore '${BACKUP_DIR}/emdash-backup-mock.tar.gz' --with-site" || {
		printf '[ERROR] expected post-migration restore guidance not printed:\n%s\n' "${stderr_out}" >&2
		exit 1
	}

	printf '[INFO] upgrade regression: pre/post migration rollback boundary passed\n'
	trap - RETURN
	rm -rf "${tmpdir}"
}

main() {
	test_parse_migrate_status_json_handles_prefix_lines
	test_apply_dependency_upgrade_preserves_user_files
	test_migration_gate_rejects_unknown_applied
	test_migration_gate_requires_yes_on_legacy_cli
	test_upgrade_rollback_respects_post_migration_boundary
	printf '[INFO] all upgrade regression checks passed\n'
}

main "$@"
