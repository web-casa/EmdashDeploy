# HiEmdash 0.2.0-hi.1 Changelog Archive

Release date: 2026-04-08

## Highlights

- First validated HiEmdash VPS installer release
- Real VPS verification across Docker and Podman platforms
- GHCR builder and app images for `amd64` and `arm64`
- Native `Caddy + HTTPS` support
- `emdashctl` operations toolkit

## Included Scope

- Debian 12/13 and Ubuntu 22/24 via Docker
- Rocky/Alma/RHEL-like EL 8/9/10 via Podman
- SQLite and PostgreSQL 18
- file and Redis session modes
- local filesystem and S3-compatible storage
- backup, restore, smoke checks, and PostgreSQL password reset

## Release Work

- Consolidated health checks on `/healthz`
- Completed and validated S3 backup support
- Stabilized GHCR branch/tag publishing behavior
- Expanded Linode VPS matrix testing
- Fixed Caddy state-directory handling for ARM64 EL deployments

## Validation Coverage

Real VPS validation was completed for:

- Debian 13 + Docker
- Ubuntu 24 + Docker
- CentOS Stream 9/10 + Podman
- AlmaLinux 10 + Podman
- amd64 and arm64 hosts

Validated feature flows:

- SQLite
- PostgreSQL
- Redis
- Caddy + HTTPS
- S3 backup
- restore
- reset-db-password

## Images

- `ghcr.io/web-casa/emdash-builder:0.2.0-hi.1`
- `ghcr.io/web-casa/emdash-app:0.2.0-hi.1`
- `ghcr.io/web-casa/emdash-app:starter-sqlite-file-local-0.2.0-hi.1`

## Known Environment Caveat

One arm64 AlmaLinux 10 cloud environment showed public `80/443` interference while local HTTPS and TLS issuance succeeded. This appears to be provider or edge-network behavior rather than an installer defect.
