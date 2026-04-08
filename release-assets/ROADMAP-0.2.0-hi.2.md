# HiEmdash v0.2.0-hi.2 Development Checklist

Target: first post-release hardening cycle after `0.2.0-hi.1`

## Priority 1

- Add a `Known Issues` section to the main README
- Add release process documentation for tags, GHCR images, and release assets
- Add a reusable release checklist script or document
- Add structured result export for VPS matrix runs
- Add automated validation for GHCR image pullability after publish

## Priority 2

- Add end-to-end S3-backed media upload validation to the automated test flow
- Add automated Caddy TLS certificate renewal and restart verification
- Reduce `podman-compose` provider noise in operator-facing output
- Add optional release assets bundle generation from validation outputs
- Improve `emdashctl doctor` diagnostics for cloud-network edge cases

## Priority 3

- Add one documented `arm64` VPS matrix scenario for repeatable regression testing
- Add optional app-image profiles beyond `starter-sqlite-file-local`
- Add release-note generation from `CHANGELOG.md`
- Add backup verification helpers for restore drills
- Add machine-readable compatibility matrix documentation

## Stretch Goals

- Add a signed checksum file for release assets
- Add SBOM generation for GHCR images
- Add GitHub Actions workflow for scheduled VPS smoke validation
- Add a `known-cloud-caveats.md` document with provider-specific notes

## Exit Criteria

- `v0.2.0-hi.2` has a documented release checklist
- release assets are generated and attached automatically or near-automatically
- at least one repeatable post-publish validation job exists
- README and release docs clearly separate verified behavior from provider-specific caveats
