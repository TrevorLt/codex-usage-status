# 开源用量与状态产品的刷新机制对照

复核日期：2026-10-15（America/Chicago）
方法：直接读取 GitHub 官方 API 与 `raw.githubusercontent.com` 的固定提交源码；下列链接均固定到 commit SHA。未使用第三方镜像。commit 时间按 UTC 记录。

## 固定版本

| 项目 | 固定版本与核验源码 |
|---|---|
| CodexBar | [`d846ceb`，2026-10-16 01:49:22 UTC（芝加哥 10-15）](https://github.com/steipete/CodexBar/commit/d846ceb47f3151df6caa88cd9aa61b17cb7185aa)：[刷新决策记录](https://github.com/steipete/CodexBar/blob/d846ceb47f3151df6caa88cd9aa61b17cb7185aa/docs/predictive-refresh-policy.md)、[纯策略核心](https://github.com/steipete/CodexBar/blob/d846ceb47f3151df6caa88cd9aa61b17cb7185aa/Sources/AdaptiveRefreshCore/AdaptiveRefreshPolicyCore.swift)、[AgentSessionsStore](https://github.com/steipete/CodexBar/blob/d846ceb47f3151df6caa88cd9aa61b17cb7185aa/Sources/CodexBar/AgentSessionsStore.swift)、[扫描限制](https://github.com/steipete/CodexBar/blob/d846ceb47f3151df6caa88cd9aa61b17cb7185aa/Sources/CodexBarCore/AgentSession.swift)。 |
| codex-usage-status 上游 | [`d8438da`，2026-05-26 15:52:41 UTC](https://github.com/tollenceld/codex-usage-status/commit/d8438da30833eadb660cb35d632d6da665a6ba23)：[Configuration](https://github.com/tollenceld/codex-usage-status/blob/d8438da30833eadb660cb35d632d6da665a6ba23/macos/CodexUsageStatus/Sources/CodexUsageStatus/App/Configuration.swift)、[AppDelegate](https://github.com/tollenceld/codex-usage-status/blob/d8438da30833eadb660cb35d632d6da665a6ba23/macos/CodexUsageStatus/Sources/CodexUsageStatus/App/AppDelegate.swift)、[CodexUsageFetcher](https://github.com/tollenceld/codex-usage-status/blob/d8438da30833eadb660cb35d632d6da665a6ba23/macos/CodexUsageStatus/Sources/CodexUsageStatus/Codex/CodexUsageFetcher.swift)。 |
| codex-usage-status 本地 30 秒分支 | [`a06d3aa`，2026-10-15 21:38:13 UTC（芝加哥 16:38）](https://github.com/TrevorLt/codex-usage-status/commit/a06d3aa2421040f7a41bb8e024d27b5f54c7abe4)：[Configuration](https://github.com/TrevorLt/codex-usage-status/blob/a06d3aa2421040f7a41bb8e024d27b5f54c7abe4/macos/CodexUsageStatus/Sources/CodexUsageStatus/App/Configuration.swift)、[RefreshPolicy](https://github.com/TrevorLt/codex-usage-status/blob/a06d3aa2421040f7a41bb8e024d27b5f54c7abe4/macos/CodexUsageStatus/Sources/CodexUsageStatus/App/RefreshPolicy.swift)、[AppDelegate](https://github.com/TrevorLt/codex-usage-status/blob/a06d3aa2421040f7a41bb8e024d27b5f54c7abe4/macos/CodexUsageStatus/Sources/CodexUsageStatus/App/AppDelegate.swift)。 |
| Claude usage（Bread-bang） | [`25b30dd`，2026-10-13 10:46:40 UTC](https://github.com/Bread-bang/claude-usage/commit/25b30ddf8e27bf4b3be9c6368e0879e6ea68bfa5)：[UsageViewModel](https://github.com/Bread-bang/claude-usage/blob/25b30ddf8e27bf4b3be9c6368e0879e6ea68bfa5/Sources/ClaudeUsageMiniBar/ViewModel/UsageViewModel.swift)、[UsageClient](https://github.com/Bread-bang/claude-usage/blob/25b30ddf8e27bf4b3be9c6368e0879e6ea68bfa5/Sources/ClaudeUsageMiniBar/Networking/UsageClient.swift)、[刷新选项](https://github.com/Bread-bang/claude-usage/blob/25b30ddf8e27bf4b3be9c6368e0879e6ea68bfa5/Sources/ClaudeUsageMiniBar/Views/UsageDropdownView.swift)。 |
| Stats | [`4ecf4f7`，2026-10-15 14:39:46 UTC](https://github.com/exelban/Stats/commit/4ecf4f736056eb488c75aa2fa62e749abd87c4a4)：[Reader](https://github.com/exelban/Stats/blob/4ecf4f736056eb488c75aa2fa62e749abd87c4a4/Kit/module/reader.swift)、[Repeater](https://github.com/exelban/Stats/blob/4ecf4f736056eb488c75aa2fa62e749abd87c4a4/Kit/plugins/Repeater.swift)、[CPU 读取器](https://github.com/exelban/Stats/blob/4ecf4f736056eb488c75aa2fa62e749abd87c4a4/Modules/CPU/readers.swift)。 |

## 刷新机制比较

| 项目 | 数据源 | 默认刷新 / 最小间隔 | 自适应 | 进程复用 | single-flight | 429 backoff | 睡眠 / 唤醒 |
|---|---|---|---|---|---|---|---|
| CodexBar | 已启用 provider 的批量刷新；本地扫描只提供活动信号，不读 quota。 | 新安装默认 `Adaptive`，provider batch 在 2–30 分钟间；旧安装无设置时沿用 5 分钟。Agent-aware 本地扫描另为 30 秒。 | 看菜单最近打开时间、可选的本地编码活动，以及低电量/热状态；不是按 quota 增减预测。约束状态为 30 分钟。 | scheduler 本身不规定 provider 是否复用子进程；Unknown。 | provider instance 级合并在途刷新；不是一个跨所有 provider 的全局请求锁。 | 没有统一 429 cadence；失败不触发 policy 层立即重试，provider 各自处理。 | 被检查的策略使用低电量/热状态，没有显式 OS sleep/wake 刷新钩子。 |
| codex-usage-status 上游 | 本机 Codex app-server 的 `account/rateLimits/read`。 | 固定默认 120 秒、下限 60 秒；失败 300 秒后重试。 | 无；成功后固定周期，失败走通用重试。 | 每次刷新启动 `codex app-server --listen stdio://`，读完即终止。 | `AppDelegate.isRefreshing` 阻止并发刷新。 | 不是 HTTP 请求；没有 429 专属处理，app-server 错误走通用 300 秒重试。 | 检查的调度路径没有显式 sleep/wake hook。 |
| codex-usage-status 本地 30 秒分支 | 同上。 | 默认 120 秒、下限 30 秒、常规上限 300 秒；环境变量可把 base 设得更高。 | 两个窗口的显示剩余值任一下降至少 5 个百分点就切到 30 秒；距显著下降满 60 秒后逐次加倍，封顶按配置 base 与 300 秒取较大值。 | 每次刷新仍新启、终止 app-server 子进程。 | 同一 `isRefreshing` 门闩。 | 没有 HTTP 429 专属分支；所有失败统一 300 秒。 | 检查的调度路径没有显式 sleep/wake hook。 |
| Claude usage | `GET https://api.anthropic.com/api/oauth/usage`，token 由本机 Keychain provider 提供。 | 默认 60 秒；设置选项 30 秒、1 分钟、5 分钟。存储值至少 30 秒才采用；小于 30 秒或未设置时回退 60 秒，非钳制到 30 秒。 | 常态按用户固定周期；无缓存时失败后 15 秒再试；已有报告遇 429 则周期乘 2。 | 不启动每次刷新子进程；`URLSession.shared` 在应用进程内请求。 | 轮询 loop 自身串行，但 `refreshNow()` 另起 Task，`load()` 没有 single-flight guard；手动刷新与轮询可重叠。 | 429 后等待 `2 × refreshInterval`；源码未见读取 `Retry-After`。无缓存启动失败会优先走 15 秒分支。 | 检查的 ViewModel 用 `Task.sleep`，未见显式 OS sleep/wake 处理。 |
| Stats | 各模块 Reader 读取本机系统指标；CPU 示例调用 `host_processor_info` / `sysctl`，不是账户 quota API。 | Reader 默认 1 秒；可按 reader 保存整数秒间隔。通用 Reader 未设置下限钳制，实际最小值取决于各设置界面，Unknown。 | 基础机制是每个 Reader 的固定 cadence；部分 reader 随 popup/preview 可见性暂停。 | Reader 在 Stats 应用进程内运行，没有每次采样启动 CLI。 | 通用 Reader 没有统一 single-flight；具体 reader 各异，CPU LoadReader 有自己的 `NSLock`。 | 对本机采样不适用。 | 未在所查路径确认系统 sleep/wake hook。Reader 的 `sleepMode` 是按 UI 可见性暂停特定 Reader，不等于设备睡眠通知。 |

## CodexBar 的关键细节

`docs/predictive-refresh-policy.md` 与 `AdaptiveRefreshPolicyCore.swift` 相互印证：自适应的 **2 / 5 / 15 / 30 分钟**是 provider batch cadence；若启用了单独的 agent-aware 模式，最近 5 分钟的本地活动可把较慢周期压到 5 分钟。严重/临界热状态或 Low Power Mode 把周期放到 30 分钟。菜单活跃时间与本地活动时间只影响何时刷新，不代表观测到了 quota 变化。

`AgentSessionsStore` 的 local task 每 30 秒发起一次扫描；这是本机活动信号，不是 quota 请求。`SessionScanConfig` 源码把扫描限制设为：最多 64 个进程、128 条 Codex rollout 元数据、每项目 64 个 Claude transcript 候选、共享目录最多 512 项/深度 1；agent-aware 目录预算为 150 ms。UI 关闭时，策略投影只保留最新活动时间，不把会话身份和路径发布给刷新策略。agent-aware 需要显式选择与 consent，且扫描受低电量/热状态约束。

## 对本项目可迁移的机制与边界

- **把本地活动探针与远端 quota 读取分成两条 cadence。** CodexBar 的 30 秒扫描可以提示“用户可能在工作”，但它本身不能证明额度已经变化。若用类似信号加速，应在描述和 UI 上明确它只是启发式。
- **把 timer、菜单手动刷新等入口收敛到单一请求协调器。** 上游 CodexUsageStatus 与 CodexBar 都有在途刷新合并/门闩；Claude 的独立 `refreshNow()` 暴露了需要避免轮询和手动刷新重叠的边界。
- **区分额度变化策略与请求失败策略。** 本地分支按显示值下降提速、对所有失败统一 300 秒；Claude 对 429 单独乘 2。由于本项目走 app-server stdio，不能直接假定获得 HTTP 429 或其 `Retry-After`。
- **Stats 的可迁移点只有定时器与暂停边界。** 它的 200 ms timer leeway、按需暂停 Reader 可减少无用本机采样；1 秒硬件采样频率不适用于远端 quota endpoint。

`account/rateLimits/read` 是否跨其他 Codex 会话或设备立即反映变化、`account/rateLimits/updated` 的通知语义及覆盖范围：**Unknown**。本次源码未证明这些更新可跨会话/设备推送，因此不把 push 当作可用保证；在获得协议级证据前，任何轮询周期仍有盲区。
