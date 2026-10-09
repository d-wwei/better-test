# Tool Operation Platform Adaptations

所有平台沿用 `references/procedures/product-operation.md`，不重复其状态机。
下面八类均为 **ADAPTED_METHOD / NOT_RUN**：本地 fixture 自测并非平台或 Agent 验证。
工具按项目现有能力选择；未知命令、权限或 runner 标 draft/blocked，不给看似合理的启动指令。

| 平台 | 优先工具 | 目标绑定 | 观察方式 | 隔离 | 恢复 | 不可外推 |
|---|---|---|---|---|---|---|
| 网页 | 项目既有浏览器 E2E；否则已安装浏览器控制面 | origin/app marker/profile/tab 与服务 identity | role/label/DOM/截图、真实请求、重开和独立持久 observer | 独立 context/profile+port/data；共享浏览器单 driver | 归档现场后重建本 run context；修当前 selector | API 不能证明 UI；按钮不证明快捷键；一个浏览器/OS 不证明另一个 |
| Electron | 项目 E2E、可用桌面与 renderer 控制面 | build/main PID/window/profile/CDP endpoint | renderer 和原生菜单各自真实操作，主进程/持久后效 | 独立 user-data 及 endpoint；未隔离窗口单 driver | 本 run window/profile reset、owned relaunch | DOM 成功不能证明原生菜单、快捷键、系统弹窗 |
| 原生桌面 | 既有 UI harness 或已授权可访问性控制 | app bundle/build/PID/window/document | AX tree/截图、文件/业务后效及 reopen | 独立 document/profile；共享前台单 driver | 保留错误窗口后 reset/relaunch owned app | 脚本/API 不证明 GUI；系统权限缺口要 blocked |
| 移动端 | 项目现有 simulator/device harness | app build/device ID/boot/session | 真实 touch/navigation、UI 状态和受控后效 | 独立 simulator/device/app data；共享设备单 driver | 本 session app reset、owned simulator recovery | emulator 不证明真机/另一OS；缺 runner 不承诺可执行 |
| CLI/TUI | 原生 CLI；需要交互时既有 PTY | binary digest/argv/PID/cwd/env/PTY ID | argv/stdin/TTY、prompt、stdout/stderr/exit 和持久状态 | 独立 cwd/temp/端口；同 PTY 单 driver | prompt doctor、重建本 run PTY/进程 | pipe 不证明 TTY；exit0 不证明业务；普通CLI不必加tmux |
| API | 项目 harness；已可用 HTTP 客户端 | endpoint/build/process、tenant/profile、key/digest | request/response/correlation、独立 DB/outbox observer | 独立port/schema/queue namespace/专用合成主体 | read/reconcile 后按幂等契约重放；unknown 停止写 | HTTP成功不证明唯一后效；实际拒绝码不补充未知合同 |
| 后台服务 | 现有 service/job/event harness | build/PID/namespace/correlation/job identity | 事件、真正终态、外部边界 stub 与持久后效 | 独立queue/schema/process；副作用限专用边界 | 查 checkpoint/receipt，再恢复 owned consumer | health不证明 job done；stub不证明真实外部集成 |
| Agent 服务 | 已有 Agent/task 工具入口和审计接口 | runtime/build/session/task ID、权限、原 run identity | 意图→实际工具参数→权限→业务后效与终态 | 独立session/synthetic tools/data；共享工具单 driver | 先查 side effects/任务终态，再有条件恢复 | 回复措辞不证明动作成功；不改变 Agent evals 核心/评分 |

共享 GUI/profile/device 的排他 driver 属于实际资源协调，不因各自处在不同 worktree 而自动解决。
团队角色和协调接入由对应 owner 维护；本文件不另建租约服务。
