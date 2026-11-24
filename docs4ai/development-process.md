# EmDash 安装器与运维链路开发过程整理

更新时间：2026-04-14

## 背景

这一轮开发围绕以下实际问题展开：

1. 新安装实例在 Setup Wizard 创建 passkey 时，浏览器报错：
   - `'rp.id' cannot be used with the current origin`
2. 某些重装/升级实例前台样式异常，看起来像 CSS/JS 没正常加载。
3. 安装器在“保留现有站点源码”与“写入新运行时配置”之间存在混合状态，容易把旧模板源码与新配置拼到一起。
4. `emdashctl upgrade app` 与安装器逻辑分叉，可能重新引入已修复的问题。
5. 激活失败与升级失败的回滚边界不完整，会留下半迁移状态。

## 最终状态与约束

截至本次整理，代码应满足以下约束：

### 1. public origin / passkey

- 安装器写入：
  - `APP_PUBLIC_URL`
  - `EMDASH_SITE_URL`
  - `SITE_URL`
- 运行时通过 `EMDASH_SITE_URL` / `SITE_URL` 为 EmDash 提供公开 `siteUrl`。
- 该约束同时覆盖：
  - passkey 创建
  - passkey 登录
  - OAuth / 重定向
  - 依赖公开 origin 的 API 行为

### 2. 模板同步策略

- 如果 `SITE_DIR` 不存在现有站点源码，安装器同步所选模板。
- 如果 `SITE_DIR` 已存在站点源码：
  - 默认进入 `preserve` 模式
  - 不再修改现有 `astro.config.mjs`
  - 不再修改现有 `package.json`
  - 不再覆盖现有 `healthz` 路由
- 如果检测到模板或驱动不匹配：
  - 直接失败
  - 不允许“旧 site + 新 runtime”混装
- 如需强制覆盖，必须显式设置：
  - `EMDASH_INSTALL_FORCE_SYNC_TEMPLATE=1`

### 3. `astro.config.mjs` 管理方式

- 不再整份重写 `astro.config.mjs`
- 只对同步下来的模板配置做定向补丁
- 必须保留模板自带：
  - 插件
  - 字体
  - 其它模板级配置
- 同时注入安装器托管项：
  - `siteUrl`
  - 数据库驱动
  - session 驱动
  - storage 驱动

### 4. 托管脚本位置

- `APP_BUILD_SCRIPT`
- `APP_START_SCRIPT`

现在统一托管在：

- `ROOT_DIR/scripts`

不再写在 `SITE_DIR` 内，原因：

- `SITE_DIR` 可能是用户要保留的模板源码目录
- preserve 模式下不应再修改该目录中的托管脚本

### 5. `emdashctl` 与安装器保持一致

- `emdashctl upgrade app` 现在与安装器共享相同的 `astro.config.mjs` 补丁策略
- 不允许 `emdashctl` 重新走回旧的整份覆盖逻辑
- 老实例若仍把 build/start 脚本路径放在 `SITE_DIR`：
  - `emdashctl` 会自动迁移到 `ROOT_DIR/scripts`
  - 迁移按项进行
  - 只迁真正 legacy 的那一项
  - 不会误改已经正确或自定义的另一项路径

### 6. 回滚边界

安装器激活失败时，现在回滚以下内容：

- `SITE_DIR`
- `SCRIPTS_DIR`
- `APP_ENV_FILE`
- `APP_SYSTEMD_UNIT`
- `INSTALL_YAML`
- 托管的 Caddy 配置文件
- 系统 Caddy 入口文件
- 备份计划文件

`emdashctl` 失败回滚现在覆盖：

- `SITE_DIR`
- `SCRIPTS_DIR`
- `APP_ENV_FILE`
- `APP_SYSTEMD_UNIT`

## 按时间顺序的开发过程

### 阶段 1：修复 passkey 的 public origin

最初的实际故障是：

- 浏览器访问公开域名
- 应用内部没有收到正确的 `siteUrl`
- WebAuthn 使用了错误的 RP ID / origin 组合
- 最终在 setup 阶段创建 passkey 时报错

根因判断：

- 旧逻辑只写 `APP_PUBLIC_URL`
- 但上游 EmDash 现在用 `siteUrl` / `EMDASH_SITE_URL` / `SITE_URL` 参与公开 origin 推导

修复动作：

- 安装器补写 `EMDASH_SITE_URL`
- 安装器补写 `SITE_URL`
- `astro.config.mjs` 中注入：
  - `siteUrl: process.env.EMDASH_SITE_URL || process.env.SITE_URL || undefined`

这一阶段对应的远端提交：

- `dfa8fd1` `Set EmDash public site URL for passkeys`

### 阶段 2：发现问题不是单点，而是“旧模板源码 + 新配置”的混合状态

随后出现新的现象：

- 站点能打开
- 静态资源并非 404
- 但页面结构和样式不对

排查结论：

- 安装器检测到已有 `site/package.json` 后跳过模板同步
- 但后续仍继续写入新的托管配置
- 于是形成了：
  - 旧模板源码
  - 新配置
  - 新运行时路径

这是结构性问题，不是单个模板 bug。

### 阶段 3：建立 preserve / sync 双模式

为了解决混装问题，引入了明确的站点目录模式：

- `sync`
  - 对新同步模板执行托管补丁
- `preserve`
  - 保留现有源码，不再覆盖模板内部文件

同时新增保护逻辑：

- 读取现有 `install.yml`
- 如缺失，再回退读取 `emdash.env`
- 检查以下元数据是否匹配：
  - 模板
  - 数据库驱动
  - session 驱动
  - storage 驱动

若元数据缺失或不匹配：

- 直接失败
- 提示使用 `EMDASH_INSTALL_FORCE_SYNC_TEMPLATE=1`

### 阶段 4：从“整份生成配置”切到“定向补丁配置”

后续 review 指出另一个更深的问题：

- 安装器和 `emdashctl` 以前都会整份生成 `astro.config.mjs`
- 这样会丢掉模板自带的插件、字体和其它配置

改造方向：

- 使用 Python 做 AST 级别之外的最小文本补丁
- 保留模板既有 import / integrations / fonts / plugins
- 只替换安装器托管的片段

这一步是后续保持模板行为稳定的关键。

### 阶段 5：把托管脚本移出 `SITE_DIR`

review 继续指出：

- 即使 preserve 模式不再动 `astro.config.mjs` / `package.json`
- 旧实现仍会改写 `SITE_DIR` 里的 build/start 脚本

于是把脚本迁移到：

- `ROOT_DIR/scripts`

这样 preserve 模式才真正不改用户站点源码。

### 阶段 6：修复 `emdashctl` 与安装器分叉

当安装器侧逻辑变安全后，又发现 `emdashctl` 还是旧逻辑：

- 仍可能整份重写 `astro.config.mjs`
- 仍可能绕过新的模板保护
- rollback 只覆盖 `SITE_DIR`

修复内容：

- `emdashctl upgrade app` 也改为定向补丁 `astro.config.mjs`
- `emdashctl` rollback 纳入 `SCRIPTS_DIR`
- 为 `emdashctl` 增加专用回归测试

### 阶段 7：补足失败回滚与旧脚本路径迁移

接着 review 指出两个迁移卫生问题：

1. 安装器激活失败时，`emdash.env` / systemd unit 已经被改写，但 rollback 没把它们带回去
2. 老实例若只用 `emdashctl`，不会自动迁到新的 `ROOT_DIR/scripts` 布局

修复内容：

- 安装器在激活前快照：
  - `SITE_DIR`
  - `SCRIPTS_DIR`
  - `APP_ENV_FILE`
  - `APP_SYSTEMD_UNIT`
- 失败时自动恢复，并尝试恢复旧服务
- `emdashctl` 为 legacy 脚本路径做自动迁移

### 阶段 8：补足回滚边界与逐项迁移

最后一轮 review 指出：

1. 激活失败回滚仍未覆盖：
   - `install.yml`
   - Caddy 文件
   - 备份计划
2. `emdashctl` 旧脚本迁移只要命中一项 legacy，就会把两项都改掉

最终修复：

- 安装器激活回滚继续扩展到：
  - `INSTALL_YAML`
  - 托管 Caddy 文件
  - 系统 Caddy 入口
  - 备份计划
- `emdashctl` 脚本迁移改为逐项迁移：
  - 只迁 legacy 的 build
  - 只迁 legacy 的 start
  - 不误改另一项

### 阶段 9：提交与推送

最终整理后的远端提交为：

- `4d59a83` `Harden installer rollback and script migration`

它建立在前一轮远端修复之上：

- `dfa8fd1` `Set EmDash public site URL for passkeys`

## 本轮新增 / 强化的回归测试

### 1. `scripts/test-passkey-origin-regression.sh`

覆盖：

- Caddy + HTTPS + 域名
- 直连 HTTP + IP:3000
- preserve 模式下依赖运行时 env 提供 origin
- build/start 脚本不再位于 `SITE_DIR`

### 2. `scripts/test-template-sync-regression.sh`

覆盖：

- 模板配置补丁保留模板自带行为
- preserve 模式不改动现有模板文件
- 模板/驱动不匹配时拒绝继续
- 缺失元数据时拒绝继续
- 激活失败时完整恢复运行时文件

### 3. `scripts/test-emdashctl-regression.sh`

覆盖：

- `emdashctl` 侧 `astro.config.mjs` 仍保留模板行为
- `emdashctl` rollback 恢复 `site/scripts/env/unit`
- 老脚本路径自动迁移到 `ROOT_DIR/scripts`
- 部分 legacy 场景下不误改另一条非 legacy 路径

## 关键经验

### 1. 安装器不应“看似保留源码，实际继续改其内部文件”

这会制造最难排查的混合状态。

### 2. 对模板类项目，配置生成优先做最小补丁，不要整份重写

只要整份重写，就会持续吞掉模板自身能力。

### 3. `install` 与 `upgrade` 不能各自维护一套近似逻辑

一旦分叉，旧 bug 会从另一条路径重新回来。

### 4. 回滚必须覆盖“已经生效的运行时状态”

不只包括源码目录，也包括：

- 环境文件
- systemd unit
- 反代配置
- 计划任务

## 后续维护建议

1. 未来若再增加新的托管运行时文件，先确认：
   - 由谁生成
   - preserve 模式是否应跳过
   - rollback 是否要纳入

2. 如果新增新的公开入口配置，必须同时检查：
   - `APP_PUBLIC_URL`
   - `EMDASH_SITE_URL`
   - `SITE_URL`
   - `astro.config.mjs` 中的 `siteUrl`

3. 如果继续扩展 `emdashctl`，应优先复用安装器已有 helper，而不是复制一套平行逻辑。

