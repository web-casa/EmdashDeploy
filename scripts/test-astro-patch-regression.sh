#!/usr/bin/env bash
set -Eeuo pipefail

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
	local file="$1" expected="$2"
	if ! grep -Fq "${expected}" "${file}"; then
		printf '[ERROR] expected fragment not found in %s: %s\n' "${file}" "${expected}" >&2
		cat "${file}" >&2
		exit 1
	fi
}

assert_not_contains() {
	local file="$1" unexpected="$2"
	if grep -Fq "${unexpected}" "${file}"; then
		printf '[ERROR] unexpected fragment found in %s: %s\n' "${file}" "${unexpected}" >&2
		cat "${file}" >&2
		exit 1
	fi
}

test_space_indent_and_sandbox_toggle_idempotent() {
	local tmpdir cfg first_pass second_pass
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "${tmpdir}"' RETURN
	cfg="${tmpdir}/astro.config.mjs"
	first_pass="${tmpdir}/pass1.mjs"
	second_pass="${tmpdir}/pass2.mjs"

	cat >"${cfg}" <<'EOF'
import node from "@astrojs/node";
import react from "@astrojs/react";
import { defineConfig, fontProviders } from "astro/config";
import emdash, { local } from "emdash/astro";
import { sqlite } from "emdash/db";
import { Features } from "lightningcss";

export default defineConfig({
  output: "server",
  adapter: node({
    mode: "standalone",
  }),
  vite: {
    css: {
      lightningcss: { exclude: Features.LightDark },
    },
  },
  integrations: [
    react(),
    emdash({
      database: sqlite({ url: "file:./data.db" }),
      storage: local({
        directory: "./uploads",
        baseUrl: "/_emdash/api/media/file",
      }),
    }),
  ],
  devToolbar: { enabled: false },
});
EOF

	SITE_DIR="${tmpdir}" DB_DRIVER="postgres" SESSION_DRIVER="redis" STORAGE_DRIVER="s3" ENABLE_PLUGIN_SANDBOX="1" \
		python3 "${SCRIPT_DIR}/lib/astro-patch.py"
	cp "${cfg}" "${first_pass}"

	# Run a second time to verify strict idempotency
	SITE_DIR="${tmpdir}" DB_DRIVER="postgres" SESSION_DRIVER="redis" STORAGE_DRIVER="s3" ENABLE_PLUGIN_SANDBOX="1" \
		python3 "${SCRIPT_DIR}/lib/astro-patch.py"
	cp "${cfg}" "${second_pass}"

	cmp -s "${first_pass}" "${second_pass}" || {
		printf '[ERROR] astro-patch.py is not idempotent\n' >&2
		diff -u "${first_pass}" "${second_pass}" >&2 || true
		exit 1
	}

	assert_contains "${cfg}" 'sandboxRunner: "@emdash-cms/sandbox-workerd/sandbox",'
	assert_contains "${cfg}" 'lightningcss: { exclude: Features.LightDark },'
	assert_contains "${cfg}" 'sessionDrivers.redis({'
	assert_contains "${cfg}" 'database: postgres({'
	assert_contains "${cfg}" 'storage: s3({'

	# Toggle sandbox off
	SITE_DIR="${tmpdir}" DB_DRIVER="sqlite" SESSION_DRIVER="file" STORAGE_DRIVER="local" ENABLE_PLUGIN_SANDBOX="0" \
		python3 "${SCRIPT_DIR}/lib/astro-patch.py"
	assert_not_contains "${cfg}" 'sandboxRunner:'
	assert_not_contains "${cfg}" 'sessionDrivers'
	assert_contains "${cfg}" 'database: sqlite({'

	printf '[INFO] astro-patch regression checks passed\n'
	trap - RETURN
	rm -rf "${tmpdir}"
}

test_space_indent_and_sandbox_toggle_idempotent
