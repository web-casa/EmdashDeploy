# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | **한국어** | [Español](./README.es.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [Português](./README.pt.md)

Node.js와 systemd 기반의 EmDash 네이티브 VPS 설치 및 운영 도구입니다.

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

`main` 브랜치는 EmDash를 VPS 호스트에 직접 설치하는 네이티브 배포용입니다. 이전 컨테이너 기반 구현은 `docker` 브랜치에 보관되어 있습니다.

지원 범위:

- Debian 13
- Ubuntu 24.04
- EL9 / EL10
- SQLite / PostgreSQL 18
- file session / Redis
- local / S3-compatible storage
- Caddy + HTTPS

## 주요 명령

```bash
emdashctl --lang=ko status
emdashctl --lang=ko doctor
emdashctl --lang=ko smoke
emdashctl --lang=ko backup
emdashctl --lang=ko restore /path/to/backup.tar.gz
emdashctl --lang=ko upgrade app
emdashctl --lang=ko reset-db-password
```

## 알려진 제한

- `main` 은 더 이상 Docker/Podman 배포를 제공하지 않습니다
- 템플릿, 플러그인, 빌드 설정 변경 후에는 여전히 `pnpm build` 가 필요합니다
- `upgrade` 는 현재 `app` 과 `caddy-config` 만 지원합니다

추가 설명은 [README.md](./README.md), [`COMPATIBILITY.md`](./COMPATIBILITY.md), [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md) 를 참고하세요.
