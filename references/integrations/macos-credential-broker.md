# macOS Credential Broker

用于 `dedicated-real-test` + `standing-all-actions` profile。用户只在密码轮换时通过稳定
broker 二进制输入一次；测试 run、subagent 和工具只传 `profile_id`。

## 安装

```bash
scripts/install-macos-credential-broker.sh
```

默认安装到：

```text
~/.local/libexec/better-test/macos-credential-broker
```

安装器必须先通过 synthetic cross-process Keychain self-test。broker 创建并读取自己的
Keychain 条目，避免不同 ad-hoc 产品二进制之间的 ACL 不兼容。

## 密码轮换

```bash
~/.local/libexec/better-test/macos-credential-broker \
  rotate dedicated-real-primary
```

这是唯一人工步骤，只在账号或密码变化时执行。输入不会出现在 argv、shell history 或
测试 evidence。之后所有测试只使用 `profile_id`。

`rotate` 属于显式的账号维护流程，不属于测试执行。active run、subagent 和测试工具不得
调用它、生成 `.command` bootstrap 或要求用户输入账号密码。`status` 缺字段、登录被服务端
拒绝或远端 runner 没有 secret provider 时，结果必须是 `BLOCKED_CREDENTIAL_PROFILE`；
继续执行不依赖凭据的安全子集，不得回退到 prompt。

## Agent 接口

检查 profile：

```bash
broker status <profile_id>
```

为第一方 daemon 生成 run 独占登录文件：

```bash
lease_dir="$(mktemp -d)"
chmod 700 "$lease_dir"
broker materialize-login <profile_id> "$lease_dir"
```

输出文件固定为 `login-account` 和 `login-password`，权限 `0600`。daemon 仍通过第一方
`--login-account` / `--login-pwd-file` 启动；broker 不能替代产品登录证据。

交易解锁只走管道：

```bash
broker pipe-trade <profile_id> \
  | futucli unlock-trade --from-stdin ...
```

清理：

```bash
broker cleanup "$lease_dir"
```

`cleanup` 只处理该 lease 目录中的两个固定文件，不使用 glob。

## 边界

- broker 输出不得进入 evidence、日志或 subagent prompt。
- `materialize-login` 仅接受当前用户拥有且权限为 `0700` 的目录。
- 文件使用 `O_EXCL | O_NOFOLLOW` 创建，权限固定 `0600`。
- broker 二进制更新后必须重新运行 self-test；若 Keychain ACL 不再匹配，则执行一次密码轮换。
- 远端 runner 只能接收 run 独占临时 secret，执行后按精确路径删除；不得提交到 Git。
