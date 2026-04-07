# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [日本語](./README.ja.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | **한국어**

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
git clone https://github.com/web-casa/EmdashDeploy.git
cd EmdashDeploy
chmod +x install-emdash.sh emdashctl linode-test.sh
sudo bash install-emdash.sh
```

즉시 활성화:

```bash
sudo bash install-emdash.sh --activate
```

## GHCR

이 저장소에는 GHCR builder 이미지를 발행하는 GitHub Actions workflow가 포함되어 있습니다.

- Workflow: [`publish-ghcr-builder.yml`](./.github/workflows/publish-ghcr-builder.yml)
- Dockerfile: [`docker/base/Dockerfile`](./docker/base/Dockerfile)
- 이미지: `ghcr.io/<repository_owner>/emdash-builder:node24-bookworm`

예시:

```bash
EMDASH_INSTALL_APP_BASE_IMAGE=ghcr.io/<owner>/emdash-builder:node24-bookworm \
sudo bash install-emdash.sh --activate
```

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
