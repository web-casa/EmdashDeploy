# EmDash Installer

这个目录现在是新的 EmDash 容器化安装器基础版，而不是旧的单机 Node.js + systemd 脚本。

核心文件：

- [install-emdash.sh](./install-emdash.sh)
- [emdashctl](./emdashctl)
- [linode-test.sh](./linode-test.sh)
- [VPS-TEST-PLAN.md](./VPS-TEST-PLAN.md)
- [docker/base/Dockerfile](./docker/base/Dockerfile)
- [publish-ghcr-builder.yml](./.github/workflows/publish-ghcr-builder.yml)

模块目录：

- [lib/common.sh](./lib/common.sh)
- [lib/config.sh](./lib/config.sh)
- [lib/os.sh](./lib/os.sh)
- [lib/prompt.sh](./lib/prompt.sh)
- [lib/network.sh](./lib/network.sh)
- [lib/render.sh](./lib/render.sh)

## 当前实现范围

- 支持 Debian 12/13、Ubuntu 22/24、EL 8/9/10
- Debian/Ubuntu 走 Docker
- EL 系走 Podman
- 支持自动安装 Docker / Podman 运行时
- 支持自动安装宿主机 Caddy
- 启用 Caddy 时会自动处理宿主机防火墙放行
- 支持 EmDash 模板拉取和自动改写
- 支持 SQLite / PostgreSQL 18
- 支持 file-based / Redis session
- 支持 local / S3-compatible storage
- 支持多源公网 IP 探测
- 支持生成 `/data/emdash` 目录布局
- 支持生成 `/etc/emdash/install.yml` 和 `compose.env`
- 支持生成 compose 配置和 Caddyfile
- 提供 `emdashctl` 基础命令

## 当前默认目录

- 根目录：`/data/emdash`
- 配置目录：`/etc/emdash`
- 管理工具：`/usr/local/bin/emdashctl`

## 当前命令

```bash
chmod +x install-emdash.sh emdashctl
sudo bash install-emdash.sh
sudo bash install-emdash.sh --activate
sudo bash install-emdash.sh --write-only
bash linode-test.sh
```

`emdashctl` 当前支持：

```bash
emdashctl status
emdashctl status --json
emdashctl smoke
emdashctl smoke --json
emdashctl logs app
emdashctl restart app
emdashctl backup
emdashctl restore /path/to/backup.tar.gz
emdashctl upgrade app
emdashctl upgrade redis
emdashctl upgrade caddy-config
emdashctl reset-db-password
emdashctl doctor
emdashctl doctor --json
```

## GHCR 托管

现在安装器支持两种与 GHCR 相关的用法：

1. 使用 GHCR 上的预构建 app 镜像
2. 使用 GHCR 上的 builder 基础镜像，加速本地 build

如果你已经有预构建 app 镜像：

```bash
EMDASH_INSTALL_APP_IMAGE=ghcr.io/<owner>/<image>:<tag> \
sudo bash install-emdash.sh --activate
```

行为：

- 安装器会优先 `pull` 这个 app 镜像
- 拉取成功则直接 `up -d`
- 拉取失败则自动回退到本地 `build`

如果你只想先把 builder 基础镜像托管到 GHCR：

```bash
EMDASH_INSTALL_APP_BASE_IMAGE=ghcr.io/<owner>/emdash-builder:node24-bookworm \
sudo bash install-emdash.sh --activate
```

对应的 GitHub Actions workflow 在 [publish-ghcr-builder.yml](./.github/workflows/publish-ghcr-builder.yml)，会把 [docker/base/Dockerfile](./docker/base/Dockerfile) 发布到：

```text
ghcr.io/<repository_owner>/emdash-builder:node24-bookworm
```

注意：

- `APP_IMAGE` 适合已经固定好模板和构建产物的场景
- `APP_BASE_IMAGE` 适合先托管通用 Node 24 builder 层，减少远端构建耗时
- 当前 EmDash 的数据库/存储配置仍是在站点构建时写入，所以预构建 app 镜像必须和实际渲染出来的站点配置匹配

## VPS 实测方案

完整的直接实测矩阵、命令和验收标准见 [VPS-TEST-PLAN.md](./VPS-TEST-PLAN.md)。

## HTTPS 测试方式

使用 `linode-test.sh` 可以直接验证 `Caddy + 域名 + HTTPS` 链路。脚本会在启用 Caddy 时自动把实例公网 IP 组装成测试域名。

`sslip.io` 示例：

```bash
LINODE_TEST_INSTALL_USE_CADDY=1 \
LINODE_TEST_INSTALL_ENABLE_HTTPS=1 \
LINODE_TEST_DOMAIN_PROVIDER=sslip.io \
bash linode-test.sh
```

`nip.io` 示例：

```bash
LINODE_TEST_INSTALL_USE_CADDY=1 \
LINODE_TEST_INSTALL_ENABLE_HTTPS=1 \
LINODE_TEST_DOMAIN_PROVIDER=nip.io \
bash linode-test.sh
```

也可以显式指定 region。当前 `linode-test.sh` 默认优先使用美国区域：

```bash
LINODE_TEST_REGION_CANDIDATES=us-lax,us-west,us-east bash linode-test.sh
```

## 当前限制

- 已接入 Docker / Podman / Caddy 的自动安装逻辑，但还没有在所有目标发行版上做完整实机回归
- 启用 Caddy 时，安装器会先校验域名解析和 `80/443` 端口占用；校验失败会直接终止安装
- EL 系启用 Caddy 时，会自动通过 `firewalld` 放行 `80/tcp` 和 `443/tcp`；如果未启用 `firewalld`，则不会额外创建防火墙规则
- Debian / Ubuntu 上如果启用了 `ufw`，安装器会自动放行 `80/tcp` 和 `443/tcp`
- `emdashctl backup` 已接入本地打包和 SFTP / S3-compatible 上传；SFTP 密码认证依赖 `sshpass`
- `emdashctl status` 已支持 `--json`，`doctor` 已支持文本和 JSON 输出，并能检查数据库目录、sessions 目录、app health、setup API、Caddy 配置和备份计划
- `emdashctl smoke` 已支持文本和 JSON 输出，并会对运行时、容器、数据库、session、app health、setup API、Caddy 做一次严格探测；关键项失败时返回非零退出码
- `linode-test.sh` 会从当前目录 `.env` 读取 `linode_token`，仓库内提供了 [.env.example](./.env.example) 作为示例；脚本会创建临时 Linode VPS，推送当前安装器并执行一轮非交互安装和 smoke 测试；启用 Caddy 时可自动生成 `nip.io` / `sslip.io` 测试域名；默认按 `us-lax,us-west,us-east` 依次尝试；默认测试后自动销毁，`--keep` 或 `LINODE_TEST_KEEP=1` 可保留实例
- `--activate` 结束后会等待 `/health`，并尝试抓取 setup 状态写入 `${ROOT_DIR}/setup-status.json`
- 如果选择对象存储，安装器会用 `amazon/aws-cli` 容器做上传测试，因此本机必须先有 Docker 或 Podman
- EL 系的 compose provider 仍依赖 `podman compose` 或 `podman-compose`；脚本会自动检测并尽量安装可用 provider
- `--write-only` 模式只生成配置，不安装运行时、不做对象存储上传测试、不安装 Caddy

## 设计约束

- 不支持 Turso / libSQL
- 不支持 SLES family
- `reset-db-password` 只支持 PostgreSQL
- `upgrade` 只支持 `app`、`redis`、`caddy-config`
- SQLite 和 Caddy 不做激进调优
