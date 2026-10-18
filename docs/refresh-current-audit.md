# Current 刷新策略与运行生命周期审计

审计时间：2026-10-15（CDT）
源码基线：`a06d3aa2421040f7a41bb8e024d27b5f54c7abe4`（分支 `local-30s-refresh`）
性质：只读源码审计 + `/private/tmp` 最小 Swift harness；未改源码、测试、安装包、LaunchAgent 或正在运行的进程。
状态：历史审计；其中 app-server 提前退出与 Codex 路径发现问题在后续 v0.1.2 修复工作中重新验证，不能把本文的 pre-fix 结论当作当前行为。

## 1. 结论先行

当前实现的名义参数确实是：默认 120 秒、快速/最短 30 秒、回退目标 300 秒、单次任一窗口下降至少 5 个“整数百分点”进入快速档。但代码并不实现“累计消耗触发”或“300 秒硬上限”：

1. **确定缺陷：连续 1–4 点的相邻下降永远不会触发快速档。** 策略只比较前后两个已经取整的快照，不累计未达阈值的下降。`100→99→98→97` 每次都返回 120 秒。
2. **确定缺陷：一次突发后的持续小幅下降不会延长快速期。** 固定时钟、零 fetch 耗时的 harness 中，`100→94` 触发 30 秒；随后每轮下降 1 点，返回 `30, 30, 120, 240, 300`。策略只从最后一次显著下降计 60 秒，不刷新小幅下降活动时间。真实 App 在 fetch 完成时取 `Date()`，之后再启动单次 timer；因此 60 秒是策略边界，不是精确的墙钟触发时刻，实际在第几轮回退会受 fetch 和调度延迟影响。
3. **契约待明确：300 秒不是环境覆盖下的硬上限。** `CODEX_USAGE_REFRESH_SECONDS=600` 会令 base 与 effective maximum 都成为 600；配置函数只做下限钳制。源码明确允许更高的用户配置。只有当产品契约要求任何情况下不超过 300 秒时，这才构成契约不一致；否则可视为支持用户设置更高刷新间隔。
4. **确定缺陷：app-server 提前退出不会被立即识别。** 终止回调只唤醒 cleanup 用的 semaphore，等待响应的另一个 semaphore 仍会等满 20 秒；`FetchError.appServerExited` 在 current 源码中没有抛出路径。
5. **确定的数据有效性缺口：** `usedPercent=nil` 被当作使用量 0（即剩余 100%）；仅有 weekly 窗口时，同一窗口可以同时被选为 5h 和 weekly，形成看似成功但语义错误的数据。
6. **资源策略是强历史依赖，而非一般意义上的 idle 自适应：** 首次显著下降前，无论 idle 多久都固定在 base（默认 120）；一旦发生过显著下降并回退到 300，又会长期停在 300，reset 不会清除该历史。
7. **当前 AppDelegate 能阻止同一应用实例内的并发 refresh/app-server 重叠，** 但 inflight 期间的 manual/timer 请求会直接丢弃，不排队；每个真正执行的 refresh 都新建并终止一个 app-server 进程。
8. **sleep/wake 没有显式策略。** 代码只使用主 run loop default mode 的单次 `Timer`，没有监听 `NSWorkspace.didWakeNotification`。休眠跨过 deadline 后何时刷新、App Nap/定时器合并造成多少偏差，必须实机测，不能由静态审计声称已验证。

## 2. 审计范围与证据等级

### 2.1 审阅文件

- `macos/CodexUsageStatus/Sources/CodexUsageStatus/App/RefreshPolicy.swift`
- `macos/CodexUsageStatus/Sources/CodexUsageStatus/App/Configuration.swift`
- `macos/CodexUsageStatus/Sources/CodexUsageStatus/App/AppDelegate.swift`
- `macos/CodexUsageStatus/Sources/CodexUsageStatus/Codex/CodexUsageFetcher.swift`
- `macos/CodexUsageStatus/Sources/CodexUsageStatus/Domain/UsageModels.swift`
- `macos/CodexUsageStatus/Tests/CodexUsageStatusTests/*.swift`
- `test/usage-format.test.js` 与测试入口配置（只用于判断 coverage，不把 JS 行为代替 Swift 行为）

### 2.2 证据标记

- **源码确定**：由 current 行号可直接推出。
- **harness 确认**：直接编译仓库未修改的 `Configuration.swift` 与 `RefreshPolicy.swift`，以固定时钟输入运行。
- **安装环境确认**：只读 plist/Info.plist/code signature/launchctl 的非敏感字段；未读取 `auth.json` 或任何凭证、用量正文。
- **主 agent 快照**：由主 agent 提供的单点 `ps` 观察，仅作旁证，不等同于持续测量。
- **待实机**：run loop、sleep/wake、CPU/RSS/wakeups、能耗/电池消耗、真实 CLI 启动分布等动态行为。

## 3. 参数契约核查

| 项目 | current 源码 | 实际语义 | 结论 |
|---|---:|---|---|
| 默认 base | 120 s | 未设置或无法解析环境值时为 120 | 已确认 |
| 最短/fast | 30 s | 环境值低于 30 被抬到 30；显著下降后用 30 | 已确认 |
| maximum | 300 s | 仅当 `base <= 300` 时是回退 cap；`base > 300` 时 maximum 随 base 增大 | **不是硬上限** |
| 显著下降 | 5 点 | 两个窗口中任一个“相邻整数剩余百分比”下降至少 5 | 已确认，不累计、不求和 |
| 稳定窗口 | 60 s | 从最后一次相邻 `>=5` 下降计时；严格 `<60` 才留在 fast | 60 秒整立即回退 |
| 失败重试 | 300 s | 任一 fetch 错误后直接设为 300 | 已确认 |
| app-server timeout | 20 s | 响应 semaphore 最多等待 20 秒；cleanup 还可能再等最多约 2 秒 | 已确认 |

精确依据：

- 常量定义：`Configuration.swift:4-11`。
- 环境变量只执行下限钳制：`Configuration.swift:14-18`。
- `maximumInterval = max(300, baseInterval)` 且初始 `currentInterval = baseInterval`：`RefreshPolicy.swift:26-30`。因此 base=600 时，从初始化开始就是 600，不可能由“maximum=300”压回 300。
- 显著下降取两个窗口下降值的 `max`，不是累计也不是两窗口之和：`RefreshPolicy.swift:37-40,62-67`。
- 稳定判定为严格小于 60：`RefreshPolicy.swift:43-54`。
- 失败直接切 300：`RefreshPolicy.swift:57-60`。

配置还有两个未覆盖边界：环境值没有上限，也没有显式 `isFinite` 校验；非数字字符串会回到 120，但 NaN/Infinity 的下游 Timer 行为本次未执行，归入待查而不是已确认故障。

## 4. 精确事件序列

### 4.1 启动与第一次成功

1. `applicationDidFinishLaunching` 建立 status item/menu，先渲染 placeholder，然后立即调用 `refresh()`：`AppDelegate.swift:33-69`。
2. `refresh()` 检查 `isRefreshing`；通过后设为 true、禁用菜单项，并创建 `Task`：`AppDelegate.swift:134-148`。
3. `CodexUsageFetcher.fetch()` 把同步 fetch 放进 utility 优先级的 detached task：`CodexUsageFetcher.swift:5-9`。
4. 每次 fetch 都创建新的 `Process`，执行 `codex app-server --listen stdio://`：`CodexUsageFetcher.swift:16-32`。
5. 每个新进程一次性写入 `initialize`、`initialized`、`account/rateLimits/read(id=2)` 三行；没有等待 initialize response 再发下一步：`CodexUsageFetcher.swift:51-58`。
6. 收到 id=2 的响应并解码后，关闭 stdin、终止子进程、读取 stderr，构造 `UsageSummary`：`CodexUsageFetcher.swift:59-78`、`CodexUsageFetcher.swift:11-14`。
7. 首次成功时 `previous=nil`；`applyUsage` 先保存数据/时间并清除错误，然后 policy 返回 base=120，最后才安排单次 timer：`AppDelegate.swift:148-160,176-181`；`RefreshPolicy.swift:43-45`。

所以“120 秒刷新”不是进程启动到下一次进程启动严格相隔 120 秒，而是：

`本次成功/失败处理完成 → 等待目标 interval → run loop 实际触发 → 下一次 fetch 开始`

正常自动轮询下，start-to-start 约为 `本轮 fetch+cleanup 时长 + interval + run-loop 延迟`。若 fetch 20 秒超时，下一次尝试是在错误已返回后再等 300 秒，不是从上一次 start 起算 300 秒。

### 4.2 连续微小下降：确定漏触发

策略每次都用 `lastUsage` 作为 previous，再立即用本轮 usage 覆盖它：`AppDelegate.swift:149-158,176-179`。因此未达 5 点的差值不会保留到下一轮。

直接 Swift harness 输出：

```text
A-small-adjacent-drops step=0 t=+0s remaining=100 adjacentDrop=n/a next=120s
A-small-adjacent-drops step=1 t=+120s remaining=99 adjacentDrop=1 next=120s
A-small-adjacent-drops step=2 t=+240s remaining=98 adjacentDrop=1 next=120s
A-small-adjacent-drops step=3 t=+360s remaining=97 adjacentDrop=1 next=120s
```

即使延长为 `100→96→92→88...`，只要每一对相邻整数快照下降不超过 4，`lastSignificantDropAt` 始终为 nil，策略就始终走 base 分支。两窗口各下降 3 点也不会触发，因为代码取 `max(3,3)=3`，不会相加成 6。

### 4.3 突发后继续小降：名义两轮 30 秒后开始回退

直接 Swift harness 输出：

```text
B-burst-then-small-drops step=0 t=+0s remaining=100 adjacentDrop=n/a next=120s
B-burst-then-small-drops step=1 t=+120s remaining=94 adjacentDrop=6 next=30s
B-burst-then-small-drops step=2 t=+150s remaining=93 adjacentDrop=1 next=30s
B-burst-then-small-drops step=3 t=+180s remaining=92 adjacentDrop=1 next=120s
B-burst-then-small-drops step=4 t=+300s remaining=91 adjacentDrop=1 next=240s
B-burst-then-small-drops step=5 t=+540s remaining=90 adjacentDrop=1 next=300s
HARNESS PASS
```

详细时序：

- `t=120`：`100→94`，下降 6，记录 `lastSignificantDropAt=120`，next=30。
- `t=150`：继续下降 1；距显著下降 30 秒，`30 < 60`，next=30。
- `t=180`：继续下降 1；距显著下降恰好 60 秒，`60 < 60` 为 false；`max(base 120, 30×2)` 得 120。
- `t=300`：再降 1；`120×2=240`。
- `t=540`：再降 1；钳到 300。

这些 `t` 是最小 harness 的合成时钟：每轮只累加策略返回的 interval，没有模拟 fetch 耗时或 run-loop 延迟。真实 App 在 fetch 成功完成时用 `Date()` 计算策略，再从完成时刻启动单次 timer；下一次策略判断还会包含该轮 fetch 和调度耗时。因此 harness 中的第三次成功恰在显著下降后名义 60 秒，真实墙钟时刻通常更晚；若前一轮 fetch 或调度延迟较大，也可能在第一轮小幅下降时就已超过 `<60` 边界，使 120 秒回退更早出现。策略观察的是 fetch 完成时的时间。当连续轮次都成功且没有新的显著下降时，回退值依次为 120、240、300 秒；启动到启动的间隔还会再加上 fetch 与调度耗时（见 4.1）。

现有测试还把这个边界固化为期望：显著下降后在 `start+60` 直接断言 120，随后断言 240/300：`RefreshPolicyTests.swift:43-59`。

### 4.4 reset、取整与“稳定”

`UsageWindow` 先把 `usedPercent` 钳到 0...100，再计算 `Int((100-used).rounded())`：`UsageModels.swift:63-72`。policy 比较的是这个整数，不是原始 Double。

这会使 5 点阈值出现最多约 1 点的量化相位误差。例如：

- used `10.49→14.51`，真实增加 4.02；remaining `90→85`，整数下降 5，**会触发**。
- used `10.51→15.49`，真实增加 4.98；remaining `89→85`，整数下降 4，**不会触发**。

reset 使 remaining 上升，当前 policy 只把它看成负下降；没有 reset 分支，也不使用 `resetsAt`：`RefreshPolicy.swift:62-67`；`UsageModels.swift:68-72`。结果取决于历史状态：

- 从未显著下降：reset 后仍是 base=120。
- 显著下降后尚在 60 秒内：reset 本身不会清除 fast 历史，可能继续 30，直到原时间窗结束。
- 已回退到 300：reset 后仍保持 300。

因此“stable”实际含义仅是“过去 60 秒没有任何一次**相邻整数**下降达到 5”，并不表示用量不再下降，也不表示刚完成 reset。

### 4.5 失败、manual、timer 与 inflight

失败时序：

1. fetch 抛错后恢复菜单状态。
2. `applyError` 只写 `lastError` 并重绘；保留 `lastUsage` 和最后成功时间，但 error image/tooltip 会覆盖 last-good 展示：`AppDelegate.swift:161-167,183-185,194-203`。
3. `intervalAfterFailure()` 无条件把 current interval 设为 300，然后安排单次 timer：`RefreshPolicy.swift:57-60`；`AppDelegate.swift:166-174`。
4. 下一次成功仍用失败前保存的 `lastUsage` 作 previous；如果失败期间累计下降达到 5，会切回 30，否则按保留的 policy 历史继续。

manual/inflight 时序：

- manual 和 timer 最终都调用同一个 `refresh()`：`AppDelegate.swift:71-77`。
- `isRefreshing` 在 MainActor 上阻止同一实例重叠：`AppDelegate.swift:4-5,134-140`。
- inflight 时 manual/timer 进入 guard 后直接 return，没有 pending 标记：`AppDelegate.swift:134-137`。
- 开始 manual refresh 时旧 timer 不会立刻 invalidate；若旧 timer 在 manual inflight 期间触发，它会被 guard 丢弃。本轮完成后 `scheduleNextRefresh` 才 invalidate 旧 timer 并从完成时重新计时：`AppDelegate.swift:155-173`。
- timer 明确为 `repeats:false`：`AppDelegate.swift:171-174`。Apple 文档说明 `scheduledTimer` 加入当前 run loop 的 default mode，非重复 timer 发火后失效：[Timer 文档](https://developer.apple.com/documentation/foundation/timer)、[scheduledTimer 文档](https://developer.apple.com/documentation/foundation/timer/scheduledtimer%28timeinterval%3Atarget%3Aselector%3Auserinfo%3Arepeats%3A%29)。因此菜单跟踪、App Nap、系统调度等造成的实际偏差不能由 `currentInterval` 本身代表。

### 4.6 sleep/wake

在审阅的 AppDelegate 中没有 `NSWorkspace.willSleepNotification` / `didWakeNotification` 观察者，也没有 wake 后主动 refresh 或重新锚定 timer 的分支；唯一调度点是 `Timer.scheduledTimer(... repeats:false)`：`AppDelegate.swift:171-174`。

Apple 提供明确的设备 wake 通知，但 current 未使用：[NSWorkspace.didWakeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification)。静态代码只能确认“无显式 wake 策略”；下列动态结果必须实机验证：

- deadline 落在睡眠期间时，wake-to-refresh 的实际延迟；
- 睡眠前 timer 尚未到期时，剩余时长如何体现；
- fetch/app-server inflight 时入睡的 timeout 与子进程清理；
- wake 后是否出现 timer/manual 同时到达，以及 guard 是否只丢一次事件。

## 5. Fetcher 生命周期与错误反馈

### 5.1 每轮初始化与 cleanup

每次 `fetch()` 都新建一个 app-server `Process`；没有连接复用：`CodexUsageFetcher.swift:5-9,16-32`。单轮协议为：

`spawn → 同批写 initialize/initialized/read → 等 id=2 → close stdin → SIGTERM → 最多等 1s → 必要时 SIGKILL → 最多再等 1s`

对应 cleanup：`CodexUsageFetcher.swift:59-69,81-90`。

正面点：

- stdout buffer 有锁，`storedResult` 只写一次：`CodexUsageFetcher.swift:93-138`。
- 正常响应、timeout、`process.run()` 失败都有至少部分 handler/pipe/process cleanup。
- AppDelegate 的 `isRefreshing` 使同一实例理论上最多一个这类子进程处于 active fetch。

缺口：

- SIGKILL 后第二次 1 秒 wait 的结果被忽略，没有最终确认 `process.isRunning == false`：`CodexUsageFetcher.swift:85-89`。是否可能残留只能用故意拒绝退出的 fake child 验证。
- timeout 分支没有读取 stderr；正常分支虽读取 stderr，也不将其用于诊断：`CodexUsageFetcher.swift:59-69`。
- 三条初始化消息被流水式写入，没有确认 initialize response；这依赖 current app-server 容忍该顺序，协议兼容性需要 fake/real server contract test。
- Task 本身没有被保存或取消；应用退出由进程终止兜底，sleep 也没有专门取消路径。

### 5.2 提前退出误判为 timeout

`process.terminationHandler` 只 signal `finished`：`CodexUsageFetcher.swift:34-37`。但主等待是 `responseBox.wait(...)`，使用 ResponseBox 自己的 semaphore：`CodexUsageFetcher.swift:39-42,59-64,93-97,130-132`。两者没有 race/合并等待。

因此 app-server 在没有 id=2 响应时即刻退出，主线程仍会等待满 20 秒，然后抛 `.timeout`。虽然 enum 定义了 `.appServerExited(Int)` 及文案，current 源码没有任何 `throw FetchError.appServerExited(...)`：`CodexUsageFetcher.swift:169-190`。

用户可见后果：

- 真实的“立即退出”被延迟约 20 秒才显示错误；
- 文案是 “did not respond within 20 seconds”，不是 exit status；
- 随后再等 300 秒才重试；
- 排查权限、CLI 参数或崩溃问题时，错误反馈丢失关键分类。

### 5.3 ResponseBox 与模型错误分类

- 只接受 id 为数字或字符串 `2` 的 JSON line：`CodexUsageFetcher.swift:140-165`。
- 任何 id=2 的 error 都压缩为通用 `.appServerError`，不保留结构化错误内容：`CodexUsageFetcher.swift:146-155`。
- 非法 JSON 会立刻存为 failure；合法但无关的 JSON line 被忽略，直到 timeout：`CodexUsageFetcher.swift:111-127,140-159`。
- UI 对所有 error 只显示 `localizedDescription`，没有 last-good 值/年龄：`AppDelegate.swift:91-110,194-203`。

“失败后 300 秒重试”降低故障时进程风暴风险，但也把一次瞬时故障的恢复延迟放大到最多约 5 分钟；这是明确取舍，是否正确需产品目标决定。

## 6. UsageModels 数据有效性

### 6.1 snapshot 选择

优先级为 `rateLimitsByLimitId["codex"] → rateLimits → rateLimitsByLimitId.values.first`：`UsageModels.swift:26-33`。最后一个 fallback 在存在多个非 codex limit 时没有语义保证；dictionary 的“第一个”不应被当成正确 limit 的契约。

### 6.2 窗口可能重复或错标

窗口选择分别计算：

- fiveHour：找约 300 分钟，否则拿第一个；
- weekly：找约 10080 分钟，否则拿第二个。

见 `UsageModels.swift:35-45,83-88`。

两个选择没有保证引用不同窗口。若 payload 只有一个 weekly 窗口：

- fiveHour 找不到 300，fallback 到唯一窗口；
- weekly 找到同一个 10080 窗口；
- guard 成功，最终 5h/7d 显示同一值，而不是报 invalid data。

若 duration 缺失，则依赖 primary/secondary 顺序；顺序反转会错标。此类错误还会污染刷新策略，因为 policy 只看到已经错标/重复的整数 snapshot。

### 6.3 缺失 usedPercent 被当成满额度

`window.usedPercent ?? 0` 把字段缺失解释为 0% used：`UsageModels.swift:68-72`。这不是 Unknown，而是可见的 100% remaining。可能后果：

- 暂时缺字段被误显示为 reset/满额度；
- 本轮被当作成功并清除 lastError；
- 下轮真实值恢复时制造一次大下降，误触发 fast。

更安全的契约应由产品决定：字段缺失时报 invalidOutput，或显式保留 Unknown；current 两者都没有。

## 7. 现有测试覆盖与验证结果

### 7.1 Swift tests 覆盖了什么

`RefreshPolicyTests.swift:6-65` 覆盖：

- 首次成功使用默认值；
- 单次 5 点触发 fast；
- 单次 3 点保持 normal；
- 60 秒整回到 120，再到 240/300；
- 失败返回 300。

未覆盖：

- 连续 1–4 点累计下降；
- 两窗口各自小降；
- 取整阈值；
- reset/窗口切换；
- base 小于 30、大于 300、非有限值；
- 失败后恢复及 policy 历史；
- manual/timer/inflight；
- app-server 提前退出、timeout、SIGKILL、stderr、重复/迟到响应；
- UsageModels 的单窗口、缺字段、错序、多 limit fallback；
- sleep/wake 与实际 timer 偏差。

Appearance tests 只覆盖外观通知/颜色；它们不覆盖刷新生命周期：`AppearanceObserverTests.swift:5-38`、`AppearanceColorTests.swift:5-43`。

### 7.2 Node tests 不能代表 Swift refresh

`package.json:10-18` 的 `npm test` 只执行 `node --test`。当前 3 个 Node tests 覆盖 JS 格式化/fallback/redaction：`test/usage-format.test.js:7-68`，不编译或运行 Swift target。Swift test target 单独定义在 `macos/CodexUsageStatus/Package.swift:13-16`。

本次结果：

```text
npm test: 3 passed, 0 failed
```

这只能证明 Node 测试仍通过，不能为 RefreshPolicy/AppDelegate/Fetcher 背书。

### 7.3 SwiftPM 与最小 harness

隔离到 `/private/tmp` 的 `swift test --scratch-path ...` 在 manifest 链接阶段失败，错误为：

```text
Undefined symbols for architecture arm64:
PackageDescription.Package.__allocating_init(...)
error: 'codexusagestatus': Invalid manifest
```

因此 XCTest 状态是 **未运行（工具链阻塞）**，不是代码 test failure。

为验证指定策略序列，使用显式 macOS SDK/target 直接编译仓库未修改的：

- `Configuration.swift`
- `RefreshPolicy.swift`
- `/private/tmp` 中只提供最小 `UsageSummary` 类型和固定时钟/断言的 harness

结果为前述两序列并输出 `HARNESS PASS`，进程 exit 0。harness 没有修改生产源码，也不覆盖 AppDelegate、真实 Timer 或 Fetcher。

接手核验时确认 `/private/tmp/codex-refresh-audit-harness-20261015/main.swift` 存在，并用该 harness 与当前仓库的 `Configuration.swift`、`RefreshPolicy.swift` 重新编译后运行；输出与上文一致。Harness 用固定时钟并按策略 interval 推进时间，不包含真实 fetch 或 Timer 延迟。

只读检查并运行 `docs/refresh-evaluation/replay.mjs --json`：其中 `CurrentPolicy` 的阈值、相邻快照比较、`lastSignificantDropAt` 窗口、倍增回退和失败 interval 与 Swift 策略一致；设置值由脚本正则读取 `Configuration.swift` 的整数常量。回放将 base 固定为源码默认值 120 秒，不读取 `CODEX_USAGE_REFRESH_SECONDS`，也不读取安装二进制，所以结果只代表默认配置下的合成模型。脚本明确把请求耗时设为零，进程启动数也只是每次尝试对应一次 one-shot process 的模型计数；不能用来推断真实功耗。当前回放 JSON 与 README 中默认场景的请求数和延迟结果一致。

## 8. current 源码与安装环境差异

### 8.1 只读安装核查

`~/Library/LaunchAgents/dev.local.CodexUsageStatus.plist` 的非敏感字段：

| 字段 | 当前值 |
|---|---|
| Label | `dev.local.CodexUsageStatus` |
| ProgramArguments[0] | `/Applications/CodexUsageStatus.app/Contents/MacOS/CodexUsageStatus` |
| RunAtLoad | `true` |
| KeepAlive | `true` |
| CODEX_BIN | `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex` |
| CODEX_USAGE_REFRESH_SECONDS | 未设置 |

`launchctl print` 只读状态：`running`，`runs=1`，`pid=41274`，`last exit code=(never exited)`。

安装包：

| 项目 | 当前值 |
|---|---|
| 路径 | `/Applications/CodexUsageStatus.app` |
| Bundle ID | `dev.local.CodexUsageStatus` |
| 版本 | `0.1.0-custom` |
| 签名 | ad-hoc；无 TeamIdentifier |
| executable SHA-256 | `a3ef4097fae44fb6a9baa4af7d4f29f7ab021ef78c4b19713e32bc3d6712027a` |

主 agent 提供的约 2026-10-15 22:45 UTC 单点 `ps` 快照：主进程 pid 41274、CPU 0.0%、RSS 42,960 KiB，观察瞬间没有独立 codex app-server。该数据只说明那个瞬间没有 fetch 子进程；不能证明周期、每轮 spawn、CPU/RSS p50/p95 或 wakeups。

### 8.2 差异与可确认边界

1. **Codex 路径明确不同：** current 源码默认 `/Applications/Codex.app/Contents/Resources/codex`（`Configuration.swift:4`），安装环境通过 plist 改为 ChatGPT.app 内嵌 CLI。
2. **refresh 环境覆盖未设置：** plist 中未设置 `CODEX_USAGE_REFRESH_SECONDS`。仅按 current 源码推导，默认配置会令 base=120、fast/minimum=30、effective maximum=300；这不能证明安装二进制实际包含这些值，因为其源码/构建来源未闭环。这里的 30 秒是源码定义的最短/快速间隔，不是已确认的安装程序固定默认刷新周期。
3. **但安装二进制与 current HEAD 的来源没有闭环：** bundle 只有 `0.1.0-custom`，没有 commit/build metadata；仓库中也没有一个可与安装 executable 做哈希等价对比的当前构建产物。因此不能把“如果”提升为已证实。若要关闭此 Unknown，应在不替换运行程序的前提下，用可复现构建/符号或构建清单比对；本次未做。
4. LaunchAgent 的 `KeepAlive` 负责主应用持续运行；刷新周期仍由应用内部单次 Timer 决定，plist 没有 StartInterval。

## 9. 可复现实验计划

目标不是只确认“会刷新”，而是把策略延迟、真实进程成本和系统调度偏差拆开。

### 9.1 统一事件日志与指标定义

每个实验事件至少记录 monotonic time、wall time、scenario/run id：

```text
ground_truth_change
refresh_requested(source=launch|timer|manual|wake)
refresh_admitted | refresh_dropped_inflight
app_server_spawned(pid)
initialize_written
rate_limit_response_received
child_term_sent | child_kill_sent | child_exited(status)
usage_applied | error_applied
next_interval_selected
timer_scheduled(deadline) | timer_fired
```

核心指标：

- **尝试启动延迟**：ground-truth change → refresh admitted；启动请求并不证明已经发现变化。
- **成功发现/可见延迟**：ground-truth change → 首次含有效变化的成功 usage snapshot applied；报告 p50/p95。若数据源公开时间未知，使用可确定的区间或 Unknown。
- **错误反馈延迟**：故障发生 → error applied，单独统计，不能当作成功检测。
- **调度误差**：timer fired − scheduled deadline；p50/p95/max。
- **实际周期**：start-to-start 与 completion-to-next-start 分开统计。
- **请求数**：每小时 refresh admitted、dropped、协议 request 数。
- **process**：spawn 数、正常/TERM/KILL exit 数、生命周期 p50/p95、orphan 数。
- **重叠**：最大 concurrent refresh 和 concurrent app-server；目标值均为 1。
- **资源/能耗**：主进程与子进程分别统计 CPU time、steady/peak RSS、wakeups/hour；在可用测量条件下记录能量或电池消耗。单点 `%CPU` 不作结论。
- **错误反馈**：故障发生 → error applied；恢复发生 → 首次 successful usage applied。

p95 至少用 100 个样本，优先 200；样本不足的 sleep 实验报告原始值、中位数和范围，不伪称稳定 p95。

### 9.2 场景矩阵

| 场景 | 输入/动作 | 必验 oracle | 首选环境 |
|---|---|---|---|
| 突发 burst | 稳定后单窗口下降 5、6、20；另一窗口不变/上升 | 立即选 30；阈值边界与两窗口 max 正确 | 离线 fake clock；再做少量集成 |
| 微小连续消耗 | 每样本下降 1/2/3/4；跨多轮累计 >5 | current 应复现“始终 base”；候选策略才应按规格决定何时触发 | 离线 evaluator，200+ 序列 |
| rounding | 原始 Double 跨 `.49/.51`；真实变化 4.0–5.0 | 记录 raw 与 integer snapshot，量化误差可见 | 离线模型测试 |
| idle（从启动） | 长时间完全不变 | current 始终 120，不会到 300；统计请求/process/wakeups | 离线策略 + 实机 1–2 h |
| idle（burst 后） | 触发一次后保持不变 | 精确 `30→30→120→240→300`，之后保持 300 | 离线 + 实机抽查 |
| structured failure | id=2 error / malformed result | error 分类、UI 延迟、300 retry、last-good 行为 | fake app-server |
| early exit | child 立即 exit 7，不输出 id=2 | current 约 20 秒后误报 timeout；无 orphan | fake executable，集成 |
| timeout | child 不响应并忽略 TERM | 20 秒 timeout；TERM/1s/KILL/1s；最终无 orphan | fake executable，集成 |
| stderr pressure | 大量 stderr 后响应/不响应 | 无 pipe deadlock；诊断策略明确 | fake executable |
| reset | 30/120/300 三种状态下 remaining 跳到 100 | current 不清 policy 历史；标签/下一间隔符合记录 | 离线 fake clock |
| manual | timer 前、timer 同时、inflight 中连续点击 | 无 overlap；记录 dropped；完成后 timer 重新锚定 | AppDelegate 集成/UI |
| sleep/wake | deadline 前睡、跨 deadline 睡、inflight 睡 | wake-to-refresh、重复/丢失、child cleanup | **必须实机** |
| launchd 重启 | 主进程退出/崩溃 | KeepAlive 重启、首次 refresh、无重复实例 | **必须实机且需另行授权** |

### 9.3 哪些可模拟，哪些必须实机

可完全模拟：

- RefreshPolicy 的 burst、微降、idle、reset、failure recovery、阈值/取整；
- UsageModels 的缺字段、单窗口、错序、多 limit；
- ResponseBox 的分块 JSON、错误/无关 id/迟到响应；
- fake child 的正常响应、立即退出、timeout、拒绝 TERM、stderr pressure；
- manual/timer 竞争（若把 clock/scheduler/fetcher 作为可注入 seam；current 尚无这些 seam）。

必须实机：

- macOS sleep/wake、App Nap、run-loop default mode、timer coalescing；
- 真实 ChatGPT 内嵌 codex CLI 的启动/响应/退出分布；
- Instruments/`powermetrics` 等得到的 CPU、RSS、wakeups、energy；
- launchd `KeepAlive`、登录启动、崩溃重启；
- 安装 app 的用户可见错误、badge 更新与菜单交互。

实机实验不得用当前单点 `ps` 替代，应持续采样主/子进程并用 spawn/exit 事件对齐；在没有明确授权前，不替换安装包、不修改 LaunchAgent、不强制 sleep/kill 生产进程。

## 10. 缺陷、取舍与待查分类

### 10.1 源码可确认的缺陷与契约待定项

1. 相邻整数 snapshot 的 5 点规则漏掉累计微小消耗。
2. 小幅持续下降不会更新 activity 时间；显著下降后 60 秒整就回到 120，并继续 240/300。
3. **契约待定：** 大于 300 的环境 base 会把 effective maximum 一并提高，因为实现使用 `max(300, base)`。产品若要求绝对 300 秒硬上限，当前行为与该契约不一致；若环境变量允许用户主动选择更长间隔，则这是有意配置行为，不能仅凭常量名认定为代码缺陷。
4. app-server 提前退出会等满 20 秒并误报 timeout；`appServerExited` 是不可达错误类型。
5. `usedPercent=nil` 被伪装为 100% remaining。
6. 单个 weekly 窗口可同时成为 5h/7d；多 limit 的 `values.first` fallback 缺乏语义保证。
7. 刷新关键路径没有可运行的 current XCTest 证据；Node `npm test` 与 Swift refresh 分离，当前机器 SwiftPM 又被工具链阻塞。

### 10.2 明确取舍（需产品目标决定，不直接判错）

1. 每轮新建 app-server，隔离简单但增加 process 启动、CPU、wakeups 成本。
2. 一次失败后等待 300 秒，避免故障风暴但延迟恢复。
3. error badge 覆盖 last-good 数据，错误醒目但失去“最后值 + 年龄”上下文。
4. inflight 请求直接 coalesce/drop，保证不重叠但 manual 不会排队。
5. timer 从 completion 重新锚定，保证 fetch 间隔不小于目标，但实际 start-to-start 高于名义值。
6. 启动后 idle 永远 base，而一次历史显著下降后 idle 最终永久 cap；是否需要状态衰减/重置属于策略定义。
7. 初始化三条消息流水发送，启动更快但依赖 app-server 对协议顺序的容忍。

### 10.3 待查（本次不能由静态审计证明）

1. 安装二进制是否精确来自 current HEAD，以及其编译入的 30/120/300 常量。
2. sleep/wake、App Nap、default-mode timer 的实际延迟与丢/重复事件。
3. 真实每轮 app-server startup/cleanup 时间、CPU、RSS、wakeups、energy 和 orphan 率。
4. 真实 app-server 是否可能早退、输出大量 stderr、拒绝 TERM，及当前协议流水顺序的兼容范围。
5. manual 与 timer 在真实菜单 run loop 下的竞争概率。
6. NaN/Infinity 环境值的 Swift/Timer 实际行为；应先加纯配置测试，不在生产实例尝试。

## 11. 本次验证证据与限制

完成：

- 指定 Swift 源码和所有现有 Swift tests 逐行审阅；关键结论引用 current 行号。
- `npm test`：3/3 通过。
- 直接 Swift harness：两个指定序列均通过断言，输出 `HARNESS PASS`。
- LaunchAgent/Info.plist/codesign/launchctl 非敏感字段只读核对。
- 未读取 `auth.json`、token、用量正文或其他敏感数据。

限制：

- `swift test` 被本机 SwiftPM/CLT `PackageDescription` 链接错误阻塞，未执行 XCTest。
- 未运行、替换或附加调试器到安装中的 app；未触发实际 refresh、sleep、kill 或 launchd 重启。
- 未对 CPU/RSS/wakeups 做持续测量，也未测真实能耗或电池消耗；主 agent 的 `ps` 仅是一个瞬间。
- 未修改任何生产源码或 tests，因此本报告只提供诊断与实验计划，不包含修复。
