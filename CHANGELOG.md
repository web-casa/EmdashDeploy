# Changelog

All notable changes to this project are documented in this file.

## 1.6.0-hi.5 - 2026-11-25

Hardening hotfix discovered during full P0/P1 real-environment E2E verification (Docker Compose PG 18 + Valkey + custom no-`/healthz` site, bidirectional Native ↔ Docker migration, real S3-compatible VersityGW storage/backup/prune/restore, and Rocky Linux 9.9 Python 3.9 + SELinux Enforcing 3-instance chaos testing).

### Fixed

- **Caller backup passphrase preservation across hosts/runtimes**: preserved caller-supplied `BACKUP_ENCRYPTION_PASSPHRASE` before sourcing `emdash.env` / `.env` in [`emdashctl`](./emdashctl) (`load_env`) and [`docker/backup.sh`](./docker/backup.sh), matching [`docker/restore.sh`](./docker/restore.sh) so cross-host/cross-runtime encrypted backups and restores (e.g. `docker-to-native` and `native-to-docker`) never fail with `openssl bad decrypt` when target host configs define a different passphrase
- **Clean S3 backup stdout return path**: routed `[INFO] Pruned old S3 backup: ...` in [`emdashctl`](./emdashctl) (`prune_s3_backups`) to `stderr` instead of `stdout` so S3 retention pruning no longer pollutes the captured archive path returned by `create_backup_archive`
- **Cross-runtime `docker/restore.sh` reliability on fresh PG + Valkey stacks and native `--full` archives**:
  - Restricted tar extraction and manifest SHA-256 verification in [`docker/restore.sh`](./docker/restore.sh) to `meta/` and `data/` (matching [`scripts/migrate-runtime.sh`](./scripts/migrate-runtime.sh)) so native `--full` backup archives containing upstream `site/` symlinks (e.g. `site/.claude/skills`) restore cleanly into Docker without relaxing symlink/traversal checks inside `meta/` or `data/`
  - Added PostgreSQL readiness polling (`psql SELECT 1`) after `docker compose up -d postgres` to eliminate first-boot `createdb` race conditions during `native-to-docker --apply`
  - Automatically starts `valkey` alongside `emdash` when `SESSION_DRIVER=redis`
- **`scripts/migrate-runtime.sh` image tag & port override**: updated default `native-to-docker` GHCR image tag to `1.6.0-hi.5-{profile}` and added optional `DOCKER_APP_PORT` override for side-by-side host migrations
- **EL9 / flaky network `git clone` resilience**: added automatic `git -c http.version=HTTP/1.1 clone` retry fallback in [`lib/render.sh`](./lib/render.sh) (`clone_template_repo`) to recover from GitHub HTTP/2 stream resets on EL9 hosts

### Validation Summary

- Full local verification gate (`bash -n`, `py_compile`, `node --check`, `shellcheck -S error`, all 13 offline regression suites including new passphrase-preservation, S3 prune stdout hygiene, `docker/restore.sh` hardening, and `git` HTTP/1.1 fallback assertions)
- **Docker Compose ARM64 E2E**: PG 18 + Valkey encrypted backup & atomic temp-DB restore (`ALTER DATABASE`), multi-instance coexistence + `compose.proxy-net.yml` zero-host-port behind external Caddy, and `Dockerfile.custom` + `compose.custom-site.yml` site without `/healthz` (HTTP 404 on `/healthz`, container still `healthy` via `/_emdash/api/setup/status`, multi-`--compose-file` backup/restore)
- **Bidirectional Native ↔ Docker Migration (PG 18 + Valkey)**: full encrypted `docker-to-native` (Docker → PVE Ubuntu 26.04 `VM 981`) and `native-to-docker --apply` (`VM 981` `--full --encrypt` → fresh Docker PG + Valkey stack), preserving `EMDASH_ENCRYPTION_KEY`, PG `$emdash` encrypted rows, and `/data/uploads`
- **Real S3-Compatible Loop (VersityGW + PVE `VM 981`)**: `STORAGE_DRIVER=s3` preflight + `doctor --deep`, 3 encrypted S3 backups with `BACKUP_KEEP_S3=2` remote pruning (`S3_COUNT=2`), local disaster wipe + `restore --from-s3 latest --yes`
- **Rocky Linux 9.9 (`VM 985`, Python `3.9.25` + SELinux `Enforcing`)**: zero-downtime `--update-cli` (`MainPID 947 -> 947`), legacy single-file Caddyfile auto-migration + `conf.d` preservation + Caddy reload-only uninstall, `upgrade app` user route preservation, 3-instance mixed stack (`default` PG+Valkey, `site2` SQLite+Caddy, `site3` isolated PG+Valkey `REDIS_DB=1`) full `reboot` autostart, per-instance `flock` concurrency, `migrate-db` non-empty/wrong-password/mid-migration automatic rollback, and full Python 3.9 `migrate-db sqlite-to-postgres` (`74` tables, `missing_in_pg: []`, `doctor --deep` `16/16 ok`)
- Documented full P0 (Phase F) and P1 (Phase G) matrices in [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md)

## 1.6.0-hi.4 - 2026-11-24

Post-release real-VM hardening hotfix discovered during cross-distro Proxmox VE verification (Rocky Linux 10.3 SELinux Enforcing + Debian 13 `trixie` + ARM64 GHCR).

### Fixed

- **`pnpm 11` mainland China mirror registry**: exported lowercase `npm_config_registry` and passed `--registry=` explicitly in [`lib/site-common.sh`](./lib/site-common.sh), [`lib/config.sh`](./lib/config.sh), [`docker/Dockerfile`](./docker/Dockerfile), and [`docker/Dockerfile.custom`](./docker/Dockerfile.custom) so `EMDASH_MIRROR_PRESET=cn` no longer falls back to `registry.npmjs.org` on Linux (cut Rocky Linux 10 full multi-instance install down to ~53s)
- **`build_site()` error propagation**: added explicit `|| return 1` guards inside `build_site()` in [`lib/render.sh`](./lib/render.sh) so `if ! build_site` rollback wrappers never swallow `emdash-build.sh` failures
- **Seamless legacy Caddyfile upgrade & safe uninstall**: automatically migrates pre-`1.6.0-hi.3` single-file `/etc/emdash/caddy/Caddyfile` into `/etc/emdash/caddy/sites.d/default.caddy` when installing a second named instance ([`lib/render.sh`](./lib/render.sh)), and preserves running Caddy during `emdashctl uninstall` whenever any `sites.d/*.caddy` or `conf.d/*.caddy` snippet remains ([`emdashctl`](./emdashctl))
- **SQLite → PostgreSQL 18 dynamic content tables & FTS5 shadow tables**: updated [`lib/migrate-sqlite-to-pg.py`](./lib/migrate-sqlite-to-pg.py) to skip SQLite-only `_emdash_fts_*` virtual shadow tables and automatically provision missing EmDash dynamic collection tables (`ec_*`, e.g. `ec_posts`, `ec_pages`) in PostgreSQL before data transfer and row-count verification
- **Runtime migration archive extraction**: scoped [`scripts/migrate-runtime.sh`](./scripts/migrate-runtime.sh) extraction strictly to `meta/` and `data/` (with full symlink/path-traversal checks) so upstream template relative symlinks under `site/` (e.g. `site/.claude/skills -> ../.agents/skills`) do not block `native-to-docker` migration

### Validation Summary

- All 13 offline regression suites (including new legacy Caddyfile migration, `_emdash_fts_*` skip, dynamic `ec_posts` DDL provisioning, and `site/.claude/skills` symlink handling assertions) + GitHub Actions CI (`lint-and-regression`, `template-build-smoke`, `docker-kit-smoke`) pass
- **PVE VM 982 (Rocky Linux 10.3 `x86_64`, SELinux Enforcing)**: zero-downtime `--update-cli` (`MainPID 968 -> 968`), 53s `--instance el10-site2` install (`portfolio`, CN mirror + fast-fail `18.02s`), `doctor --deep` (19 checks / 0 fail), `diagnose --out` (`0600`), clean `uninstall --purge-data`
- **PVE VM 983 (Debian 13 `trixie`, `x86_64`, 2 GiB RAM + PG 18)**: zero-downtime `--update-cli` across 2 instances, `migrate-db sqlite-to-postgres` migrating 74 tables / 75 PG tables (`missing_in_pg: []`, preserving both `$emdash` encrypted canary and `ec_posts` blog post row), encrypted backup -> `scripts/migrate-runtime.sh native-to-docker` (`0600` `.env`), clean `uninstall --purge-data --drop-db`
- **ARM64 GHCR verification**: pulled `ghcr.io/web-casa/emdash-deploy:1.6.0-hi.3-blog-sqlite` (`aarch64`) and verified full encrypted `docker/backup.sh` -> `docker/restore.sh --yes` loop

## 1.6.0-hi.3 - 2026-11-24

Native multi-instance hosting, modular Caddy layout, zero-downtime CLI updates, clean instance uninstallation, full S3 backup/restore loop, SQLite-to-PostgreSQL and Docker/Native migration assistants, mainland China Google Fonts fast-fail build acceleration, Docker restore parity, and Node 24 CI/GHCR hardening for the `HiEmdash` line.

### Added

- **Native multi-instance support on a single host**:
  - `install.sh --instance <name>` (and `bootstrap.sh` passthrough) creates isolated named instances under `/etc/emdash/instances/<name>`, `/data/emdash-<name>`, `emdash-app-<name>.service`, `/etc/cron.d/emdash-backup-<name>`, auto-allocated free `APP_PORT` starting at `3001`, and isolated PostgreSQL database/user `emdash_<name>` (while preserving 100% compatibility for default single-instance `/etc/emdash` + `/data/emdash` layouts)
  - `emdashctl --instance <name> <command>` with per-instance `flock` (`/run/lock/emdashctl-<slug>.lock`), plus `emdashctl instances [--json]` host-wide overview
- **Modular Caddy layout** (`/etc/emdash/caddy/`):
  - Single host-wide global email block (`global.email`) in `/etc/emdash/caddy/Caddyfile`
  - Managed per-instance site blocks under `/etc/emdash/caddy/sites.d/<slug>.caddy`
  - User-owned snippets under `/etc/emdash/caddy/conf.d/*.caddy` preserved untouched across upgrades and instance uninstalls
- **Zero-downtime CLI & shared library updater**:
  - `install.sh --update-cli [--instance <name>]` atomically updates `/usr/local/bin/emdashctl` and `${ROOT_DIR}/lib/` across installed instances without rebuilding or restarting running services
- **Safe instance uninstaller**:
  - `emdashctl [--instance <name>] uninstall [--purge-data] [--drop-db] [--confirm-instance <name>] [--yes]`
  - Includes root-path blocklist, mandatory `--confirm-instance <name>` guard for destructive `--purge-data` / `--drop-db` (never accepts `--yes` alone), sibling-instance and `conf.d` preservation, and only removes `/usr/local/bin/emdashctl` when zero instances remain
- **Full S3 backup/restore loop**:
  - `BACKUP_KEEP_S3` (default `14`) automatic remote retention pruning strictly scoped to `emdash-backup-YYYYMMDD-HHMMSS.tar.gz(.enc)?`
  - `emdashctl backup --list-s3 [--json]` and `emdashctl restore --from-s3 <key|latest>`
- **Database & runtime migration assistants**:
  - `emdashctl [--instance <name>] migrate-db sqlite-to-postgres` powered by zero-dependency [`lib/migrate-sqlite-to-pg.py`](./lib/migrate-sqlite-to-pg.py) (`sqlite3` + `psql`): FK topological sort (non-superuser safe), `information_schema` column type coercion (including `$emdash` encrypted envelopes verbatim), sequence resets, exact per-table row count verification, hard-fail on empty/missing non-empty target schema, and full automatic rollback on failure
  - [`scripts/migrate-runtime.sh`](./scripts/migrate-runtime.sh): `docker-to-native` and `native-to-docker` migration helper preserving `EMDASH_ENCRYPTION_KEY` with `0600` `.env` permissions
- **Mainland China Google Fonts build speedup**:
  - Non-invasive Node `--import` preload hook [`lib/fast-fail-google-fonts.mjs`](./lib/fast-fail-google-fonts.mjs) automatically enabled (`EMDASH_FAST_FAIL_GOOGLE_FONTS=1`) under `EMDASH_MIRROR_PRESET=cn` when no `HTTPS_PROXY`/`ALL_PROXY` is set (opt-out via `0`), cutting Astro build times from ~110–140s timeouts down to ~16–19s without modifying user `astro.config.mjs`
- **Docker restore & key-rotation parity**:
  - [`docker/restore.sh`](./docker/restore.sh): decrypts `.enc`, validates tar member safety (rejects symlinks/path traversal), verifies `manifest.json` driver and SHA-256 checksums, atomically swaps SQLite (`PRAGMA integrity_check`) or PostgreSQL (`pg_restore` temp-DB swap), restores `/data/uploads`, and verifies `/healthz`
  - Repeatable `--compose-file` support in both [`docker/backup.sh`](./docker/backup.sh) and [`docker/restore.sh`](./docker/restore.sh) for `compose.build.yml` / `compose.custom-site.yml` overlays
  - Updated [`docker/README.md`](./docker/README.md) with `docker/restore.sh`, two-stage Docker encryption key rotation, and `scripts/migrate-runtime.sh` guides
- **CI & GHCR hardening**:
  - Removed duplicate `push.tags` trigger and added `concurrency` control in [`.github/workflows/publish-docker.yml`](./.github/workflows/publish-docker.yml)
  - Upgraded all GitHub Actions workflows to Node 24 native action releases (`checkout@v7`, `setup-node@v7`, `upload-artifact@v7`, `download-artifact@v8`, `docker/setup-buildx-action@v4`, `docker/login-action@v4`, `docker/build-push-action@v7`)
  - Added `docker-kit-smoke` job to [`.github/workflows/ci.yml`](./.github/workflows/ci.yml) testing `compose.custom-site.yml` + `Dockerfile.custom` + encrypted `docker/backup.sh` + `docker/restore.sh`
  - Added 3 new offline regression suites: [`scripts/test-multi-instance-regression.sh`](./scripts/test-multi-instance-regression.sh), [`scripts/test-s3-backup-restore-regression.sh`](./scripts/test-s3-backup-restore-regression.sh), and [`scripts/test-migrate-db-regression.sh`](./scripts/test-migrate-db-regression.sh)

### Fixed

- Fixed `parse_lang_args` in [`emdashctl`](./emdashctl) running inside a `< <(...)` subshell so `--lang` and `--instance` flags always propagate to the main process
- Isolated per-instance `HOME=${ROOT_DIR}` (with `.cache`, `.local`, `.config` owned by `${APP_RUN_USER}:${APP_RUN_GROUP}`) in [`lib/render.sh`](./lib/render.sh) and `emdashctl`'s `run_as_app_user()` so named instances never hit Corepack `EACCES` on startup or during migrations
- Added `npm_config_confirm_modules_purge=false` / `--config.confirmModulesPurge=false` in [`lib/site-common.sh`](./lib/site-common.sh) so non-interactive `pnpm 11` installs during `migrate-db` or `upgrade app` never abort with `ERR_PNPM_ABORTED_REMOVE_MODULES_DIR_NO_TTY`
- Invoked `${SITE_DIR}/node_modules/.bin/emdash` directly in `emdashctl` migration probes to avoid Corepack cache interference
- Used Python 3.12+ `tarfile.extractall(..., filter="data")` when available (preserving Python 3.9 compatibility on EL9)

### Validation Summary

- All 13 offline regression test suites + `bash -n` + `py_compile` + `node --check` + `shellcheck -S error` pass with zero warnings
- **Real PVE Ubuntu 26.04.1 LTS VM (`x86_64`) end-to-end verification**:
  - `install.sh --update-cli` updated `/usr/local/bin/emdashctl` + both instances' `lib/` with zero downtime (`MainPID` unchanged across both running services)
  - Multi-instance `--instance site2` (`marketing`, SQLite, Caddy HTTP, `EMDASH_MIRROR_PRESET=cn`): Google Fonts fast-fail built Astro server in `18.19s`, auto-allocated port `3001`, validated modular Caddyfile (`sites.d/` + user `conf.d/`), and passed `emdashctl instances`
  - `emdashctl --instance site2 migrate-db sqlite-to-postgres --yes`: initialized 73 PostgreSQL 18 tables, migrated 72 data tables (61 rows including an `$emdash` encrypted-envelope canary in `options`) with exact row-count verification, and verified live `/healthz` + `/_emdash/api/setup/status`
  - `emdashctl --instance site2 uninstall --purge-data --drop-db --confirm-instance site2`: removed `site2` service/cron/Caddy snippet/config/data/PostgreSQL DB cleanly while preserving `default` instance health, user `conf.d/` snippet, and `/usr/local/bin/emdashctl`
- **Local ARM64 (`aarch64`) Docker end-to-end verification**:
  - `compose.yml` + `compose.build.yml` with `EMDASH_FAST_FAIL_GOOGLE_FONTS=1` built Astro in `16.25s`
  - Full encrypted `docker/backup.sh --encrypt` -> DB corruption + upload deletion -> `docker/restore.sh --yes` loop verified data, uploads, and `/healthz`

## 1.6.0-hi.2 - 2026-11-24

Operational maturity, AI-friendly diagnostics, safe two-stage encryption key rotation, native multi-arch GHCR Docker publishing, and Ubuntu 26.04 LTS / ARM64 platform expansion for the `HiEmdash` line.

### Added

- AI-friendly one-command redacted diagnostic bundle: `emdashctl diagnose [--json] [--lines <N>] [--out <file>] [--no-ip-redact]` (`schema_version: 1`)
  - Aggregates host metadata, non-secret config summary (`encryption_key_kids`), site package versions, `doctor --deep`, migration status, systemd service states, structured `journalctl -o json` logs (32 KiB per-service cap with `truncated` flag), and `suggested_next_steps`
  - Recursive, idempotent redaction covering database/Redis URLs, `emdash_enc_v1_*`, runtime secrets, `Authorization: Bearer/Basic`, `Cookie`/`Set-Cookie`, JWTs, sensitive URL query parameters, and Caddy client IP headers (`remote_ip`/`client_ip`/`X-Forwarded-For`, opt-out via `--no-ip-redact`)
  - `--out` refuses symlinks and writes atomically with `0600` permissions
- Safe two-stage `EMDASH_ENCRYPTION_KEY` rotation assistant: `emdashctl rotate-encryption-key [--status [--json] | --dry-run [--yes] | --prune-old [--confirm-prune-kid <kid>] [--force-prune]]`
  - Stage 1 generates a new key via `emdash secrets generate`, atomically prepends `<new>,<old>` to `/etc/emdash/emdash.env` and updates `encryption_key_kid` in `/etc/emdash/install.yml`, restarts `emdash-app`, verifies `/healthz` + `/_emdash/api/setup/status`, and rolls back both files automatically on failure
  - Stage 2 (`--prune-old`) scans SQLite/PostgreSQL tables for EmDash `1.6.x` encrypted envelopes referencing legacy `kid`s, blocks pruning if any references remain (unless `--force-prune`), and requires explicit kid-bound confirmation (`--confirm-prune-kid <kid>`)
- Enhanced `emdashctl doctor --deep`:
  - Verifies runtime directory ownership (`${APP_RUN_USER}:${APP_RUN_GROUP}`) and `/etc/emdash/emdash.env` permissions (blocks group-write or world-readable modes)
  - Aggregates upstream `pnpm exec emdash doctor --database <path> --json` checks (`collections`, `datetime storage`, `users`) under `timeout 15` protection in SQLite mode
- Native multi-arch GHCR Docker publishing workflow [`.github/workflows/publish-docker.yml`](./.github/workflows/publish-docker.yml) (`linux/amd64` on `ubuntu-24.04` + `linux/arm64` on `ubuntu-24.04-arm`, digest merge via `docker buildx imagetools create`, SBOM & provenance attestations, and native dual-arch `workerd` + `/healthz` post-publish smoke tests)
- Decoupled Docker Compose overlays and container backup helper:
  - [`docker/compose.build.yml`](./docker/compose.build.yml): independent local build overlay (with `emdash-deploy:local-*` tags and mainland China mirror args), separated from prebuilt GHCR images in [`docker/compose.yml`](./docker/compose.yml)
  - [`docker/Dockerfile.custom`](./docker/Dockerfile.custom) & [`docker/compose.custom-site.yml`](./docker/compose.custom-site.yml): immutable non-root build for custom/AI-modified EmDash sites via BuildKit `additional_contexts` without bind-mounting `/app/site`
  - [`docker/backup.sh`](./docker/backup.sh): container-safe SQLite (`sqlite3.backup()` + `PRAGMA integrity_check`) and PostgreSQL (`pg_dump -Fc` + `pg_restore --list`) backup script with `0600` output and dedicated `BACKUP_ENCRYPTION_PASSPHRASE` encryption
- Ubuntu 26.04 LTS (`resolute`) and ARM64 (`aarch64`) support in [`lib/os.sh`](./lib/os.sh) (dynamic EL PGDG `uname -m` URL selection, PGDG apt release reachability check, and runtime Valkey systemd unit detection)
- Generic, read-only-by-default remote E2E verification script [`scripts/remote-e2e-verify.sh`](./scripts/remote-e2e-verify.sh) (mutating tests require `--destructive`, reboot test requires `--verify-reboot`)
- New offline regression suites: [`scripts/test-diagnose-regression.sh`](./scripts/test-diagnose-regression.sh) (including secret canary leakage assertions) and [`scripts/test-rotate-key-regression.sh`](./scripts/test-rotate-key-regression.sh)

### Changed

- Upgraded `update_env_file_value` in [`lib/site-common.sh`](./lib/site-common.sh) to atomic `fsync` + `os.replace` writes preserving file permissions and ownership
- Cleaned legacy container-era variables (`MATRIX_APP_IMAGE`, `MATRIX_APP_BASE_IMAGE`) from [`linode-test-matrix.sh`](./linode-test-matrix.sh) and added `ubuntu26-postgres-redis`
- Synchronized all 9 language READMEs (`README.md`, `README.zh-CN.md`, `README.zh-TW.md`, `README.ja.md`, `README.ko.md`, `README.de.md`, `README.es.md`, `README.fr.md`, `README.pt.md`), `lib/i18n.sh` usage help, [`docker/README.md`](./docker/README.md), and [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md)
- Updated `.gitignore` to ignore local `mitm_mcp_traffic.db` and added AI project documentation under `docs4ai/`

### Fixed

- Fixed PostgreSQL encrypted-envelope `kid` scan in `emdashctl rotate-encryption-key --prune-old` (`LIKE '%\$emdash%'`) so JSON stored inside PostgreSQL `TEXT` columns (escaped by `row_to_json`) is reliably detected before pruning legacy keys
- Added POSIX `fcntl.lockf` apt/dpkg lock waiting (`wait_for_apt_locks`) in `lib/os.sh` to prevent `apt-get` lock collisions with `cloud-init` / `unattended-upgrades` on freshly booted Debian/Ubuntu hosts
- Skipped port 443 and public DNS A/AAAA checks in `lib/network.sh` when Caddy is configured in HTTP-only mode (`USE_CADDY=1`, `ENABLE_HTTPS=0`, e.g., LAN or behind Cloudflare Tunnel/CDN)

### Validation Summary

- All 10 offline regression test suites (including PostgreSQL `row_to_json` escaped `TEXT` column scan regression) + `bash -n` + `py_compile` + `shellcheck -S error` pass
- Full 6-distro real PVE `x86_64` VM deep E2E verification matrix passed via `scripts/remote-e2e-verify.sh`:
  - **Ubuntu 26.04.1 LTS** (`resolute`, kernel `7.0.0`): PG 18 + Valkey + `blog` + full 7-step + `reboot` autostart (`ok=15, warn=0, fail=0`)
  - **Rocky Linux 10.3** (SELinux enforcing): SQLite + file + Caddy HTTP + `marketing` + SQLite upstream `emdash doctor` aggregation + Caddy live sensitive-header canary redaction (0 leak) + env permission fault injection + SQLite DB `kid` prune guard + chaos restore (`ok=18, warn=1, fail=0`)
  - **Debian 13** (`trixie`, 2 GiB RAM): auto `/swapfile.emdash` creation + apt lock wait + PG 18 + Valkey + Caddy HTTP + `blog` + Caddy canary redaction + PG DB `kid` prune guard + `reset-db-password` + `reboot` autostart (`ok=16, warn=0, fail=0`)
  - **Ubuntu 24.04.5 LTS** (`noble`): SQLite + Valkey + `portfolio` + idempotent installer rerun (preserve mode keeping custom files, `astro.config.mjs`, and encryption key) + SQLite DB `kid` prune guard + chaos restore (`ok=17, warn=1, fail=0`)
  - **Rocky Linux 9.9** (SELinux enforcing): PGDG `EL-9-x86_64` PG 18 + Valkey + `blog` + PG DB `kid` prune guard + chaos restore + `reset-db-password` + `reboot` autostart (`ok=15, warn=0, fail=0`)
  - **AlmaLinux 10.3** (SELinux enforcing, in-place CLI upgrade from `1.6.0-hi.1`): default read-only `remote-e2e-verify.sh` + `rotate-encryption-key --status` (`ok=15, warn=0, fail=0`)
- Native **ARM64 (`aarch64`)** local Docker build (`compose.yml` + `compose.build.yml`) and `docker/backup.sh` (plain + encrypted SQLite `sqlite3.backup()` verification) passed live smoke tests

## 1.6.0-hi.1 - 2026-11-24

EmDash `1.6.x` compatibility, lifecycle reliability, and multi-service Docker Compose release for the `HiEmdash` line.

### Added

- Shared site management library [`lib/site-common.sh`](./lib/site-common.sh) deployed atomically to `${ROOT_DIR}/lib/site-common.sh` and included in rollback snapshots
- EmDash `1.6.x` native security and plugin isolation:
  - `EMDASH_ENCRYPTION_KEY` generation via `pnpm exec emdash secrets generate` with `fingerprint` verification
  - `@emdash-cms/sandbox-workerd` + `workerd` plugin sandbox support (enabled by default, configurable via `EMDASH_INSTALL_ENABLE_PLUGIN_SANDBOX`)
- Non-destructive `emdashctl upgrade app` workflow (`--dry-run`, `--target`, `--skip-backup`, `--yes`) with `flock` locking, pre-upgrade verified backup, explicit `emdash migrate --status --json` / `emdash migrate --expected-target-fingerprint` gate, and pre/post-migration rollback separation
- Read-only `emdashctl template diff [--stat]` to compare upstream template updates without overwriting user code
- Enhanced `emdashctl backup [--full] [--encrypt]` with `0600` permissions, `manifest.json` + SHA256 checksums, lightweight site source snapshot (excluding `node_modules`/`dist`/`.astro`/`.git`), SQLite `PRAGMA integrity_check`, PostgreSQL custom dump (`pg_dump -Fc`) + `pg_restore --list` verification, and optional AES-256-CBC PBKDF2 encryption
- Safe `emdashctl restore <archive> [--with-site] [--with-secrets]` with cross-driver guard and portable-secret-only merge (never overwrites host domain, ports, or DB credentials)
- Full-stack redacted diagnostics via `emdashctl doctor --deep --json` (`schema_version: 1`)
- Mainland China mirror acceleration preset (`EMDASH_MIRROR_PRESET=cn`, application/registry layer only without modifying host APT/DNF system repositories)
- Lightweight multi-service / multi-instance Docker Compose kit under [`docker/`](./docker/README.md):
  - [`docker/Dockerfile`](./docker/Dockerfile): Node.js 24 image reusing `lib/site-common.sh` and `lib/astro-patch.py`, supporting EmDash `1.6.x`, `@emdash-cms/sandbox-workerd`, `tini`, `HEALTHCHECK`, and optional mainland China registry build args
  - [`docker/entrypoint.sh`](./docker/entrypoint.sh): non-root `PUID`/`PGID` alignment, persistent/validated `EMDASH_ENCRYPTION_KEY`, PostgreSQL readiness wait, explicit `emdash migrate` gate (`start`, `migrate`, `migrate-status`, `secrets-generate`, `doctor`)
  - [`docker/compose.yml`](./docker/compose.yml): coexistence-first stack (binds `127.0.0.1:${APP_PORT:-3000}` only, no host `80/443` conflict) with optional `postgres` (PG 18), `valkey` (Valkey 8), and `caddy` profiles
  - [`docker/compose.proxy-net.yml`](./docker/compose.proxy-net.yml): zero-host-port overlay for attaching to an existing reverse-proxy Docker network
  - [`docker/.env.example`](./docker/.env.example) & [`docker/Caddyfile.example`](./docker/Caddyfile.example)
- GitHub Actions CI (`.github/workflows/ci.yml` and `.github/workflows/upstream-compat.yml`) and 5 new offline regression test suites

### Changed

- Removed discontinued `blank` template option (`blog`, `marketing`, `portfolio` supported; existing legacy instances preserved with migration notice)
- Stopped hardcoding `pnpm@10.28.0` and `kysely@^0.27.6`; Corepack now respects each site's `packageManager` field with `COREPACK_ENABLE_DOWNLOAD_PROMPT=0`
- Hardened `lib/astro-patch.py` to support tab/space indentation, `sandboxRunner` injection, strict idempotency, and secret-free PostgreSQL runtime env resolution (`|| undefined`)
- Updated `emdashctl reset-db-password` to preserve user `astro.config.mjs` and validate the real DB-backed `/_emdash/api/setup/status` endpoint
- Replaced legacy `docker/base/Dockerfile` with the unified `docker/Dockerfile`

### Fixed

- Removed container-era dead helpers (`compose_cmd`, `run_compose`, `scripts/prepare-app-context.sh`)
- Fixed `emdashctl doctor` reporting `backup schedule` as `fail` when `BACKUP_ENABLED=0` (now `skipped`)
- Fixed `install-emdash.sh` NAT-friendly local setup status probe when Caddy is disabled

### Validation Summary

- All 8 offline regression suites + `bash -n` + `py_compile` pass
- Real PVE AlmaLinux 10.2 (SELinux enforcing, mainland China network with `EMDASH_MIRROR_PRESET=cn`) E2E verification passed across fresh install (PG 18 + Valkey + `sandbox-workerd`), `doctor --deep --json`, non-destructive `upgrade app`, `template diff`, encrypted `--full` backup & `--with-site --with-secrets` restore, and `reset-db-password`
- Dual-instance Docker Compose E2E verification passed (PostgreSQL 18 + Valkey 8 + `sandbox-workerd` secret-free image coexisting with SQLite instance on the same host)

## 0.2.0-hi.2 - 2026-04-09

Native deployment release for the `HiEmdash` line. `main` now ships the host-based installer and operations flow; the previous container-based implementation remains archived on the `docker` branch.

### Changed

- Switched `main` from Docker/Podman deployment to native Node.js + systemd deployment
- Standardized installer, bootstrap, and operator entrypoints on `--lang`
- Rewrote repository documentation and VPS test plan for native deployment
- Updated upgrade behavior to the native host workflow: template refresh, `pnpm install`, `pnpm build`, and service restart

### Added

- Native install path for Debian 13, Ubuntu 24.04, EL9, and EL10
- Native `systemd` service generation for `emdash-app`
- Native package installation via NodeSource, PGDG, and system packages
- Native Caddy, PostgreSQL, Redis/Valkey, S3 storage, and S3 backup support
- Native release-prep VPS operator validation for backup, restore, password reset, upgrade, and reboot

### Fixed

- PostgreSQL restore now makes extracted dumps readable to the `postgres` OS user
- PostgreSQL password reset now updates the role safely and rebuilds the app so baked connection settings stay in sync
- Native Redis service/path handling on EL9 and EL10
- Native Caddy installation ordering where package auto-start could block HTTPS validation
- Native S3 storage and backup flows with `boto3`-based verification
- Linode native test reliability around SSH host keys and workspace upload

### Validation Summary

Validated with real native VPS testing for:

- Debian 13
- Ubuntu 24.04
- EL9
- EL10
- SQLite, PostgreSQL, Redis/Valkey
- Caddy + HTTPS
- S3-compatible media storage
- S3 backup
- `emdashctl backup`, `restore`, `upgrade app`, `reset-db-password`, and reboot/autostart

### Notes

- `main` is native deployment only as of this release.
- The archived container-based implementation remains available on the `docker` branch.

## 0.2.0-hi.1 - 2026-04-08

First validated HiEmdash production release for VPS deployment.

### Added

- Interactive and non-interactive EmDash VPS installer
- `emdashctl` for status, logs, smoke checks, backup, restore, restart, upgrades, and PostgreSQL password reset
- Native `Caddy` install path with automatic HTTPS
- `Docker` support for Debian 12/13 and Ubuntu 22/24
- `Podman` support for Rocky/Alma/RHEL-like EL 8/9/10
- `SQLite` and `PostgreSQL 18` deployment modes
- `file` and `Redis` session modes
- `local filesystem` and `S3-compatible` storage support
- GHCR builder and app images
- `linux/amd64` and `linux/arm64` image manifests
- Linode-based VPS validation scripts and matrix runner

### Changed

- Standardized health probes on `/healthz`
- Stabilized release tagging and GHCR publish flow for branch/tag separation
- Improved Caddy handling on EL systems with state-directory preparation and SELinux relabel fallback
- Refined backup behavior to keep local artifacts and support verified S3 uploads
- Expanded real-VPS test coverage across Docker, Podman, amd64, and arm64

### Fixed

- PostgreSQL password reset now updates runtime config correctly
- PostgreSQL restore flow now avoids destructive early cutover
- SQLite backup and restore handling improved for WAL safety
- S3 backup upload path now returns proper failure codes
- Podman and Linode test runner edge cases around retries, labels, and flow control
- Caddy certificate issuance on ARM64/EL where `/var/lib/caddy` was not prepared

### Validation Summary

Validated with real VPS testing for:

- Debian 13
- Ubuntu 24
- CentOS Stream 9
- CentOS Stream 10
- AlmaLinux 10
- amd64 and arm64 hosts
- SQLite, PostgreSQL, Redis, Caddy + HTTPS, S3 backup, restore, and password reset flows

### Known Caveat

One arm64 AlmaLinux 10 cloud environment showed external interference on public `80/443` despite successful in-host TLS issuance and local HTTPS validation. Non-standard public ports remained reachable on the same host. This indicates provider or edge-network behavior rather than an installer defect.

## v0.1.0 - 2026-04-07

Initial public repository release with installer, tooling, repository metadata, and translated READMEs.
