# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | **한국어** | [Español](./README.es.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [Português](./README.pt.md)

Node.js 24와 systemd 기반의 EmDash `1.6.x` 네이티브 VPS 설치 및 운영 도구입니다.

## 빠른 시작

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=ko
```

설정만 생성:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=ko --write-only
```

비대화형 설치:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=ko --non-interactive --activate
```

## 요약

`main` 브랜치는 EmDash를 VPS 호스트에 직접 설치하는 네이티브 배포가 기본이며, 한 서버에서 여러 서비스나 다중 EmDash 사이트를 공존시키려는 경우를 위해 [`docker/`](./docker/README.md) 경량 Docker Compose 키트(GHCR 네이티브 멀티아키텍처 `amd64`/`arm64` 이미지, 기본 80/443 미점유)도 함께 제공합니다. 이전 컨테이너 설치 스크립트는 `docker` 브랜치에 보관되어 있습니다.

지원 범위 (`x86_64` / `aarch64`):

- Debian 13 (`trixie`)
- Ubuntu 24.04 LTS (`noble`) / 26.04 LTS (`resolute`)
- EL9 / EL10
- SQLite / PostgreSQL 18 (PGDG)
- file session / Valkey
- local / S3-compatible storage, Caddy + HTTPS
- EmDash `1.6.x`: `EMDASH_ENCRYPTION_KEY` 2단계 키 로테이션, `@emdash-cms/sandbox-workerd` 플러그인 샌드박스, `emdash migrate` 게이트, `EMDASH_MIRROR_PRESET=cn`

## 주요 명령

```bash
emdashctl --lang=ko status [--json]
emdashctl --lang=ko doctor --deep --json
emdashctl --lang=ko diagnose --json --out /tmp/emdash-diag.json
emdashctl --lang=ko smoke [--json]
emdashctl --lang=ko backup [--full] [--encrypt]
emdashctl --lang=ko restore /path/to/backup.tar.gz [--with-site] [--with-secrets]
emdashctl --lang=ko instances [--json]
emdashctl --lang=ko [--instance <name>] upgrade app [--dry-run] [--target <version|latest>]
emdashctl --lang=ko [--instance <name>] template diff [--stat]
emdashctl --lang=ko [--instance <name>] rotate-encryption-key [--status | --dry-run | --prune-old --confirm-prune-kid <kid>]
emdashctl --lang=ko [--instance <name>] migrate-db sqlite-to-postgres [--dry-run] [--yes]
emdashctl --lang=ko [--instance <name>] reset-db-password
emdashctl --lang=ko [--instance <name>] uninstall [--purge-data] [--drop-db] [--confirm-instance <name>]
sudo bash install.sh --update-cli
```

## 검증 범위 및 제한

- Debian 13 / Ubuntu 24.04 / Ubuntu 26.04 / EL9 / EL10은 `x86_64` 실서버 VM에서 검증되었으며, `ARM64` 컨테이너 이미지와 `workerd`는 GitHub Actions `ubuntu-24.04-arm`에서 네이티브 검증됩니다.
- 템플릿, 플러그인, 빌드 설정 변경 후에는 `pnpm build`가 필요합니다.
- `upgrade`는 현재 `app`과 `caddy-config`만 지원합니다.

추가 설명은 [README.md](./README.md), [`docker/README.md`](./docker/README.md), [`COMPATIBILITY.md`](./COMPATIBILITY.md), [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md)를 참고하세요.
