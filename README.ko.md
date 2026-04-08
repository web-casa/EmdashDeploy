# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | **한국어** | [Español](./README.es.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [Português](./README.pt.md)

Docker/Podman, 선택적 Caddy HTTPS, 백업, 복구, 헬스 체크를 지원하는 EmDash용 대화형 VPS 설치 및 운영 도구입니다.

## 저장소 목적

이 저장소는 EmDash를 VPS에 배포하고, 설치 후 운영에 필요한 기본 기능을 제공합니다.

## 주요 기능

- 설치 스크립트: [`install-emdash.sh`](./install-emdash.sh)
- 운영 CLI: [`emdashctl`](./emdashctl)
- Linode 실서버 테스트 스크립트: [`linode-test.sh`](./linode-test.sh)
- SQLite / PostgreSQL 18
- file-based / Redis 세션
- local / S3-compatible 스토리지
- 호스트 네이티브 Caddy 선택 지원

## 지원 플랫폼

| 시스템 | 버전 | 런타임 |
| --- | --- | --- |
| Debian | 12, 13 | Docker |
| Ubuntu | 22.04, 24.04 | Docker |
| EL-like | 8, 9, 10 | Podman |

지원하지 않음:

- SLES 계열
- Turso / libSQL

## 빠른 시작

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.ko.sh | sudo bash
```

설정 파일만 생성:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.ko.sh | sudo bash -s -- --write-only
```

## GHCR

이 저장소에는 GHCR builder 이미지와 기본 app 이미지를 발행하는 GitHub Actions workflow가 포함되어 있습니다.

- Workflow: [`publish-ghcr-builder.yml`](./.github/workflows/publish-ghcr-builder.yml)
- Workflow: [`publish-ghcr-app.yml`](./.github/workflows/publish-ghcr-app.yml)
- Dockerfile: [`docker/base/Dockerfile`](./docker/base/Dockerfile)
- builder 이미지: `ghcr.io/<repository_owner>/emdash-builder:node24-bookworm`
- 기본 app 이미지: `ghcr.io/<repository_owner>/emdash-app:starter-sqlite-file-local`

builder 와 app 의 차이:

- `builder` 는 재사용 가능한 빌드 환경 이미지입니다.
- `app` 는 이미 빌드된 런타임 이미지입니다.

`builder` 를 쓰기 좋은 경우:

- VPS에서 사이트를 직접 빌드하고 싶을 때
- PostgreSQL, Redis, S3 호환 스토리지를 사용할 때
- 템플릿을 수정했거나 유연성을 우선할 때

`app` 을 쓰기 좋은 경우:

- 가장 빠른 배포 경로를 원할 때
- VPS에서 로컬 앱 빌드를 생략하고 싶을 때
- 기본 공개 프로필 `starter + sqlite + file + local` 을 사용할 때

예시:

```bash
EMDASH_INSTALL_APP_BASE_IMAGE=ghcr.io/<owner>/emdash-builder:node24-bookworm \
sudo bash install-emdash.ko.sh --activate
```

사전 빌드된 app 이미지 사용 예시:

```bash
EMDASH_INSTALL_APP_IMAGE=ghcr.io/<owner>/emdash-app:starter-sqlite-file-local \
sudo bash install-emdash.ko.sh --activate
```

권장:

- 일반적이거나 커스텀된 배포는 `APP_BASE_IMAGE` 를 우선하세요
- 기본 SQLite/file/local 프로필은 `APP_IMAGE` 를 우선하세요

## HTTPS

Caddy를 활성화하면 설치기가 공인 IP 감지, DNS 검증, `80/443` 확인, 호스트 Caddy 설치, HTTPS 설정을 수행합니다.

EL에서는 `firewalld`, Debian/Ubuntu에서는 활성화된 `ufw`에 대해 자동으로 포트를 엽니다.

## VPS 테스트

```bash
cp .env.example .env
```

그 다음:

```bash
linode_token=YOUR_TOKEN_HERE
```

실행:

```bash
bash linode-test.sh
```

자세한 테스트 매트릭스는 [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md)를 참고하세요.

운영 명령은 한국어 wrapper를 사용할 수 있습니다:

```bash
emdashctl.ko.sh status
emdashctl.ko.sh doctor
emdashctl.ko.sh smoke
emdashctl.ko.sh logs app -f
emdashctl.ko.sh backup
emdashctl.ko.sh restore /path/to/backup.tar.gz
```
