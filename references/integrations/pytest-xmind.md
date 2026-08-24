# Pytest -> XMind Optional Adapter

XMind 是测试资产展示格式，不是 Better Test 核心 gate。吸纳外部 pytest 仓时，可把已验证
case map 投影为：

```text
API/module
  -> class
    -> test function
      -> parameter variant
        -> steps
        -> expected result
```

## Contract

1. 输入必须是已通过 `validate-reference-suite-map.py` 的 map。
2. XMind case 数应与选定 map universe 一致。
3. dynamic parametrize 无法静态展开时标 `static-function`，不得伪造 collected node 数。
4. XMind 不保存凭证、账户 ID 或响应原文。
5. XMind 漂移不阻断 runtime gate；case map 漂移必须阻断。

项目可复用 upstream 的 `export-pytest-xmind` 思路，但 exporter 作为 integration 安装，不进入
`protocol-base`、results schema 或 release readiness。
