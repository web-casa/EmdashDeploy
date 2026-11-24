# Changelog

All notable changes to this project are documented in this file.

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
