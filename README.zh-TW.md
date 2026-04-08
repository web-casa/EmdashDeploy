# EmdashDeploy

[English](./README.md) | [简体中文](./README.zh-CN.md) | **繁體中文** | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [Português](./README.pt.md)

EmDash 的互動式 VPS 安裝器與維運工具集，支援 Docker/Podman、可選的 Caddy HTTPS、備份、還原與健康檢查。

## 快速開始

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.zh-TW.sh | sudo bash
```

只產生設定：

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.zh-TW.sh | sudo bash -s -- --write-only
```

非互動安裝：

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.zh-TW.sh | sudo bash -s -- --non-interactive
```

非互動模式，SQLite：

```bash
EMDASH_INSTALL_DB_DRIVER=sqlite \
EMDASH_INSTALL_SESSION_DRIVER=file \
EMDASH_INSTALL_STORAGE_DRIVER=local \
sudo bash install-emdash.zh-TW.sh --non-interactive --activate
```

非互動模式，PostgreSQL + Redis：

```bash
EMDASH_INSTALL_DB_DRIVER=postgres \
EMDASH_INSTALL_PG_PASSWORD='change-me-now' \
EMDASH_INSTALL_SESSION_DRIVER=redis \
EMDASH_INSTALL_REDIS_PASSWORD='change-me-too' \
sudo bash install-emdash.zh-TW.sh --non-interactive --activate
```

完整文件請參考英文版：[README.md](./README.md)

維運命令建議使用繁體中文 wrapper：

```bash
emdashctl.zh-TW.sh status
emdashctl.zh-TW.sh doctor
emdashctl.zh-TW.sh smoke
emdashctl.zh-TW.sh logs app -f
emdashctl.zh-TW.sh backup
emdashctl.zh-TW.sh restore /path/to/backup.tar.gz
```
