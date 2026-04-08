# Changelog

All notable changes to this project are documented in this file.

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
