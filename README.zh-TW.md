# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | **繁體中文** | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [Português](./README.pt.md)

原生 VPS 安裝器與維運工具集，使用 Node.js、systemd、可選 Caddy HTTPS、備份、還原與健康檢查。

## 快速開始

互動式安裝：

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=zh-TW
```

只產生設定：

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=zh-TW --write-only
```

非互動安裝：

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=zh-TW --non-interactive --activate
```

## 說明

`main` 現在只保留原生部署。舊的容器版已封存到 `docker` 分支。

支援範圍：

- Debian 13
- Ubuntu 24.04
- EL9 / EL10
- SQLite / PostgreSQL 18
- file session / Redis
- local / S3-compatible storage
- Caddy + HTTPS

## 常用命令

```bash
emdashctl --lang=zh-TW status
emdashctl --lang=zh-TW doctor
emdashctl --lang=zh-TW smoke
emdashctl --lang=zh-TW backup
emdashctl --lang=zh-TW restore /path/to/backup.tar.gz
emdashctl --lang=zh-TW upgrade app
emdashctl --lang=zh-TW reset-db-password
```

## 已知限制

- `main` 不再提供 Docker/Podman 部署
- 模板、外掛與建置期設定變更後仍需 `pnpm build`
- `upgrade` 目前僅支援 `app` 與 `caddy-config`

更多說明見 [README.md](./README.md)、[`COMPATIBILITY.md`](./COMPATIBILITY.md) 與 [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md)。
