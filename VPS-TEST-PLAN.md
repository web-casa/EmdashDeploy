# VPS Test Plan

这份文档用于执行 EmDash 安装器的直接 VPS 实测，目标是把当前高风险路径逐项跑通，而不是只做语法检查。

## 目标

- 验证 `install-emdash.sh` 的真实安装链路
- 验证 `emdashctl` 的高风险运维命令
- 验证 `Docker` 和 `Podman` 两条运行时分支
- 验证 `SQLite`、`PostgreSQL`、`Redis`、`Caddy + HTTPS`、`S3 preflight`、`SFTP backup`
- 验证最近修过的问题没有回归

## 测试原则

- 先跑自动化矩阵，再做需要人工介入的命令级验证
- 每个高风险能力至少在一台真实 VPS 上跑一次
- 对破坏性命令，优先在保留实例上验证
- 每轮测试都保留：
  - `emdashctl status --json`
  - `emdashctl doctor --json`
  - `emdashctl smoke --json`
  - 失败时的容器日志和 `journalctl -u caddy`

## 前置准备

1. 本地准备 `.env`

```bash
linode_token=...
```

2. 如需测试 SFTP 备份，准备一台可写入的 SFTP 目标

3. 如需测试 S3 预检或备份上传，准备一组 S3-compatible 凭据

4. 默认 region 使用美西优先：

```bash
export LINODE_TEST_REGION_CANDIDATES=us-lax,us-west,us-east
```

5. 可选：直接使用预定义矩阵脚本跑自动化组合

```bash
bash linode-test-matrix.sh
```

只跑部分场景：

```bash
bash linode-test-matrix.sh --scenario debian13-caddy-app,centos9-builder
```

输出内容：

- 每个场景一个结果 JSON
- 每个失败场景一个 failure log
- 一份汇总 JSON
- 一份汇总 Markdown

## 自动化测试矩阵

### A 组：基础安装链路

#### A1. Ubuntu 24 + SQLite + file session + local storage

```bash
LINODE_TEST_IMAGE=linode/ubuntu24.04 \
LINODE_TEST_INSTALL_DB_DRIVER=sqlite \
LINODE_TEST_INSTALL_SESSION_DRIVER=file \
LINODE_TEST_INSTALL_STORAGE_DRIVER=local \
LINODE_TEST_INSTALL_USE_CADDY=0 \
bash linode-test.sh
```

验收：

- 安装完成
- `emdashctl smoke --json` 通过
- `APP_PUBLIC_URL` 指向公网 IP，而不是 `127.0.0.1`

#### A2. CentOS Stream 9 + SQLite + file session + local storage

```bash
LINODE_TEST_IMAGE=linode/centos-stream9 \
LINODE_TEST_INSTALL_DB_DRIVER=sqlite \
LINODE_TEST_INSTALL_SESSION_DRIVER=file \
LINODE_TEST_INSTALL_STORAGE_DRIVER=local \
LINODE_TEST_INSTALL_USE_CADDY=0 \
bash linode-test.sh
```

验收：

- Podman 路线安装完成
- `emdashctl smoke --json` 通过

### B 组：数据库与 Session 组合

#### B1. Ubuntu 24 + PostgreSQL + file session

```bash
LINODE_TEST_IMAGE=linode/ubuntu24.04 \
LINODE_TEST_INSTALL_DB_DRIVER=postgres \
LINODE_TEST_INSTALL_SESSION_DRIVER=file \
LINODE_TEST_INSTALL_PG_PASSWORD='Pg-Test-123_Complex@Value' \
bash linode-test.sh
```

验收：

- 安装完成
- 复杂密码连接串正常
- `/_emdash/api/setup/status` 正常返回

#### B2. CentOS Stream 9 + PostgreSQL + Redis

```bash
LINODE_TEST_IMAGE=linode/centos-stream9 \
LINODE_TEST_INSTALL_DB_DRIVER=postgres \
LINODE_TEST_INSTALL_SESSION_DRIVER=redis \
LINODE_TEST_INSTALL_PG_PASSWORD='Pg-Test-123_Complex@Value' \
LINODE_TEST_INSTALL_REDIS_PASSWORD='Redis-Test-123:@Value' \
bash linode-test.sh
```

验收：

- Podman 路线正常
- PostgreSQL 与 Redis 同时工作
- `emdashctl doctor --json` 中 `postgres connect` 与 `redis ping` 都为 `ok`

### C 组：Caddy + HTTPS

#### C1. Ubuntu 24 + Caddy + HTTPS + sslip.io

```bash
LINODE_TEST_IMAGE=linode/ubuntu24.04 \
LINODE_TEST_INSTALL_USE_CADDY=1 \
LINODE_TEST_INSTALL_ENABLE_HTTPS=1 \
LINODE_TEST_DOMAIN_PROVIDER=sslip.io \
bash linode-test.sh
```

验收：

- `https://<domain>/__emdash_health` 正常
- `emdashctl doctor --json` 中 `tls cert` 为 `ok`
- `caddy service` 为 `ok`

#### C2. CentOS Stream 9 + Caddy + HTTPS + nip.io

```bash
LINODE_TEST_IMAGE=linode/centos-stream9 \
LINODE_TEST_INSTALL_USE_CADDY=1 \
LINODE_TEST_INSTALL_ENABLE_HTTPS=1 \
LINODE_TEST_DOMAIN_PROVIDER=nip.io \
bash linode-test.sh
```

验收：

- EL 防火墙自动放行有效
- `tls cert` 为 `ok`
- `smoke` 通过

## 保留实例上的人工验证

下面几项不适合直接塞进一次性 smoke，建议使用 `--keep` 保留实例后在远端手工验证。

### D1. `reset-db-password`

目的：

- 验证 PostgreSQL 密码重置
- 验证重建后的 app 能继续连库

创建保留实例：

```bash
LINODE_TEST_KEEP=1 \
LINODE_TEST_IMAGE=linode/ubuntu24.04 \
LINODE_TEST_INSTALL_DB_DRIVER=postgres \
LINODE_TEST_INSTALL_SESSION_DRIVER=file \
LINODE_TEST_INSTALL_PG_PASSWORD='Pg-Test-123_Complex@Value' \
bash linode-test.sh
```

远端执行：

```bash
emdashctl reset-db-password
emdashctl status --json
emdashctl doctor --json
emdashctl smoke --json
```

验收：

- `reset-db-password` 成功
- app 重建后仍健康
- setup API 仍可访问

### D2. PostgreSQL restore

目的：

- 验证“临时库导入 -> 正式库切换 -> 旧库清理”流程

远端执行：

```bash
emdashctl backup
ls -1 /data/emdash/backups/emdash-backup-*.tar.gz | tail -n1
emdashctl restore /data/emdash/backups/<backup-file>.tar.gz
emdashctl smoke --json
```

验收：

- restore 成功
- app 恢复后正常
- `postgres connect` 正常

### D3. SQLite restore

目的：

- 验证 `integrity_check`
- 验证恢复前清理 `-wal/-shm`

创建保留实例：

```bash
LINODE_TEST_KEEP=1 \
LINODE_TEST_IMAGE=linode/ubuntu24.04 \
LINODE_TEST_INSTALL_DB_DRIVER=sqlite \
LINODE_TEST_INSTALL_SESSION_DRIVER=file \
bash linode-test.sh
```

远端执行：

```bash
emdashctl backup
ls -1 /data/emdash/backups/emdash-backup-*.tar.gz | tail -n1
emdashctl restore /data/emdash/backups/<backup-file>.tar.gz
emdashctl smoke --json
```

验收：

- restore 成功
- app 正常
- SQLite 文件存在且无旧 WAL 污染症状

### D4. SFTP backup

目的：

- 验证首次上传时自动创建远端目录

创建保留实例：

```bash
LINODE_TEST_KEEP=1 \
LINODE_TEST_IMAGE=linode/ubuntu24.04 \
LINODE_TEST_INSTALL_DB_DRIVER=sqlite \
LINODE_TEST_INSTALL_SESSION_DRIVER=file \
bash linode-test.sh
```

远端先改 `/etc/emdash/compose.env` 或重装时带入：

- `BACKUP_TARGET_TYPE=sftp`
- `BACKUP_SFTP_HOST`
- `BACKUP_SFTP_PORT`
- `BACKUP_SFTP_USER`
- `BACKUP_SFTP_PASSWORD` 或密钥认证
- `BACKUP_SFTP_REMOTE_PATH`

然后执行：

```bash
emdashctl backup
```

验收：

- 远端目录自动创建
- 首次上传成功
- 本地备份仍保留

### D5. S3-compatible storage preflight

目的：

- 验证对象存储上传预检
- 验证 EL + Podman + SELinux `:Z` 挂载

建议测试机型：

- `Ubuntu 24`
- `CentOS Stream 9`

示例：

```bash
LINODE_TEST_IMAGE=linode/centos-stream9 \
LINODE_TEST_INSTALL_STORAGE_DRIVER=s3 \
EMDASH_INSTALL_STORAGE_DRIVER=s3 \
bash linode-test.sh
```

说明：

- 当前 `linode-test.sh` 没有把 S3 测试参数完全透传；这项建议先手工在保留实例上执行安装器验证
- 重点看 `test_s3_storage` 是否通过

## 推荐执行顺序

1. A1
2. A2
3. B1
4. B2
5. C1
6. C2
7. D1
8. D2
9. D3
10. D4
11. D5

这样可以先确认“安装主链路”，再做破坏性运维命令验证。

## 统一验收标准

每个用例至少满足：

- 安装命令返回 0
- `emdashctl status --json` 返回 0
- `emdashctl doctor --json` 返回 0
- `emdashctl smoke --json` 返回 0
- `/_emdash/api/setup/status` 可访问

如果启用了 Caddy + HTTPS，还必须满足：

- `tls cert` 为 `ok`
- `https://<domain>/__emdash_health` 正常

## 失败留证

自动化失败时保留：

- `linode-test-failure.log`
- 结果 JSON
- 远端：
  - `docker/podman compose ps`
  - `docker/podman compose logs app`
  - `emdashctl doctor --json`
  - `journalctl -u caddy`

人工验证失败时补充：

```bash
emdashctl logs app
emdashctl logs postgres
emdashctl logs redis
journalctl -u caddy -n 200 --no-pager
```

## 当前最值得优先实测的 3 项

- `B1`: 复杂 PostgreSQL 密码的连接串正确性
- `D2`: PostgreSQL restore 切换流程
- `D4`: SFTP 首次上传自动建目录
