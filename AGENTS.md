# AGENTS.md — EmdashDeploy Engineering Guide

This file provides authoritative architecture context, non-negotiable invariants, platform pitfalls, and verification gates for AI coding agents and contributors working in `web-casa/EmdashDeploy`.

Historical design decisions from earlier iterations are preserved in [`docs4ai/development-process.md`](./docs4ai/development-process.md); end-to-end VPS validation procedures live in [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md).

---

## 1. Repository Architecture & Single Source of Truth

`main` ships **two first-class deployment runtimes** for EmDash `1.6.x` that intentionally share core configuration and patching logic:

1. **Native VPS Runtime** (`bootstrap.sh` → `install.sh` → `install-emdash.sh` → `lib/*.sh`, operated by `emdashctl`):
   - Installs Node.js 24 (NodeSource + Corepack), optional PostgreSQL 18 (PGDG), optional Valkey 8, and optional host Caddy directly on Debian 13, Ubuntu 24.04/26.04 LTS, and EL 9/10 (`x86_64` & `aarch64`).
   - Supports both the default single-instance layout (`/etc/emdash`, `/data/emdash`, `emdash-app.service`, port `3000`) and isolated multi-instance hosting (`--instance <name>` → `/etc/emdash/instances/<name>`, `/data/emdash-<name>`, `emdash-app-<name>.service`, auto-allocated port `3001+`).
2. **Coexistence-First Docker Compose Kit** (`docker/`):
   - `docker/compose.yml` references **prebuilt multi-arch GHCR images only** (`image:`, never `build:`), binds `127.0.0.1:${APP_PORT:-3000}` only (never host `80/443` by default), and provides optional `postgres`, `valkey`, and `caddy` profiles.
   - Local builds (`docker/compose.build.yml`), custom user sites (`docker/Dockerfile.custom` + `docker/compose.custom-site.yml`), and external reverse-proxy networks (`docker/compose.proxy-net.yml`) are strictly separated overlays.

### Shared Single-Source-of-Truth Modules (DO NOT Fork or Duplicate)

- **`lib/site-common.sh`**: Shared by `install-emdash.sh`, `emdashctl`, `docker/Dockerfile`, and `docker/Dockerfile.custom`. Owns `patch_site_package_json_common`, `render_site_astro_config_common`, `render_site_app_scripts_common`, `ensure_site_pnpm`, `update_env_file_value` (atomic `fsync` + `os.replace`), `atomic_install_file`, and encryption key helpers. Deployed atomically to `${ROOT_DIR}/lib/` on native hosts.
- **`lib/astro-patch.py`**: Minimal targeted text patcher for `astro.config.mjs`. Preserves user/template imports, fonts, plugins, and custom Vite/LightningCSS settings while managing only `siteUrl`, `database`, `storage`, `session`, and `sandboxRunner`.
- **`lib/fast-fail-google-fonts.mjs`**: Non-invasive Node.js `--import` preload hook that fast-fails `fonts.google.com` / `fonts.gstatic.com` with `AbortError` when `EMDASH_FAST_FAIL_GOOGLE_FONTS=1` and no `HTTPS_PROXY`/`ALL_PROXY` is set. Never mutate user `astro.config.mjs` or `node_modules` for font handling.
- **`lib/migrate-sqlite-to-pg.py`**: Zero-dependency (`sqlite3` + `psql`) SQLite → PostgreSQL 18 migrator.

---

## 2. Non-Negotiable Engineering Invariants

Any change MUST preserve all of the following invariants:

1. **Passkey / Public Origin Contract**:
   - Always keep `APP_PUBLIC_URL`, `EMDASH_SITE_URL`, and `SITE_URL` in sync in `emdash.env` and container environments.
   - `astro.config.mjs` must resolve `siteUrl` at runtime via `process.env.EMDASH_SITE_URL || process.env.SITE_URL || undefined`.
2. **Site Source Preservation (`preserve` vs. `sync`)**:
   - If `SITE_DIR/package.json` already exists and `EMDASH_INSTALL_FORCE_SYNC_TEMPLATE != 1`, the installer enters `preserve` mode and MUST NOT modify `astro.config.mjs`, `package.json`, or `src/pages/healthz.ts`.
   - Managed scripts (`emdash-build.sh`, `emdash-start.sh`) MUST live in `${ROOT_DIR}/scripts`, never inside `SITE_DIR`.
   - Never overwrite user site code during `emdashctl upgrade app`; only update `emdash` and `@emdash-cms/*` versions in `package.json`.
3. **Never Bake Secrets Into Images or Config Files**:
   - Database passwords, Redis passwords, S3 credentials, and `EMDASH_ENCRYPTION_KEY` must always be resolved at runtime via environment variables (`process.env.*`), never hardcoded into Docker images or `astro.config.mjs`.
   - Sensitive files (`emdash.env`, backup archives, `diagnose --out`, generated Docker `.env`) MUST be written atomically with `0600` or `0640` (`root:${APP_RUN_GROUP}`) permissions and reject symlinks where user-supplied output paths are accepted.
4. **Encryption Key Rotation Safety**:
   - `emdashctl rotate-encryption-key` is strictly two-stage: Stage 1 prepends `<new>,<old>` (preserving decryption of legacy envelopes); Stage 2 (`--prune-old`) scans SQLite and PostgreSQL tables for `$emdash` encrypted envelopes referencing legacy `kid`s and requires explicit `--confirm-prune-kid <kid>`.
   - **PostgreSQL `row_to_json` caveat**: `row_to_json(t)::text` escapes JSON quotes inside `TEXT` columns as `\"$emdash\"`. Always match `%$emdash%` (never unescaped `%"$emdash"%`).
5. **Diagnostic Redaction**:
   - `emdashctl diagnose` MUST recursively redact secrets, DB/Redis URLs, `emdash_enc_v1_*`, Bearer/Basic headers, cookies, JWTs, sensitive query params, and client IPs (unless `--no-ip-redact`). Never regress canary leak tests in `scripts/test-diagnose-regression.sh`.
6. **Modular Caddy & Multi-Instance Isolation**:
   - Caddy forbids duplicate `{ ... }` global blocks across imported files. Store `email` once in `/etc/emdash/caddy/global.email` and emit the single global block only in `/etc/emdash/caddy/Caddyfile`.
   - Managed site blocks live in `/etc/emdash/caddy/sites.d/<slug>.caddy`; user snippets live in `/etc/emdash/caddy/conf.d/*.caddy` and MUST NEVER be overwritten or deleted by installer/upgrade/uninstall.
   - Installing a second named instance on a legacy pre-`1.6.0-hi.3` host MUST auto-migrate the existing single-file Caddyfile into `sites.d/default.caddy`.
   - Named instances MUST isolate `HOME=${ROOT_DIR}` (with `${ROOT_DIR}/.cache`, `.local`, `.config` owned by `${APP_RUN_USER}:${APP_RUN_GROUP}`) and use per-instance `flock` (`/run/lock/emdashctl-<slug>.lock`).
7. **Destructive Action Guardrails**:
   - `emdashctl uninstall --purge-data` / `--drop-db` MUST require `--confirm-instance <expected_instance>` in non-interactive mode — never accept plain `--yes` alone.
   - Never stop/disable Caddy if any `sites.d/*.caddy` or `conf.d/*.caddy` remains; never delete `/usr/local/bin/emdashctl` if any sibling instance remains.
   - Guard against unsafe `ROOT_DIR` values (`/`, `/data`, `/etc`, `/var`, `/home`, `/usr`, `/root`, `/tmp`, `/opt`).
8. **Database Migration Completeness (`migrate-sqlite-to-pg.py`)**:
   - Must work under non-superuser PostgreSQL roles (use FK topological sort + `SET CONSTRAINTS ALL DEFERRED;`, never `SET session_replication_role = 'replica'`).
   - Skip SQLite-only FTS5 shadow tables (`_emdash_fts_*`) and migration metadata tables (`_emdash_migrations`, `__drizzle_migrations`, `emdash_migrations`).
   - Automatically create missing dynamic EmDash collection tables (`ec_*`, e.g., `ec_posts`, `ec_pages`) in PostgreSQL from SQLite `PRAGMA table_info` before copying rows.
   - **Hard-fail** (never silently return exit 0) if 0 tables match a non-empty SQLite DB, if any non-empty non-FTS5 SQLite table is missing in PostgreSQL, or if post-copy per-table row counts diverge.
9. **Docker Compose Kit Contracts**:
   - `docker/compose.yml` must never declare `build:`; local builds belong solely in `docker/compose.build.yml` with independent `emdash-deploy:local-*` tags.
   - `docker/backup.sh` and `docker/restore.sh` must support repeatable `--compose-file` arguments so they work seamlessly with overlays (`compose.build.yml`, `compose.custom-site.yml`).
   - Container healthchecks and `docker/restore.sh` must accept either `/healthz` or `/_emdash/api/setup/status` so custom sites without a `/healthz` route remain healthy.

---

## 3. Hard-Won Platform & Language Pitfalls (Do Not Reintroduce)

- **Bash `if ! func` disables `set -e` inside `func`**: Inside any helper called under `if ! ...` (such as `build_site` called by `build_site_with_rollback`), always chain critical steps with `|| return 1` explicitly.
- **Bash subshell arg parsing**: Never run `parse_lang_args` inside `< <(...)` process substitution — variable mutations (`INSTANCE_NAME`, `EMDASH_INSTALL_LANG`) will be silently lost. Populate a global array `PARSED_ARGS=()` in the current shell.
- **Bash `set -o pipefail` + `grep -q` SIGPIPE**: Use `grep -Fq ... <<<"${var}"` instead of `printf '%s' "${var}" | grep -Fq` on large strings.
- **Bash `RETURN` traps & `local` variables**: Store cleanup paths in non-local variables with `${VAR:-}` and clear `trap - RETURN` before normal return.
- **`pnpm 11` on Linux**:
  - Ignores uppercase `NPM_CONFIG_REGISTRY`! Always export lowercase `npm_config_registry="${NPM_CONFIG_REGISTRY}"` AND pass `--registry="${NPM_CONFIG_REGISTRY}"` to `pnpm install`.
  - Aborts non-interactive installs on `node_modules` recreation unless `npm_config_confirm_modules_purge=false` / `--config.confirmModulesPurge=false` is set.
  - Prefer calling `${SITE_DIR}/node_modules/.bin/emdash` directly over `pnpm exec emdash` in `emdashctl` probes to avoid Corepack cache interference.
- **Python 3.9–3.14 Compatibility**:
  - Rocky Linux 9 ships **Python 3.9**: NEVER use backslashes inside f-string `{...}` expressions (Python 3.12+ only) and NEVER use `X | Y` PEP 604 type unions.
  - Ubuntu 26.04 ships **Python 3.14**: For `tarfile.extractall`, use `if hasattr(tarfile, "data_filter"): tf.extractall(dest, ..., filter="data")` to avoid deprecation warnings while staying Python 3.9 compatible.
- **Debian/Ubuntu boot-time `apt` locks**: `DPkg::Lock::Timeout` does not wait for `/var/lib/apt/lists/lock`. Always use `wait_for_apt_locks` (`fcntl.lockf`, NOT `fcntl.flock`) in `lib/os.sh`.
- **Upstream template symlinks in backups**: EmDash `1.6.0` templates include relative symlinks under `site/` (e.g., `site/.claude/skills -> ../.agents/skills`). Runtime migration (`scripts/migrate-runtime.sh`) extracts only `meta/` and `data/` while strictly rejecting symlinks/devices/path traversal in those directories.
- **EL 9/10 SELinux Enforcing**: Always call `restorecon -RF` after writing/linking Caddy files under `/etc/emdash/caddy` and `/etc/caddy`.

---

## 4. Mandatory Local Verification Gate

Run this full gate before committing any change (matches `.github/workflows/ci.yml`):

```bash
bash -n bootstrap.sh install.sh install-emdash.sh emdashctl docker/entrypoint.sh docker/backup.sh docker/restore.sh lib/*.sh scripts/*.sh linode-test.sh linode-test-matrix.sh
python3 -m py_compile lib/astro-patch.py lib/migrate-sqlite-to-pg.py
node --check lib/fast-fail-google-fonts.mjs
shellcheck -S error bootstrap.sh install.sh install-emdash.sh emdashctl docker/entrypoint.sh docker/backup.sh docker/restore.sh lib/*.sh scripts/*.sh

for t in \
  scripts/test-passkey-origin-regression.sh \
  scripts/test-template-sync-regression.sh \
  scripts/test-emdashctl-regression.sh \
  scripts/test-astro-patch-regression.sh \
  scripts/test-upgrade-regression.sh \
  scripts/test-backup-restore-regression.sh \
  scripts/test-doctor-regression.sh \
  scripts/test-diagnose-regression.sh \
  scripts/test-rotate-key-regression.sh \
  scripts/test-docker-compose-regression.sh \
  scripts/test-multi-instance-regression.sh \
  scripts/test-s3-backup-restore-regression.sh \
  scripts/test-migrate-db-regression.sh; do
  echo "=== Running $t ==="
  bash "$t"
done
```

### Adding New Features or Bug Fixes

- Every bug fix or new CLI/installer behavior MUST include a regression assertion in the corresponding `scripts/test-*-regression.sh` suite (and if a new suite is added, register it in `.github/workflows/ci.yml`).
- When modifying `emdashctl` or `install-emdash.sh`, keep testability hooks (`EMDASH_INSTANCES_BASE_DIR`, `EMDASH_BIN_PATH`, `EMDASH_INSTALL_ENV_FILE`, `EMDASH_LOCK_FILE`, `EMDASH_CADDY_MAIN_FILE`, `BASH_SOURCE[0] == "$0"` main guard) intact so offline tests never require root or mutate host paths.

---

## 5. CI, Versioning & Release Process

- **CI Workflows** (Node 24 native GitHub Actions):
  - `.github/workflows/ci.yml`: Runs on every push/PR to `main` (`lint-and-regression`, `template-build-smoke`, `docker-kit-smoke`).
  - `.github/workflows/publish-docker.yml`: Triggered **only** on GitHub `release.published` (plus `workflow_dispatch`) with `concurrency` control — builds native `linux/amd64` + `linux/arm64` images, merges manifests with SBOM & provenance attestations, and runs native dual-arch `workerd` + `/healthz` smoke tests.
  - `.github/workflows/upstream-compat.yml`: Scheduled compatibility check against upstream `emdash-cms/templates`.
- **Release Checklist (`<emdash-version>-hi.<revision>`)**:
  1. Update `CHANGELOG.md`, `docker/compose.yml`, `docker/.env.example`, and `docker/README.md` image tags.
  2. Pass the full local verification gate and verify `ci.yml` is 3/3 green on `main`.
  3. Create annotated tag (`git tag -a <ver> -m "Release <ver>" && git push origin <ver>`) and publish GitHub Release (`gh release create <ver> ...`).
  4. Verify all 9 jobs in `publish-docker.yml` pass green (including both `smoke-test-native` architectures).
