# HiEmdash 0.2.0-hi.2

`0.2.0-hi.2` is the native deployment release for the HiEmdash line.

From this version onward:

- `main` ships the native host-based installer
- the previous Docker/Podman implementation is archived on the `docker` branch

## Highlights

- native Node.js + systemd deployment on supported VPS hosts
- Debian 13, Ubuntu 24.04, EL9, and EL10 support
- Caddy + HTTPS support retained in native mode
- SQLite, PostgreSQL 18, file sessions, Redis/Valkey sessions, local storage, and S3-compatible storage
- native backup, restore, upgrade, and PostgreSQL password reset flows
- unified `--lang` command interface for installer, bootstrap, and operator CLI

## Native Platform Scope

- Debian 13
- Ubuntu 24.04
- EL9
- EL10

Runtime and package sources:

- Node.js from NodeSource
- PostgreSQL 18 from PGDG
- Redis from system packages
- EL10 automatically uses `valkey` when that is the packaged service

## Major Changes

- moved `main` to native deployment only
- rewrote README and VPS test planning around native operations
- standardized upgrade flow on `git`/template refresh + `pnpm install` + `pnpm build` + `systemctl restart`
- standardized command usage on:
  - `bootstrap.sh --lang=<code>`
  - `install.sh --lang=<code>`
  - `emdashctl --lang=<code>`

## Fixes Included

- PostgreSQL restore now fixes extracted dump permissions before running restore as `postgres`
- `emdashctl reset-db-password` now safely updates the role password and rebuilds the app so baked PostgreSQL config stays correct
- native Redis/Valkey service detection fixed for EL9 and EL10
- native Caddy install flow fixed so package auto-start does not break HTTPS validation
- native S3 storage and backup paths moved to `boto3` with successful remote object verification
- Linode native test runner hardened for SSH host-key reuse and workspace upload reliability

## Validation Summary

Real VPS validation completed for:

- Debian 13 + SQLite + file
- Ubuntu 24.04 + SQLite + file
- EL9 + SQLite + Redis
- EL10 + SQLite + Redis
- Debian 13 + Caddy + HTTPS
- Ubuntu 24.04 + Caddy + HTTPS
- Ubuntu 24.04 + PostgreSQL + file
- Ubuntu 24.04 + PostgreSQL + Redis + Caddy
- EL9 + PostgreSQL + Redis + Caddy
- EL10 + PostgreSQL + Redis + Caddy
- Debian 13 + S3-compatible media storage
- Ubuntu 24.04 + S3 backup

Operator checks also completed on retained native VPS instances for:

- `emdashctl backup`
- `emdashctl restore`
- `emdashctl upgrade app`
- `emdashctl reset-db-password`
- reboot and service autostart recovery

## Release Note

This release is the native cutover for HiEmdash. If you want the previous container-based installer, use the `docker` branch. If you are following `main`, use the native installer and operator workflow documented in the repository root.
