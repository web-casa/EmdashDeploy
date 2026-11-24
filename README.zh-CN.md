# EmdashDeploy

[English](./README.md) | **简体中文** | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [Português](./README.pt.md)

原生 VPS 安装器与运维工具集，使用 Node.js、systemd、可选 Caddy HTTPS、备份、恢复和健康检查。

## 快速开始

交互式安装：

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=zh-CN
```

只生成配置：

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=zh-CN --write-only
```

非交互安装：

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=zh-CN --non-interactive --activate
```

本地仓库方式：

```bash
git clone https://github.com/web-casa/EmdashDeploy.git
cd EmdashDeploy
chmod +x bootstrap.sh install.sh emdashctl linode-test.sh
sudo bash install.sh --lang=zh-CN --activate
```

统一入口：

- `bootstrap.sh --lang=<code>`
- `install.sh --lang=<code>`
- `emdashctl --lang=<code>`

## 说明

这个仓库把 EmDash 直接部署到 VPS 宿主机，不再走 Docker/Podman。

适合这些场景：

- 交互式安装
- 环境变量驱动的非交互安装
- 原生 Node.js + systemd 部署
- 可选 Caddy + HTTPS
- SQLite 或 PostgreSQL 18
- file session 或 Redis
- local 或 S3-compatible storage
- 备份、恢复、健康检查、升级

旧的容器版 bash 安装脚本已经归档到 `docker` 分支。对于**一台服务器需要共存多个服务或多个 EmDash 站点**的用户，`main` 分支在 [`docker/`](./docker/README.md) 目录下额外提供了轻量的 Docker Compose 多服务套件（默认不占用宿主机 `80/443`，复用同一套 EmDash `1.6.x` 补丁与运行规范）。

## 支持平台

| 系统 | 版本 | 说明 |
| --- | --- | --- |
| Debian | 13 | 原生安装 |
| Ubuntu | 24.04 | 原生安装 |
| EL-like | 9, 10 | 原生安装 |

补充：

- Node.js 24 来自 `NodeSource`，Corepack 自动尊重项目 `packageManager` 字段（如 `pnpm@11.9.0`）
- PostgreSQL 18 全平台统一来自 `PGDG`
- Session 缓存全平台统一使用 `Valkey`（Debian/Ubuntu 为 `valkey-server`，EL9/10 为 `valkey`）
- 完整适配 EmDash `1.6.x`：`EMDASH_ENCRYPTION_KEY` 生成与指纹校验、`@emdash-cms/sandbox-workerd` 插件沙箱、显式 `emdash migrate` 迁移门禁
- 大陆网络可设置 `EMDASH_MIRROR_PRESET=cn` 加速 npm/Corepack 下载（不改写宿主机全局 APT/DNF 源）

## 主要功能

- 安装脚本：[`install.sh`](./install.sh)
- 运维 CLI：[`emdashctl`](./emdashctl)
- Linode 实机测试：[`linode-test.sh`](./linode-test.sh)
- 原生 `systemd` 服务
- 原生 Caddy
- SQLite / PostgreSQL 18
- file / Redis session
- local / S3-compatible storage
- S3 backup
- `status` / `doctor` / `smoke` JSON 输出

## 非交互示例

SQLite + local：

```bash
EMDASH_INSTALL_DB_DRIVER=sqlite \
EMDASH_INSTALL_SESSION_DRIVER=file \
EMDASH_INSTALL_STORAGE_DRIVER=local \
sudo bash install.sh --lang=zh-CN --non-interactive --activate
```

PostgreSQL + Redis：

```bash
EMDASH_INSTALL_DB_DRIVER=postgres \
EMDASH_INSTALL_PG_PASSWORD='change-me-now' \
EMDASH_INSTALL_SESSION_DRIVER=redis \
EMDASH_INSTALL_REDIS_PASSWORD='change-me-too' \
sudo bash install.sh --lang=zh-CN --non-interactive --activate
```

Caddy + HTTPS：

```bash
EMDASH_INSTALL_USE_CADDY=1 \
EMDASH_INSTALL_ENABLE_HTTPS=1 \
EMDASH_INSTALL_DOMAIN=example.com \
EMDASH_INSTALL_ADMIN_EMAIL=you@example.com \
sudo bash install.sh --lang=zh-CN --non-interactive --activate
```

## 常用命令

```bash
emdashctl --lang=zh-CN status
emdashctl --lang=zh-CN doctor --deep --json
emdashctl --lang=zh-CN smoke
emdashctl --lang=zh-CN logs app
emdashctl --lang=zh-CN backup [--full] [--encrypt]
emdashctl --lang=zh-CN restore /path/to/backup.tar.gz [--with-site] [--with-secrets]
emdashctl --lang=zh-CN upgrade app [--dry-run] [--target <version|latest>]
emdashctl --lang=zh-CN template diff [--stat]
emdashctl --lang=zh-CN reset-db-password
```

说明：`upgrade app` 仅无损升级 `emdash` / `@emdash-cms/*` 依赖并在构建后执行显式数据库迁移门禁，**不再覆盖用户自定义的页面、样式与 `astro.config.mjs`**；如需对照官方模板更新，使用只读命令 `emdashctl template diff`。

## 运维示例

恢复最新备份：

```bash
latest="$(ls -1 /data/emdash/backups/emdash-backup-*.tar.gz | tail -n1)"
emdashctl --lang=zh-CN restore "$latest"
```

重置 PostgreSQL 密码：

```bash
emdashctl --lang=zh-CN reset-db-password
```

执行原生升级：

```bash
emdashctl --lang=zh-CN upgrade app
```

## 从 `docker` 分支迁移

如果你之前使用的是容器版：

1. 继续用 Docker/Podman，就留在 `docker` 分支
2. 想用原生部署，再切到 `main`
3. 注意运行模型已经变化：
   - 没有 `compose.yml`
   - 不需要容器运行时
   - 应用由 `systemd` 管理
   - PostgreSQL / Redis / Caddy 都直接安装在宿主机
4. 迁移前建议先做完整备份

## 已知限制

- `main` 不再提供 Docker/Podman 部署
- 只支持 Debian 13、Ubuntu 24.04、EL9、EL10
- 模板、插件和构建期配置变更后仍然需要 `pnpm build`
- `upgrade` 目前只支持 `app` 和 `caddy-config`
- 用户自己的脚本、用户 crontab、旧 raw URL 不会自动迁移

## 原生实测范围

- Debian 13
- Ubuntu 24.04
- EL9
- EL10
- SQLite / PostgreSQL / Redis
- Caddy + HTTPS
- S3 storage / S3 backup
- `backup` / `restore` / `upgrade app` / `reset-db-password`

详细矩阵见 [`VPS-TEST-PLAN.md`](./VPS-TEST-PLAN.md)。

更多兼容性说明见 [`COMPATIBILITY.md`](./COMPATIBILITY.md)。
