# CodexUsageStatus 刷新调度研究：新鲜度、请求预算与 macOS 能效

研究日期：2026-10-15（America/Chicago）
范围：只研究与评估，不修改 app、安装内容或运行中的程序。

## 结论先行

1. **“事件 + 轮询”是正确方向，但当前没有已验证的“额度发生变化”事件。** `NSWorkspace` 唤醒、`NWPathMonitor` 路径恢复、低电量状态变化、用户打开菜单/手动刷新都可以减少特定场景的无效等待；它们并不等于额度变化通知。只要额度变化本身仍靠轮询发现，就不能称为严格实时。
2. **候选 V2（30 → 60 → 120 → 300 秒）不是 current 的全面改进。** 它在连续小步变化时更快，但 idle 退到 300 秒后，若 burst 恰好发生在一次 poll 后 1 秒，首次发现可等 299 秒；current 尚处于 120 秒周期时最多约等 119 秒。V2 可能同时“某些场景请求更少”和“某些场景更慢”，不能声称所有场景更实时且更省。
3. **我赞成“任何有效额度下降都重新进入 active”，不赞成直接把 300 秒 idle 设为未经量测的默认。** 更稳妥的首发候选是 30/60/120 秒、idle 先封顶 120 秒；300 秒作为实验或用户明确选择。若以后获得可靠额度事件，或实测证明 300 秒带来有意义的系统成本下降且用户接受五分钟盲区，再升为默认。
4. **论文支持“新鲜度与采样成本需要联合优化”“自适应策略可在特定模型中优于固定周期”，不证明本项目的 30/60/120/300、90 秒/5 分钟/15 分钟参数。** 下文所有具体参数都标为工程建议，必须用本项目的请求延迟、child-process 成本、idle wakeup 与 Energy Log 实测校准。
5. **常驻 app-server 与每次刷新启动 app-server，谁更省不能先验断言。** 当前实现每次请求都启动、初始化、读取再终止子进程；常驻方案可能减少启动成本，也会增加常驻内存、生命周期与断线恢复成本。两者必须在同一 Mac 上实测，本文不给虚构节能百分比。

## 检索方法与边界

初稿记录曾使用 Google Scholar 查询作为文献发现入口，并保留下列精确题名查询链接。本次接手复核时，web open 工具无法访问 Scholar 页面，因此无法独立确认初稿当时的访问情况或查询结果；以下链接仅作为后续复核入口，不作为事实依据。论文题名、作者、摘要与结论按已核验的 arXiv 原文及出版方记录复核。

- ["Age of Information" adaptive sampling polling](https://scholar.google.com/scholar?q=%22Age+of+Information%22+adaptive+sampling+polling)
- [Real-time status: How often should one update?](https://scholar.google.com/scholar?q=%22Real-time+status%3A+How+often+should+one+update%3F%22)
- [Update or Wait: How to Keep Your Data Fresh](https://scholar.google.com/scholar?q=%22Update+or+Wait%3A+How+to+Keep+Your+Data+Fresh%22)
- [Detecting State Transitions of a Markov Source](https://scholar.google.com/scholar?q=%22Detecting+state+transitions+of+a+Markov+source%22)
- [The Age of Incorrect Information](https://scholar.google.com/scholar?q=%22Age+of+Incorrect+Information%3A+A+New+Performance+Metric+for+Status+Updates%22)

论文元数据与论据来自 IEEE 出版页、作者稿或 arXiv 原文。Apple 部分只采用 Apple 官方开发者文档。Apple 当前 symbol 页面通常不标发布日期，本文如实写“页面未标发布日期，访问于 2026-10-15”；归档能效指南则采用页面明确列出的更新时间 2016-09-13。

## 学术证据

### 1. AoI 的目标不同于吞吐量或单次延迟

Kaul、Yates、Gruteser 的 *Real-time status: How often should one update?* 以“接收端最新样本自生成以来经过的时间”衡量新鲜度，并在 FCFS 队列模型中证明存在使平均 age 最小的生成速率；该速率不同于最大化利用率/吞吐量或最小化包传输延迟的速率。论文会议日期为 2012-03-25 至 2012-03-30，IEEE Xplore 收录日期为 2012-05-10。[IEEE 出版页与 DOI 10.1109/INFCOM.2012.6195689](https://ieeexplore.ieee.org/document/6195689/) · [作者 PDF](https://winlab.rutgers.edu/~gruteser/papers/sanjitnew.pdf)

对本项目的可迁移结论是：**“请求更频繁”“单次返回更快”和“用户看到的数据更鲜”不是同一个目标。** 但该论文是通信队列模型，不包含 macOS timer、App Nap、Swift `Process` 启动或 Codex 数据源滞后，不能据此给出刷新秒数或节能比例。

### 2. 最快地再次请求不一定得到最低 age

Sun、Uysal-Biyikoglu、Yates、Koksal、Shroff 的 *Update or Wait: How to Keep Your Data Fresh* 研究带一般 age penalty、相关/随机传输时间和最大更新频率约束的更新策略。论文证明 zero-wait（上次完成后立刻提交下一次）虽可最大化吞吐、最小化传输延迟，却不总能最小化信息 age；在传输时间正相关、高随机/重尾或 age penalty 快速增长的模型中，zero-wait 可能明显偏离最优。arXiv 初稿提交于 2016-01-11、v9 为 2017-04-21；期刊版刊于 2017-11。[arXiv 原文](https://arxiv.org/abs/1601.02284) · [IEEE DOI 10.1109/TIT.2017.2735804](https://doi.org/10.1109/TIT.2017.2735804)

这支持“不要因为一次变化就无限期保持最快轮询”“把请求频率当显式约束”。它**不**直接支持指数退避，也不证明某个等待阶梯适用于本地 app-server。

### 3. 变化检测应联合考虑变化率、陈旧度与采样预算

Champati、Skoglund、Gross 的 arXiv 预印本 *Detecting State Transitions of a Markov Source: Sampling Frequency and Age Trade-off* 把来源建模为有限状态 DTMC，定义“自上次观测状态第一次发生跃迁以来的时间”为 age penalty，并分别研究“给定平均采样频率预算，最小化平均 age penalty”和反向约束。其数值实验中，基于观测状态的 Markov 采样策略优于最优固定周期采样；不同状态的转移概率不同时，下一次采样间隔也不同。arXiv 初稿提交于 2020-01-22、v2 为 2020-05-05；扩展期刊版发表于 2022-05，作者名单另含 Magnus Jansson。[arXiv 原文](https://arxiv.org/abs/2001.10381) · [IEEE 期刊 DOI 10.1109/TCOMM.2022.3160563](https://doi.org/10.1109/TCOMM.2022.3160563)

这篇论文与“变化率高时缩短间隔、稳定时延长间隔”最接近，但仍有关键限制：真实额度不是已知转移矩阵的 DTMC；只在采样时才能看到量化值；变化发生时刻是区间删失的；数据源还可能批量更新或滞后。因此，本项目的变化率估计只能是启发式，不能套用论文中的最优性结论。

### 4. “旧”不等于“错”；没有变化时重复更新的信息价值低

Maatouk、Kriouile、Assaad、Ephremides 的 *The Age of Incorrect Information: A New Performance Metric for Status Updates* 将时间陈旧度与监视端是否持有错误状态结合：监视端仍正确时不计 penalty，状态不一致后 penalty 随时间增长；论文也研究了功率/发送预算约束。arXiv 初稿提交于 2019-07-15、v2 为 2020-07-09；期刊版发表于 2020-10。[arXiv 原文](https://arxiv.org/abs/1907.06604) · [IEEE DOI 10.1109/TNET.2020.3005549](https://doi.org/10.1109/TNET.2020.3005549)

对应本项目：连续相同读数时，高频刷新带来的信息价值有限；一旦观察到有效下降，应提高短期采样价值。但论文的“功率预算”是通信模型中的约束，不是 Mac 电池实测，不能把其移动/无线结论写成 macOS 节能事实。

## Apple 官方能效与系统事件证据

| 主题 | Apple 的具体结论与日期 | 对本项目的含义 |
|---|---|---|
| timer 与事件 | Apple 的 *Minimize Timer Usage* 指出 timer 唤醒空闲系统有能耗成本；若状态可由事件通知，应响应事件而非用 timer 监视；必须使用 timer 时应设置合理 timeout、停止不需要的 timer、设置 tolerance。归档页更新于 **2016-09-13**。[官方文档](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html) | 睡眠期间停止调度；网络恢复、唤醒、低电量变化走事件；额度本身没有可靠事件时仍需兜底 poll。 |
| tolerance / coalescing | `Timer.tolerance` 允许 timer 在计划时间之后、计划时间加 tolerance 之前触发，不会提前；该灵活性帮助系统做功耗和响应性优化。页面未标发布日期，macOS 10.9+，访问于 **2026-10-15**。[官方文档](https://developer.apple.com/documentation/foundation/timer/tolerance) | 为自动 timer 设置 tolerance；延迟上界必须把 tolerance 算进去，不能仍声称精确 30/60/120/300 秒。 |
| QoS | Apple 说明 QoS 会影响 CPU/I/O 优先级和 timer latency；高优先级通常使用更多资源。`utility` 用于用户不立即等待、但在用户可见时间尺度运行的周期内容更新。归档指南更新于 **2016-09-13**；当前 enum 页面访问于 **2026-10-15**。[QoS 指南](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/PrioritizeWorkAtTheTaskLevel.html) · [`QualityOfService.utility`](https://developer.apple.com/documentation/foundation/qualityofservice/utility) | 自动刷新使用 `.utility` 合理；用户手动 Refresh 可提升为 `.userInitiated`。当前 fetch 已在 detached `.utility` task 中。 |
| Low Power Mode | `ProcessInfo.isLowPowerModeEnabled` 在 macOS 12+ 可查询；Apple 建议状态变化后读取该属性，并在低电量模式下减少 app 活动。页面未标发布日期，访问于 **2026-10-15**。[属性与建议](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled) · [power-state notification](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/nsprocessinfopowerstatedidchange) | 低电量模式应走单独、较慢的自动 cadence policy，并取消实验 boost；具体档位待测，手动刷新仍可用。 |
| sleep / wake | `NSWorkspace.willSleepNotification` 在设备睡眠前发出，`didWakeNotification` 在唤醒后发出；两者必须通过 `NSWorkspace.notificationCenter` 注册。页面未标发布日期，访问于 **2026-10-15**。[will sleep](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification) · [did wake](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification) | sleep 时 invalidate timer；wake 后合并为一次刷新，不补跑睡眠期间错过的所有 timer。 |
| 网络路径变化 | `NWPathMonitor` 是“监视并响应网络变化”的 observer，提供 path update handler；macOS 10.14+。页面未标发布日期，访问于 **2026-10-15**。[官方文档](https://developer.apple.com/documentation/network/nwpathmonitor) | `unsatisfied → satisfied` 可触发一次去抖后的重试，但路径可用不证明 Codex 服务可达，更不证明额度发生变化；实际请求结果仍是权威信号。 |
| App Nap | Apple 说明 App Nap 可降低 timer 触发频率并做 I/O throttling，但明确说不要依赖 App Nap 代替 app 自己进入 idle。归档页更新于 **2016-09-13**。[官方文档](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html) | 不把“系统可能 throttle timer”当调度策略；主动停止 sleep/无用 timer，并在 UI 中显示最后成功时间。 |

Apple 的 iOS 蜂窝 radio tail 等结论没有作为 Mac 证据使用。Mac 上一次本地 app-server 请求的 CPU、进程启动、网络与电池成本都保持为 **Unknown，待实测**。

## 当前实现：已确认事实

代码检查基于本仓库 2026-10-15 的共享工作树；这些是实现事实，不是论文结论。

- `Configuration.swift`：自动刷新下限 30 秒、默认 120 秒、默认 base 下回退目标 300 秒、显著下降门槛 5 个百分点、显著变化 active 窗口 60 秒、失败固定 300 秒、单请求 timeout 20 秒。环境覆盖的 base 若高于 300 秒，effective maximum 也会相应提高，300 不是所有配置下的硬上限。
- `RefreshPolicy.swift`：仅当任一窗口的**显示剩余百分比下降至少 5 点**才进入 30 秒；60 秒稳定后依次走 120、240、300 秒。此前从未发生 ≥5 点下降时，小变化仍保持 120 秒。
- `UsageModels.swift`：`usedPercent: Double` 被转换成四舍五入的 `remainingPercent: Int`。可见下降以整数百分点计；小于 1 个百分点的真实变化可能被隐藏，但跨越取整边界时仍可导致显示整数变化。
- `AppDelegate.swift`：one-shot `Timer`；`isRefreshing` 阻止重叠请求；调度新 timer 前 invalidate 旧 timer。当前 timer 未设置 tolerance；没有 sleep/wake、Low Power Mode 或 `NWPathMonitor` 状态。
- `CodexUsageFetcher.swift`：每次刷新都用 Swift `Process` 启动 `codex app-server --listen stdio://`，发送 initialize、initialized、`account/rateLimits/read`，得到结果后终止 child process；自动任务 QoS 为 `.utility`。

## 延迟模型：必须把轮询盲区和数据源滞后写清楚

设固定轮询间隔为 `T`，timer tolerance 为 `J`，一次 app-server 请求与渲染用时为 `S`，数据源从真实用量变化到 `account/rateLimits/read` 可见的滞后为 `Lsource`。

- 若变化相位相对 poll 均匀、`Lsource = 0` 且请求可靠，纯轮询的平均等待约为 `T/2`，最坏等待接近 `T`。
- 在没有额外调度阻塞、采样间隔固定的理想模型中，允许的 tolerance 可把等待增加到接近 `T + J`。它不是实际系统的最大延迟保证：Timer 不是实时机制，run-loop 忙碌或模式不匹配可造成额外延迟；当前应用从请求完成后重新计时，实际周期还包含请求耗时。[Apple Timer](https://developer.apple.com/documentation/foundation/timer)
- 用户端到端看到变化的时间近似 `Lsource + Dpoll + S`；只有 `Dpoll` 受本 app 的 cadence 约束。
- `resetsAt` 是窗口重置时间，不是样本生成时间。若 app-server 不提供 source-generated timestamp，就不能从本地成功读取时间推断 `Lsource`。

因此：

- 30 秒轮询：在上述理想模型中平均约 15 秒、等待接近 30 秒；3 秒 tolerance 可再允许延后约 3 秒，实际还有请求、数据源及系统调度延迟，不能据此给出严格端到端上界。
- 120 秒轮询：理想平均约 60 秒、最坏接近 120 秒。
- 300 秒轮询：理想平均约 150 秒、最坏接近 300 秒。
- **idle → burst 且没有可靠额度事件时，V2 的首次发现最坏接近 300 秒。** 第一次 poll 发现下降后，30 秒 active 才开始；active 不能倒推缩短已经发生的 299 秒等待。

“事件 + 轮询”的准确表述应是：**事件缩短特定环境转换后的等待，低频轮询覆盖没有事件的额度变化。** wake/path/manual/menu-open 事件可降低对应场景延迟；在没有 app-server 额度 push 的前提下，不能称为 polling-only 实时。

## 离线 current vs V2：反例与权衡

共享的 `docs/refresh-evaluation/replay.mjs` 在 2026-10-15 运行通过。它是 1 小时的整数额度合成回放：请求耗时、timer jitter、数据源滞后与 push event 均设为 0，**不是能耗 benchmark**。关键结果如下：

| 合成场景 | current | candidate 30/60/120/300 | 能说明什么 |
|---|---:|---:|---|
| idle | 30 attempts/h | 21 attempts/h（含启动阶段；稳定后将趋近 12/h） | V2 可减少 idle 请求，但未量出能耗。 |
| 每 60 秒小降 1 点 | 30 attempts/h；P95 103s | 120 attempts/h；P95 13s | V2 延迟更好，但请求数为 current 的 4 倍。 |
| burst 恰在 idle poll 后 1 秒 | 首次/最大下一采样延迟 119s | 299s | 明确反例：V2 不能声称所有场景更实时。 |
| 600–900 秒瞬时失败 | 26 attempts、1 failure；变化→下次成功样本最大 403s | 109 attempts、4 failures；变化→下次成功样本最大 433s | 递增重试的相位可能让变化更久才被成功样本观察到，同时制造更多失败尝试。 |

这里的 403s/433s 是合成回放中“变化到下一成功样本”的最大间隔，不是故障结束后的恢复等待。这组回放只证明调度逻辑的**可能结果**。真实 `usedPercent` 到达模式、app-server publication lag、请求耗时和能耗都没有被模拟。

## 对候选 V2 的独立判断

### 值得保留

- 自动刷新下限仍为 30 秒；不默认上线更快 cadence。
- 对同一窗口、同一 reset 周期中的任何**有效下降**重新标记 active，而不是要求一次下降 ≥5 点。
- 以“自最后一次可见变化经过多久”决定退阶，而不是靠一次大变化后机械倍增。
- 睡眠时停止，唤醒后合并为一次 refresh。
- 所有自动触发统一经过 single-flight、去抖和请求预算。

### 需要修改或 gated rollout

- **默认 idle 300 秒：不建议立即普遍上线。** 在没有可靠额度事件时，它把最坏首次发现从 current 的常态 120 秒扩大到 300 秒。建议先采用“30 秒至 90 秒、60 秒至 5 分钟、之后 120 秒”的延迟优先版本；300 秒仅作为 `energy-saver` 实验组。
- **任何“变化”不能只写 `current != previous`。** 窗口 reset 会使剩余值上升；账号/limit/window identity 变化也会造成跳变。有效下降应要求同一 `limitId`、同一窗口时长、同一 `resetsAt` 周期，且 raw used percent 单调增加。缺少这些条件时应重建 baseline，不把跳变当消费速率。
- **当前 Int 四舍五入会隐藏亚百分点变化。** 若调度真的要对“任何有效下降”反应，候选实现应保留 raw `Double` 给 policy，UI 仍可显示 Int；同时设置极小 epsilon 防浮点噪声。epsilon 必须根据实测数据定，本文不虚构值。
- **失败递增退避不是无条件更好。** 它可更早做第一次恢复尝试，也会在特定 outage 相位中比固定 300 秒更晚命中恢复窗口。上线条件应是按错误类型分类并做回放，而不是只看“指数退避”标签。

## 可行状态与转换（建议，不是论文证明）

| 状态 | 建议自动间隔 | 进入条件 | 退出/说明 |
|---|---:|---|---|
| `active` | 30s | 启动短暂 warm-up；或任一有效额度下降 | 最后一次可见下降后 90s 转 `warm`。 |
| `warm` | 60s | quiet ≥90s | quiet ≥5min 转 `cool`；任何有效下降回 `active`。 |
| `cool` | 120s | quiet ≥5min | 默认建议停在 120s；实验组 quiet ≥15min 可转 `idle-eco`。 |
| `idle-eco` | 300s | quiet ≥15min，且用户/实验明确接受盲区 | 无可靠事件时最坏首次发现约 300s；任何下降回 `active`。 |
| `failure-1/2/3` | 60/120/300s | transient request failure | 成功即回按 quiet age 计算的状态；不要因为失败把它计作“无变化”。 |
| `offline` | 无常规快速 retry；15min safety poll | `NWPath` 明确 unsatisfied | path 恢复后去抖触发一次；path 只作提示，实际请求裁决成功。 |
| `low-power` | `max(当前间隔, 120s)`；idle 可 600s | Low Power Mode on | 禁用实验 boost；手动 refresh 不受自动预算阻断。 |
| `sleeping` | timer 停止 | `willSleepNotification` | wake 后等 3–5s，并与 path 事件合并为一次请求。 |

参数边界建议：正常成功轮询默认不短于 30 秒、不长于 120 秒；健康 idle 的 300 秒仅用于明确接受盲区的 eco 实验。失败重试间隔应作为独立错误策略实测，不应与健康 idle cadence 混为一谈。低电量模式走单独策略，可实验性地放宽到 600 秒；单请求 timeout 暂保留现有 20 秒，除非延迟实测支持修改。上述每个数字都是待验证配置，不是论文最优值。

## 变化率估计：可用，但只应做弱信号

可对连续成功样本计算：

```text
delta_i = max(0, rawUsed_i - rawUsed_(i-1))
rate_i  = delta_i / elapsed_i
alpha   = 1 - exp(-ln(2) * elapsed_i / H)
rateEWMA_i = (1 - alpha) * rateEWMA_(i-1) + alpha * rate_i
```

建议先以 `H = 5min` 作为实验半衰期，并同时保留“距最后一次可见下降的时间”。注意：

- 变化发生时刻只知道落在两次 poll 之间，`rate_i` 是区间平均，不是瞬时速率。
- app-server 若批量发布，EWMA 会把 publication burst 误认成用户 burst。
- 失败样本不能作为 `rate=0`；reset/account/window identity 变化必须清空 estimator。
- rate estimator 只用于选择 30/60/120 档或记录 telemetry，不应用来宣称预测了用户行为。
- 先记录 raw 样本分布再定 rate threshold；本文不建议凭空写一个“pp/min”阈值。

## 请求预算、去抖与 single-flight（建议参数）

所有 timer、wake、path、power、menu-open 和 manual 原因应进入一个 refresh arbiter：

- `inFlight == true` 时不启动第二个请求；记录至多一个 `pendingRefresh`，把多个 reason 合并。
- 自动事件去抖 3 秒；自动请求仍受“距上次 attempt ≥30 秒”限制。手动 Refresh 可立即请求，但仍 single-flight。
- 统计所有自动 attempts；若以后配置任何请求预算，成功与失败都应计入，避免离线时预算失真。
- 30 秒自动请求最小间隔对应持续活跃时理论上约 **120 attempts/h**（实际值还受请求耗时影响）；不应再叠加未经测量的 30/h、60/h soft/hard budget，否则持续活跃时会强制退阶，与 30 秒 active 策略相矛盾。
- 若产品后来确实需要 token bucket（例如 `r = 120/h`），必须同时写明容量 `B`、补充速率及哪些触发会扣 token；只能声称“长期平均不超过 120/h，另允许至多 `B` 次 burst”，不能称为严格 rolling-hour hard cap。
- Low Power Mode 使用独立 cadence policy，按系统状态变化切换到较慢档并禁用实验 boost；不要把低电量规则混进正常活跃状态的请求预算。具体数字需实测。

### 10 秒 boost 仅作为实验

10 秒轮询不能帮助一个**没有触发事件的 idle burst**更早被发现；它只能在已经有可靠事件或第一次 poll 已发现下降之后，更密地观察后续变化。若做实验，建议：

- feature flag 默认关闭；Low Power Mode、offline、sleeping 时禁止；
- 单次最多 6 次/60 秒，rolling hour 内最多 12 次 boost attempts；
- 到期无论是否继续变化都回 30 秒 floor；
- boost 请求计入总预算；比较 p50/p95 change-to-display、attempts、CPU time、idle wakeups，而不是只看“看起来更快”。

这些 10 秒/6 次/12 次都是资源边界建议，不是论文结论，也不建议默认上线。

## 失败、睡眠恢复与 path 的具体处理

1. **瞬时 app-server/transport 错误**：可试 60 → 120 → 300 秒，cap 300；每次实际 attempt 重新计算。与 current 固定 300 秒做 outage 相位 sweep，接受其“可能更早，也可能更晚”的事实。
2. **明确 offline**：停止快速 retry，等待 `NWPathMonitor` 从 unsatisfied 变为 satisfied；为防 path 事件丢失，保留 15 分钟 safety poll。path satisfied 不直接清除 error，只有真实请求成功才清除。
3. **确定性配置错误**（binary 不存在、长期不兼容输出）：不按 60 秒重试；建议 15 分钟或环境/手动事件再试，并在菜单中明确错误。
4. **sleep**：`willSleep` invalidate timer，不做网络/进程清理之外的长任务；`didWake` 后 3–5 秒触发一次，若 path 尚未 satisfied 则等待 path 或 30 秒 fallback。不要补跑每个错过的 interval。
5. **同一时刻 wake + path + menu-open**：合并为一次请求；请求中又收到事件时，完成后最多补一次，并再次检查 30 秒自动 floor。

## stale timestamp：必须区分“本地观测时间”和“源生成时间”

UI 应始终显示：

- `Last successful read: <absolute time> (<relative age>)`
- 若最后一次 attempt 失败：保留最后一份成功值，同时显示 `Stale — refresh failed at <time>` 和错误摘要。
- tooltip/menu 打开时现算 relative age，不用每秒 timer 刷新“x 秒前”。

建议把 stale threshold 定为：

```text
max(120s, 2 * scheduledInterval + timerTolerance + requestTimeout)
```

例如 300 秒档、10% tolerance、20 秒 timeout 下约为 650 秒。它只是 UI 告警阈值，不代表数据源保证。若 app-server 没有 sample-generated timestamp，文案必须叫 `Last successful read/observed`，不能叫 `Data updated at`。数据源滞后 `Lsource` 应在诊断中显示为 `Unknown`。

## 常驻 app-server vs 每次启动：必须实际量测

当前 one-shot 方案的成本可能包括 child process 启动、初始化、stdio 握手、读取和终止；常驻方案可能降低每次启动成本，却引入常驻 RSS、保活/断线、升级兼容与睡眠恢复成本。没有测量前，不能断言任一方案更省。

建议在同一 Mac、相同电源/网络/额度脚本下做随机交错 A/B：

| 维度 | one-shot | persistent 候选 | 必测指标 |
|---|---|---|---|
| idle 300s，60 分钟 | 每 poll 启停 | 单 child 常驻 | parent+child CPU time、RSS、idle wakeups/h、process starts、Energy Log |
| active 30s，30 分钟 | 高频启停 | 复用 stdio | request p50/p95、CPU ms/request、失败率、Energy Log |
| offline/恢复 | 每次失败后退出 | 断线检测与重连 | 恢复时间、失败 attempts、残留 child、错误可见性 |
| sleep/wake 10 次 | 每次 wake 新启 | 常驻 child 的 sleep 生命周期 | wake 后成功率、重复请求、child 泄漏、首次响应 |

实现测量时用 signpost 包住 spawn、initialize、rate-limit response、terminate；Instruments Energy Log/Xcode Energy gauge 与 Activity Monitor idle wakeups 用于相对比较，并同时记录 wall time、CPU time、RSS。至少重复多轮并报告中位数、p95 与方差。Energy Impact 是相对指标，不应被包装成未经校准的焦耳或节能百分比。

## 建议的决策顺序

1. 先把现有代码和 candidate 的离线 replay 扩展为更多 phase sweep：burst 相位 0…T−1、outage 起止相位、publication lag、20 秒 request duration、reset/window rollover。
2. 默认候选先采用 30/60/120、任何有效下降回 active、sleep/wake/path/low-power、tolerance、single-flight 与 stale timestamp；保留 120 秒 idle 上限。
3. 将 300 秒 idle 和 10 秒 boost 分别做独立 feature flag，避免把两个变量混成一次实验。
4. 在真实 one-shot 实现上先记录 attempts、spawn/response/terminate latency、error class、成功样本变化分布；不记录 token、prompt 或用户内容。
5. 完成 one-shot vs persistent 能效与延迟 A/B 后，再决定是否改变进程生命周期和 300 秒默认值。

最终判断：**论文与 Apple 文档支持“事件优先、预算约束、自适应轮询、允许 timer 合并、睡眠/低电量主动降频”；它们不支持把 candidate V2 宣称为普遍更实时或更省。** 在当前缺少可靠额度事件、缺少 Mac 实测的条件下，120 秒 idle cap 是更诚实的默认；300 秒是明确接受最长五分钟 polling blind spot 后的节能实验。

## 与优化设计稿的交叉评审

`docs/refresh-optimization-plan.md` 已采用正常 cadence 30/60/120 秒、默认 idle cap 120 秒，与本报告建议一致；300 秒仅作为明确标注的 eco candidate。回放中的 `candidate-30s` 包含 300 秒档，用于展示延迟反例；新增 `--cap120` 单独评估成功后 120 秒封顶版，不能混用两组结果。离线评估 README 将回放定位为合成策略比较，而非上线或能耗证明；报告中的 403/433 秒也按同一边界解释。
