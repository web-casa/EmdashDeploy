# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | **繁體中文** | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [Português](./README.pt.md)

原生 VPS 安裝器與維運工具集，使用 Node.js 24、systemd、可選 Caddy HTTPS、備份、還原、AI 一鍵診斷與安全金鑰輪替。

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

`main` 以原生主機部署為主；若同一伺服器需共存多個服務或多個 EmDash 站點，亦於 [`docker/`](./docker/README.md) 提供輕量多服務 Docker Compose 套件（含 GHCR 原生多架構映像 `amd64`/`arm64`，預設不佔用 80/443）。舊版容器腳本封存於 `docker` 分支。

支援範圍（`x86_64` 與 `aarch64`）：

- Debian 13 (`trixie`)
- Ubuntu 24.04 LTS (`noble`) / 26.04 LTS (`resolute`)
- EL9 / EL10 (Rocky / AlmaLinux / CentOS Stream)
- SQLite / PostgreSQL 18 (PGDG)
- file session / Valkey
- local / S3-compatible storage
- Caddy + HTTPS
- EmDash `1.6.x`：`EMDASH_ENCRYPTION_KEY`、外掛沙箱 `@emdash-cms/sandbox-workerd`、顯式 `emdash migrate` 門禁、`EMDASH_MIRROR_PRESET=cn`

## 常用命令

```bash
emdashctl --lang=zh-TW status [--json]
emdashctl --lang=zh-TW doctor --deep --json
emdashctl --lang=zh-TW diagnose --json --out /tmp/emdash-diag.json
emdashctl --lang=zh-TW smoke [--json]
emdashctl --lang=zh-TW backup [--full] [--encrypt]
emdashctl --lang=zh-TW restore /path/to/backup.tar.gz [--with-site] [--with-secrets]
emdashctl --lang=zh-TW instances [--json]
emdashctl --lang=zh-TW [--instance <name>] upgrade app [--dry-run] [--target <version|latest>]
emdashctl --lang=zh-TW [--instance <name>] template diff [--stat]
emdashctl --lang=zh-TW [--instance <name>] rotate-encryption-key [--status | --dry-run | --prune-old --confirm-prune-kid <kid>]
emdashctl --lang=zh-TW [--instance <name>] migrate-db sqlite-to-postgres [--dry-run] [--yes]
emdashctl --lang=zh-TW [--instance <name>] reset-db-password
emdashctl --lang=zh-TW [--instance <name>] uninstall [--purge-data] [--drop-db] [--confirm-instance <name>]
sudo bash install.sh --update-cli
```

## 實測邊界與限制

- Debian 13 / Ubuntu 24.04 / Ubuntu 26.04 / EL9 / EL10 已於 `x86_64` 實機驗證；`ARM64` 多架構容器映像與 `workerd` 由 GitHub Actions `ubuntu-24.04-arm` 原生驗證。
- 範本、外掛與建置期設定變更後仍需 `pnpm build`。
- `upgrade` 目前僅支援 `app` 與 `caddy-config`。

更多說明見 [README.md](./README.md)、[`docker/README.md`](./docker/README.md)、[`COMPATIBILITY.md`](./COMPATIBILITY.md) 與 [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md)。
