# EmdashDeploy

[English](./README.md) | **简体中文** | [日本語](./README.ja.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [한국어](./README.ko.md)

EmDash 的交互式 VPS 安装器与运维工具集，支持 Docker/Podman、可选 Caddy HTTPS、备份、恢复和健康检查。

## 这个仓库是做什么的

这个仓库用于把 EmDash 部署到 VPS，并提供安装后的基础运维能力。

适合以下场景：

- 想用交互式安装
- 想通过环境变量做非交互部署
- Debian/Ubuntu 上用 Docker
- EL 系统上用 Podman
- 需要可选的 Caddy 和 HTTPS
- 需要备份、恢复、健康检查和基础升级命令

## 主要功能

- 安装脚本：[`install-emdash.sh`](./install-emdash.sh)
- 运维 CLI：[`emdashctl`](./emdashctl)
- Linode 实机测试脚本：[`linode-test.sh`](./linode-test.sh)
- 宿主机原生安装 Caddy
- 支持 SQLite / PostgreSQL 18
- 支持 file-based / Redis session
- 支持 local / S3-compatible storage
- 支持多源公网 IP 探测
- 运行目录默认在 `/data/emdash`
- 配置目录默认在 `/etc/emdash`

## 支持的平台

| 系统 | 版本 | 运行时 |
| --- | --- | --- |
| Debian | 12, 13 | Docker |
| Ubuntu | 22.04, 24.04 | Docker |
| EL-like | 8, 9, 10 | Podman |

说明：

- 不支持 SLES family
- 不支持 Turso / libSQL

## 快速开始

```bash
git clone https://github.com/web-casa/EmdashDeploy.git
cd EmdashDeploy
chmod +x install-emdash.sh emdashctl linode-test.sh
sudo bash install-emdash.sh
```

立即激活：

```bash
sudo bash install-emdash.sh --activate
```

只生成配置：

```bash
sudo bash install-emdash.sh --write-only
```

## 非交互示例

SQLite：

```bash
EMDASH_INSTALL_DB_DRIVER=sqlite \
EMDASH_INSTALL_SESSION_DRIVER=file \
EMDASH_INSTALL_STORAGE_DRIVER=local \
sudo bash install-emdash.sh --non-interactive --activate
```

PostgreSQL + Redis：

```bash
EMDASH_INSTALL_DB_DRIVER=postgres \
EMDASH_INSTALL_PG_PASSWORD='change-me-now' \
EMDASH_INSTALL_SESSION_DRIVER=redis \
EMDASH_INSTALL_REDIS_PASSWORD='change-me-too' \
sudo bash install-emdash.sh --non-interactive --activate
```

## Caddy 与 HTTPS

启用 Caddy 后，安装器会：

- 多源检测公网 IP
- 校验 DNS
- 检查 `80/443`
- 在宿主机安装 Caddy
- 配置 HTTPS

防火墙说明：

- EL 系统启用 Caddy 时，会自动通过 `firewalld` 放行 `80/tcp` 和 `443/tcp`
- Debian/Ubuntu 如果启用了 `ufw`，也会自动放行 `80/tcp` 和 `443/tcp`

## GHCR 发布说明

仓库内已经包含 GHCR builder 镜像发布工作流：

- Workflow: [`publish-ghcr-builder.yml`](./.github/workflows/publish-ghcr-builder.yml)
- Dockerfile: [`docker/base/Dockerfile`](./docker/base/Dockerfile)
- 镜像名：`ghcr.io/<repository_owner>/emdash-builder:node24-bookworm`

触发条件：

- `main` 分支上的 `docker/base/Dockerfile` 变更
- `main` 分支上的 workflow 文件变更
- 手工 `workflow_dispatch`

使用 GHCR builder 镜像：

```bash
EMDASH_INSTALL_APP_BASE_IMAGE=ghcr.io/<owner>/emdash-builder:node24-bookworm \
sudo bash install-emdash.sh --activate
```

使用预构建 app 镜像：

```bash
EMDASH_INSTALL_APP_IMAGE=ghcr.io/<owner>/<image>:<tag> \
sudo bash install-emdash.sh --activate
```

注意：

- 想匿名拉取时，需要把 GHCR package 设为 public
- 私有镜像需要先在 VPS 上登录 `ghcr.io`

## 实机测试

先准备 `.env`：

```bash
cp .env.example .env
```

写入：

```bash
linode_token=YOUR_TOKEN_HERE
```

运行：

```bash
bash linode-test.sh
```

HTTPS 测试：

```bash
LINODE_TEST_INSTALL_USE_CADDY=1 \
LINODE_TEST_INSTALL_ENABLE_HTTPS=1 \
LINODE_TEST_DOMAIN_PROVIDER=sslip.io \
bash linode-test.sh
```

更多测试矩阵见 [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md)。
