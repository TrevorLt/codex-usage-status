# 睡醒读数与缓存策略评估

评估日期：2026-10-15。分析部分基于实施前 `a06d3aa` 源码及 Apple 官方文档、HTTP stale-while-revalidate 规范；文末另列本轮实际落地与验证，区分模拟通知和物理合盖。

## 结论

就“机器睡醒后马上能看到最近一次读数”而言，建议先用同进程内存中的 last-good 值，单独表达 stale 状态，并在 wake 时立即重绘、合并为一次刷新。**不需要磁盘快照来解决睡眠/唤醒问题。** 磁盘 JSON 只增加进程退出后冷启动时的占位体验；它还带来账号归属、过期、损坏、权限、原子替换和隐私处理等额外决策，因此应作为独立范围。

当前最直接的问题很可能不是内存值在睡眠期间丢失：`AppDelegate` 已把成功结果保存在 `lastUsage` 和 `lastRefreshDate`；刷新失败只设置 `lastError`，没有清除 `lastUsage`。但 `renderCurrentBadge()` 先检查 `lastError`，于是错误图覆盖了仍在内存中的成功读数。当前所查的 AppDelegate 也没有 `NSWorkspace` sleep/wake 观察者。静态代码不能证明实际 wake 时序，最终仍需在运行中的 app 上验证。

建议顺序：

1. 保留 last-good，并让失败信息与读数并存；明确标出 stale 和最后成功时间。
2. 用 `NSWorkspace.shared.notificationCenter` 监听 `didWakeNotification`；wake 时先重绘现有值，再触发一次刷新。
3. 用 single-flight 合并 wake、timer、手动刷新；如果 wake 到来时已有一次睡前请求在运行，最多记一个待执行的 wake 刷新，避免事件被静默丢弃。
4. 采用 30/60/120 秒作为正常刷新档位。它们是轮询间隔，不是缓存 TTL；wake 刷新是一次性事件，不能靠缩短常规间隔替代。
5. 先不读写磁盘快照。若以后明确要求进程重启后也立即显示旧值，再单独评估账号绑定和持久化策略。

## 实施前代码基线（a06d3aa）

- [`AppDelegate.swift`](../macos/CodexUsageStatus/Sources/CodexUsageStatus/App/AppDelegate.swift#L16) 保存 `lastUsage`、`lastRefreshDate`、`lastError`；成功路径更新 last-good，失败路径没有清除它们（`#L148`、`#L176`）。
- 同一文件的 `renderCurrentBadge()` 优先画 `errorImage`，只有没有错误时才画 last-good（`#L188`）。因此“刷新错误”和“无可用读数”目前被合成一个红色错误画面；可以把数据新鲜度、最近错误和显示值拆成并列状态。
- `refresh()` 用 `isRefreshing` 阻止并发，但 guard 命中时直接返回（`#L134`）。若 wake 事件恰好撞上睡前仍在进行的 fetch，单纯再次调用 `refresh()` 会丢掉这次 wake 意图；single-flight 需要合并请求，并为这种情况保留至多一个 trailing refresh。
- [`UsageModels.swift`](../macos/CodexUsageStatus/Sources/CodexUsageStatus/Domain/UsageModels.swift#L3) 的限额响应包含 quota bucket 的 `limitId`（例如 `codex`），但模型没有账号或登录会话标识。这个 `limitId` 不能用作账号绑定键。
- [`CodexUsageFetcher.swift`](../macos/CodexUsageStatus/Sources/CodexUsageStatus/Codex/CodexUsageFetcher.swift#L4) 通过本地 app-server stdio 获取数据，不是 HTTP/HTTPS 请求。
- [`Configuration.swift`](../macos/CodexUsageStatus/Sources/CodexUsageStatus/App/Configuration.swift#L3) 在该实施前基线中设最短间隔 30 秒、默认 120 秒、失败重试 300 秒；30/60/120 档是本轮随后落地的调度方案，不能把这些值混称为数据有效期。
- 当前 [`ApplicationAppearanceObserver.swift`](../macos/CodexUsageStatus/Sources/CodexUsageStatus/UI/ApplicationAppearanceObserver.swift#L11) 观察的是外观变化，不是电源状态。

## 三种方案

| 方案 | 睡醒时体验 | 进程重启后 | 主要代价与风险 | 评估 |
|---|---|---|---|---|
| 只保留内存 last-good | 同一进程仍有旧值；wake 立即重绘并异步刷新即可 | 重新启动时没有旧值 | stale 值必须与错误分开；同进程切换 Codex 账号后，旧值可能暂时属于前一账号 | **当前推荐**。能解决 wake 体验，改动集中且不增加持久数据 |
| 磁盘 JSON 快照 | 与内存方案相同；磁盘对 wake 本身没有额外帮助 | 可跳过空白占位，先展示快照再刷新 | 当前没有账号 ID 可验证快照归属；还要定义 TTL、reset 失效、格式迁移、损坏恢复、权限失败及文件 I/O | 只有明确需要跨启动展示时再立项；无账号绑定时默认不加载 |
| 只依赖刷新，不展示 last-good | 请求成功后才有读数 | 没有缓存 | 唤醒、进程启动或短暂故障期间显示空白/错误；不利用已有有效读数 | 保持权威数据来自刷新，但不满足快速恢复体验；不推荐单独使用 |

stale-while-revalidate 描述的是先呈现一份可接受的旧值，再在后台重新验证。RFC 5861 定义了 HTTP `stale-while-revalidate` 缓存控制扩展；Apple 的 [`URLCache`](https://developer.apple.com/documentation/foundation/urlcache) 和 [缓存访问文档](https://developer.apple.com/documentation/foundation/accessing-cached-data) 处理 URL Loading System 的 HTTP/HTTPS 响应。它们不是本项目 stdio 数据源可直接套用的通用快照 API。这里应实现同样的产品行为：last-good 继续可见，刷新异步进行，成功才替换，失败只更新错误状态。不要把缓存层称为服务端 revalidation，也不要让 stale 值参与成功状态或刷新策略的“新鲜快照”比较。

## stale 值、TTL 与窗口重置

缓存读取时间与刷新间隔是两个概念。每个成功样本应有 `fetchedAt`；UI 在最后一次成功后刷新尚未到期时标为当前，刷新失败或到期后标为 stale，并可展示“上次成功于……；最近刷新失败……”这样的分离信息。一次失败不能清空或覆写 last-good。

`resetsAt` 应逐窗口处理，而非整份快照一刀切：若当前时间已到某窗口的 `resetsAt`，该窗口的旧百分比不再当作当前读数，可显示未知/等待刷新；另一窗口在自身 `resetsAt` 之前仍可作为 stale 参考。重置后不得拿旧窗口值计算变化率或决定 30/60/120 档。当前 `UsageWindow.isExpired(at:)` 已能判断单个窗口过期，但 UI 仍需显式应用这个判断。

Apple 没有为这个本地额度数据定义 TTL。建议将 UI stale 展示上限设为独立策略参数；若保留当前 300 秒失败重试，可先以 10 分钟作为待验证的上限候选，超过后隐藏百分比并显示 unavailable，同时仍保留错误详情。这个数字是工程取舍，不是 Apple 规范，也不等于正常刷新 120 秒。未来若改变错误退避，应一起复核此值。无论显示上限如何，已到 `resetsAt` 的单个窗口都应立即失效。

对持久化快照还需额外处理时钟：记录绝对 UTC 时间；读取时若 `fetchedAt` 明显晚于当前墙上时间，不得把负年龄当成新鲜，可拒绝该快照并立即刷新。运行期间测量间隔可用单调时钟；跨进程时间戳仍需墙上时钟并在系统时间倒退/跳跃时按 stale 处理。允许的时钟偏差应是显式配置，不要悄悄把异常日期钳成当前时间。

## 如果以后批准磁盘缓存

### 账号绑定是加载门槛

响应目前只有 quota `limitId`，没有可核验的账号身份。内存 last-good 也不能保证在同进程切换账号时仍属于当前账号，因此必须显示 stale 和年龄；这一有限生命周期不等于已证明账号安全。跨启动的磁盘值更容易被另一个已登录账号复用。**在数据源没有可验证的账号绑定字段前，默认不读取磁盘快照，也不宣称它属于当前账号。** 不读取 `auth.json`、token、cookie、浏览器资料或其他未授权身份信号来补这个缺口。

### 目录与格式

Apple 将 `Caches` 定义为可丢弃、可重建的数据目录；`Application Support` 用于应用支持文件，且 Apple 的文件系统指南说明该目录会纳入常规备份。若它只是“重启后尽量先显示、随时能重新抓取”的快照，未来实现应使用通过 `FileManager` 查找的 app 专属 `Caches` 子目录，而不是硬编码 `~/Library/...`。只有产品要求保留且不能方便重建的数据，才考虑 `Application Support`。

不要用 `UserDefaults` 存这份读数。Apple 将它定位为 app 设置，并明确提醒不要存个人或敏感信息：defaults 数据以未加密形式写盘，写入也异步完成。显示样式等小型非敏感偏好适合 defaults；运行时额度快照不是偏好，也不需要把它塞进 defaults。

若经账号绑定审查后启用 JSON，最小字段建议为 schema version、成功时间、两个窗口的显示百分比、窗口时长和各自 `resetsAt`。不保存原始 app-server 响应、原始用量字段、plan type、认证材料或调试转储。缓存只在响应完整、通过解码/范围校验且刷新成功后写入；语义值或重置时间变化时才替换。一次刷新失败、无效响应或文件权限错误不得覆盖内存/磁盘中的旧成功值。

当前没有磁盘写入，未来实现应把 JSON 编码与文件读写放在后台执行上下文，绝不在 AppKit 主线程同步做 I/O。使用 `Data.write(to:options: .atomic)` 可先写辅助文件、成功后再替换目标文件，避免读者看到半截 JSON；它不负责账号绑定、过期判断或加密，也不替代对损坏文件的容错。读取失败、schema 不兼容、解码损坏、目录创建失败或权限拒绝时，丢弃/忽略磁盘候选，照常刷新并保留当前进程的 last-good；不要因缓存 I/O 失败让 app 启动失败。

“仅成功且语义变化才写盘”还有一个时间语义：若成功响应内容没变而不重写文件，文件里的时间只能表示最近一次内容变化，不能冒充最近一次成功验证。若将来要求重启后按最近验证时间判 TTL，就必须另行决定是否低频更新 `lastValidatedAt` 元数据；更新它也会产生写盘。未作决定前，宁可按文件时间保守地判 stale，也不要伪造新鲜度。

## sleep/wake 事件与验收

Apple 提供 [`NSWorkspace.willSleepNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification) 与 [`NSWorkspace.didWakeNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification)。两者应通过 `NSWorkspace.shared.notificationCenter` 注册；Apple 特别说明，改用其他 notification center 收不到这些通知。`willSleep` 可用于标记 stale、停止/失效 timer；不要在该回调里做长工作，Apple 说明观察者最多可能延迟睡眠 30 秒。`didWake` 中先重绘，再安排一次立即或短暂合并后的刷新，不要补跑睡眠期间错过的每一个 timer。

**仍待真实机器验证**，静态检查不能替代以下验收：

- app 带着成功读数睡眠并唤醒：读数应在 wake 重绘中保留且标记 stale，后台只启动一次刷新。
- wake 时刚好已有睡前 fetch：确认不会并发启动第二个 child；当前请求结束后最多补一次 wake 请求，或证明当前成功响应足够新鲜。
- wake 后 Codex app-server 暂时不可用：百分比保持但显示 stale/最近错误；成功恢复后只由有效成功结果更新读数和时间。
- 分别跨过 5 小时、7 天 `resetsAt`：过期窗口隐藏/标未知，未过期窗口单独保留；不能把一窗过期误判为另一窗也过期。
- 核对 wake 延迟、timer 重排、请求次数与进程生命周期。当前 `isRefreshing` 只能证明同一时刻不并发，不能证明 wake 意图一定执行。

## Apple 与规范来源

- [Apple: `NSWorkspace.didWakeNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification)；[Apple: `NSWorkspace.willSleepNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification) — 通知时机及必须使用 workspace notification center。
- [Apple: `URLCache`](https://developer.apple.com/documentation/foundation/urlcache)；[Apple: Accessing cached data](https://developer.apple.com/documentation/foundation/accessing-cached-data) — URL 请求响应缓存、HTTP/HTTPS cache policy 与重新验证。
- [RFC 5861: HTTP Cache-Control Extensions for Stale Content](https://www.rfc-editor.org/rfc/rfc5861.html) — stale-while-revalidate / stale-if-error 的 HTTP 语义；用于解释模式，不代表本地 app-server 实现了该协议。
- [Apple: `Data.WritingOptions.atomic`](https://developer.apple.com/documentation/foundation/nsdata/writingoptions/atomic) — 辅助文件写完后替换原文件。
- [Apple: Using the file system effectively](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively)；[`cachesDirectory`](https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/cachesdirectory)；[`applicationSupportDirectory`](https://developer.apple.com/documentation/foundation/url/applicationsupportdirectory) — 可重建缓存与应用支持文件的目录取舍。
- [Apple: `UserDefaults`](https://developer.apple.com/documentation/foundation/userdefaults) — 用于应用设置；不应保存个人/敏感信息，写盘异步。

## 本轮落地与验证

本机已更新为 `0.1.1-custom`，保留原有 LaunchAgent 的 RunAtLoad/KeepAlive。采用的正常成功间隔为 30/60/120 秒，静稳阈值分别为 90/300 秒；使用单调时间，显式有限环境值可选择固定周期。失败维持 300 秒重试。

已实现内存 last-good 优先显示，`~` 为中性 stale 标记，tooltip 保留最后成功时间和最近错误；成功数据替换旧值。每窗 `resetsAt` 到点由本地一次性 timer 重绘为未知，不新增网络查询。为了允许长时间合盖后仍参考未重置的 weekly，显示保留上限最终选择 24 小时，而非分析时提出的 10 分钟候选；这 24 小时只是 stale 参考值的保留上限，绝不是“24 小时新鲜”。重置时间先到则该窗口提前失效，墙钟时间异常倒退时隐藏旧值。

设备/屏幕唤醒先重绘，再去抖调度查询；网络从不可用恢复也可提前重试，初次网络状态通知不触发额外查询。自动查询仍经过 30 秒间隔与 single-flight。睡眠前在途结果以代次识别并丢弃，恢复意图只消费一次；旧 wake 意图不再覆盖恢复请求的失败退避。设备睡眠期间停掉查询和显示有效性 timer，醒来重建。

本轮没有写入 quota txt/JSON、没有读取认证文件，也没有启用跨启动缓存。同一进程切换账户而尚未成功刷新时仍存在 last-known 属于旧账户的可能，因此 UI 明示“最后一次观测”，不宣称这些值代表已验证的当前账户。

验证证据：

- 真实旧 AppDelegate + 模拟 fetcher：成功显示 65%/88% 后，再失败即被错误画面遮住（回归测试 FAIL）。
- 修正版同一路径：65%/88% 保留，错误和 stale 信息同时出现（PASS）。
- `bash scripts/test-wake-recovery.sh`：Swift 6 直接编译真实 AppDelegate、policy、models、renderer，仅替换 fetcher；17 项检查通过，包括重复 wake、自动恢复、睡前挂起请求、失败退避不被覆盖、窗口在显示期间跨过期限及过期重绘不查询账户。
- 更新包与安装包哈希一致，签名校验通过，LaunchAgent 状态 running；真实 `--once` 成功读取 5H/7D；菜单栏截图确认两窗正常显示且在持续使用期间更新。
- 完整 SwiftPM/XCTest 仍受本机 PackageDescription 链接问题限制；Node 3 项测试通过，但不将其当作原生 UI 测试。

工作区旧应用备份：`work/wake-install-backup.me9sce/CodexUsageStatus.app`。未强制物理休眠；真实合盖后 macOS 通知投递、网络重新建立的端到端表现，仍需下一次自然唤醒观察。截图仅证明正常运行时的显示，不替代该验证。
