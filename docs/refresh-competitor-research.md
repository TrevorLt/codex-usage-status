# CodexUsageStatus：路径发现与失败处理研究

研究日期：2026-10-15（America/Chicago）
范围：macOS 菜单栏 usage/rate-limit 监视器；核对 CodexUsageStatus 发布版源码与文档、OpenAI Codex 源码/公开 issue、CodexBar 及 Claude 类竞品的公开 README、源码、issue 和 release。本文只记录研究，不包含生产代码修改、测试运行、提交或推送。未读取任何认证文件、token、cookie、API key、浏览器数据或用户私密数据。

## 结论摘要

本文的研究记录是在本地修复落地前生成的；后文关于“未提交、尚未验证”的描述是研究时点的状态，不是当前工作树的最终验证结论。

“问号”不能单独证明是 Codex 路径错误。按 CodexUsageStatus 当前 UI 实现，如果还没有成功读取过额度，且最近一次刷新失败，状态栏显示错误图标；若已有成功数据，刷新失败会保留旧数字并标为陈旧。因此，新用户安装后持续看到问号，能确认的是“这个进程还没有拿到可用额度”，具体原因仍需查看 Settings 中的错误文本。

不过路径错误是 v0.1.1 的首要候选：该 release 的源码把 Codex 可执行文件固定为 `/Applications/Codex.app/Contents/Resources/codex`。OpenAI 的公开 macOS issue 记录了 ChatGPT.app 安装、从旧 `Resources/codex` 迁移到 `Resources/codex-cli/bin/codex`、以及 CLI 内层 bundle 可执行文件等布局变化。另有公开复现证明，Codex CLI 未登录时 `account/rateLimits/read` 会返回认证错误；若客户端把该错误折叠成普通刷新失败，用户也只会看到问号。

本次只读检查还发现：当前工作树已有未提交的 `CodexPathResolver` 与错误分类改动，以及路径/进程生命周期测试文件；README、technical review 和 `docs/diagnostics.md` 也有未提交的配套改动。这些是既存工作，不属于本研究的修改，均不包含在 v0.1.1 tag/release 中；研究记录将发布版事实与工作树中的待审改动分开说明。v0.1.1 tag 上的 README 仍把旧路径写成唯一默认位置。

## 版本与证据边界

- GitHub 上的公开发布为 [CodexUsageStatus v0.1.1](https://github.com/TrevorLt/codex-usage-status/releases/tag/v0.1.1)。其 [release notes](https://github.com/TrevorLt/codex-usage-status/blob/v0.1.1/docs/release-notes-v0.1.1.md) 列出 sleep/wake 恢复、失败后保留最后成功读数和双架构下载，但没有逐类说明初始化、登录、可执行文件、RPC 和 schema 错误。
- [v0.1.1 README](https://github.com/TrevorLt/codex-usage-status/blob/v0.1.1/README.md) 将要求写为 Codex 在 `/Applications/Codex.app`，并把该路径列为已知限制。该说明与 ChatGPT.app 安装及 bundle 内 CLI 布局变化不符。
- GitHub CLI 查询显示该 fork 的 Issues 已关闭/未启用，因此没有可核对的本项目公开用户 issue。原始项目当前公开 release 仍是 v0.1.0；它不能证明 v0.1.1 的运行结果。
- v0.1.1 tag 的 `Configuration.swift` 使用单一绝对路径，`CodexUsageFetcher.swift` 启动本地 `codex app-server --listen stdio://`，读取 `account/rateLimits/read`。这些发布版事实可在 [v0.1.1 Configuration.swift](https://github.com/TrevorLt/codex-usage-status/blob/v0.1.1/macos/CodexUsageStatus/Sources/CodexUsageStatus/App/Configuration.swift) 和 [v0.1.1 CodexUsageFetcher.swift](https://github.com/TrevorLt/codex-usage-status/blob/v0.1.1/macos/CodexUsageStatus/Sources/CodexUsageStatus/Codex/CodexUsageFetcher.swift) 核对。
- 当前工作树的未提交变更将候选位置扩展到 `/Applications` 和 `~/Applications` 下的 `Codex.app`、`ChatGPT.app`，并纳入四种 bundle 内候选路径；fetcher 也加入进程提前退出及部分错误分类。README、technical review 和诊断文档也有未提交的同步改动。该组改动尚未经过本研究验证，不应被视为 v0.1.1 已有能力或已发布修复。

本报告将“源码/文档直接可见”视为已验证事实；公开 issue 的用户复现标为“公开复现”，不等同于所有机器都会发生；对该下载者的根因不作确定归因。

## “问号”对应什么状态

在项目 [AppDelegate.swift](../macos/CodexUsageStatus/Sources/CodexUsageStatus/App/AppDelegate.swift) 中：

1. 最近一次成功值保存在进程内的 `lastUsage`；成功读取时更新，失败时不清除。
2. 已有成功值但刷新失败时，数字继续显示为最后已知读数并标陈旧，tooltip 包含上次成功读取时间与最近错误。
3. 没有成功值但存在 `lastError` 时，状态栏使用错误图标；tooltip 给出错误文本。菜单的 Settings 也显示最近错误、最近成功时间和下次刷新时间。
4. 没有成功值且尚无错误时显示等待首刷的 placeholder。
5. 重启会丢失内存中的 `lastUsage`。release notes 与 [wake/cache strategy](wake-cache-strategy.md) 说明刻意不持久化额度快照，原因是当前展示模型没有可用于验证账号归属的可靠身份字段；旧快照可能在用户切换账号后误显示。

因此，问号与“值很旧但仍成功返回”是两类问题：前者通常是没有成功响应或响应无法解析；后者可能继续显示数字，直到陈旧期限、额度 reset 或显式错误状态使其标 stale/unknown。`resetsAt` 是限额窗口边界，不是服务端样本生成时间，无法单独证明最新配额值何时产生。

## 失败场景逐项盘点

| 场景 | 可验证事实与可能表现 | 对 v0.1.1 的判断 | 建议的产品处理 |
|---|---|---|---|
| 找不到 Codex CLI | release 只尝试 `/Applications/Codex.app/Contents/Resources/codex`；不存在或不可执行就产生 `codexNotFound`，首刷后显示错误图标。`CODEX_BIN` 可覆盖路径，但由 GUI、Login Item 或 launchd 启动时，不应假设用户 shell 的 PATH/环境变量会自动带入。 | **高优先级、release 中确认存在的兼容缺口。** README 也把旧路径写成唯一要求。 | 先尊重显式 `CODEX_BIN`；否则发现 `com.openai.codex` bundle 并检查已知布局；错误区分“没装 app”“找到了 app 但没找到 CLI”“文件不可执行”。展示实际尝试位置及安装/设置指引。不要扫描或运行当前目录/相对 PATH 中任意同名文件。 |
| bundle 名称、安装目录或资源布局改变 | OpenAI CLI 的 macOS 源码会在 `/Applications`、`~/Applications` 搜索 `ChatGPT.app` 和 `Codex.app`，并用 `com.openai.codex` 验证 bundle。OpenAI issue 记录了 `ChatGPT.app/Contents/Resources/codex` 迁移到 `codex-cli/bin/codex`，以及旧 symlink 因更新变悬空的公开案例。CodexBar 文档同样列出当前与 legacy app 内的 CLI 入口。 | **公开事实，解释了为何单一路径脆弱。** 这些是观察到的布局，不是 OpenAI 对第三方承诺的稳定路径 API。 | LaunchServices bundle ID 查询可用于发现注册 app；再检查标准 Applications 目录与已知兼容布局。读取 `CFBundleIdentifier`，对 OpenAI bundle 做签名/身份验证；只选匹配当前 CPU 架构、真实存在且可执行的 launcher。每次 app 更新后按 inode/mtime 等文件元数据重新验证路径，不永久信任旧结果。 |
| Apple Silicon / Intel / Rosetta 不匹配 | release 分别提供 `arm64` 和 `x86_64` app；错误架构的 CLI 可能无法启动，即使文件路径存在。CodexBar 对已知 npm/package 布局按 host 架构选择 payload，不让另一架构的陈旧 payload 静默替代当前有效路径。 | **可能性明确；下载者的机器与所选 ZIP 未知。** 若主 app 本身已成功运行并显示菜单图标，整包架构不匹配的可能性较低；但内嵌/外部 CLI 仍可能不匹配。 | 在启动前记录 app 与 CLI 的架构/版本诊断；明确报出 `Bad CPU type`/架构不匹配与“找不到文件”。不要以存在的错误架构二进制作为成功候选。 |
| Gatekeeper、签名、quarantine、损坏或权限问题 | v0.1.1 是 ad-hoc signed、未 notarize；首次运行可能经系统确认。若 App 已经运行并显示状态栏图标，单纯“主 App 被 Gatekeeper 阻止”的可能性就低很多，但子 CLI 启动仍可能失败。Apple `Process` API 把子进程启动错误、终止状态和标准流暴露给调用者。 | **可发生，但“已安装后看到问号”不足以支持它是根因。** | 把 `Process.run()` 的系统错误、退出状态和超时分别呈现；指导用户使用正常 macOS 安全确认，不建议全局关闭 Gatekeeper 或删除 quarantine。仅在用户请求诊断时提示检查 CLI 的系统信任状态。 |
| CLI 未登录、Codex 登录态与外部 CLI 不一致 | CodexBar issue #1170 记录：本地 `codex app-server` 在未登录时对 `account/rateLimits/read` 返回 `codex account authentication required to read rate limits`。该案例还显示通用“暂时不可用”文案会让用户误以为是服务故障。独立安装的 CLI、Codex Desktop 的内置 CLI 和不同 `CODEX_HOME` 可能对应不同运行环境。 | **公开复现；v0.1.1 将 RPC `error` 压成通用错误并丢弃服务端消息，无法明确提示登录。** 本研究没有读取任何认证材料。 | 将已知认证必需错误映射为“请打开 Codex 完成登录后刷新”；不请求或打印凭证，不自行执行登录/续期。RPC 错误中的自由文本需 allowlist/脱敏，不能原样暴露任意 stderr。 |
| app-server 启动失败、提早退出或卡住 | v0.1.1 为请求等待最多 20 秒；进程终止信号只用于收尾，提早退出没有唤醒等待 RPC 响应的 semaphore，可能被误报为 timeout。枚举虽有 `appServerExited`，tag 代码没有实际抛出该错误的路径。 | **v0.1.1 源码确认的诊断缺口。** 当前工作树的未提交 diff 添加了终止回调唤醒，但尚未验证或发布。 | 子进程结束即唤醒请求等待，区分 exit code、signal、spawn error 与 timeout；超时后关闭 pipe、TERM 后限时等待，再 KILL 并回收；保证不会遗留子进程。测试空输出退出、非零退出、无响应、超量 stderr、正常响应等 fake child。 |
| app-server / JSON-RPC 不兼容 | 官方 Codex 仓库定义 `account/rateLimits/read` 和响应 schema；当前实现仍直接依赖本机 app-server 的 CLI/stdio 协议。初始化或 method 参数/响应字段未来变化可能导致 RPC error、无响应或 decode error。 | **真实兼容面；具体某个下载者是否遇到未知。** CLI RPC 是本地接口实现事实，不应宣传为第三方永久稳定 ABI。 | 对 initialize、请求与返回分阶段设有限时；解析稳定的 JSON-RPC id/error/result 字段；保留安全的错误类别，不把未知 schema 变成 100% 或 0%；提示更新 Codex 或监视器。协议通知可作为补充信号，仍保留低频读取用于恢复和校验。 |
| 5H 或 7D 字段缺失、schema 变化 | `UsageModels.swift` 要求找到约 300 分钟和 10080 分钟两个有效窗口；字段缺失、非法百分比、duration 不匹配就拒绝整个样本。OpenAI 官方 schema/issue 也展示了某些限额窗口可以是 null 或只出现一个窗口的 payload 情况。 | **模型校验是安全的，但 UI 错误信息应指出是窗口字段缺失，而非笼统失败。** | 单项窗口可缺失时，按产品约定选择“可用项 + unknown”，或明确拒绝整行；切勿把缺失值当 0 使用量/100% 剩余。日志使用错误码和字段名，不记录原始响应或账号数据。 |
| 网络离线、DNS、代理/VPN、服务端错误或 429 | app-server 负责查询远端 usage；NWPathMonitor 可报告系统可用网络路径的变化，但 `.satisfied` 不保证目标主机、DNS、TLS、登录或额度服务正常。CodexUsageStatus 在网络从不可达变为可达时请求恢复，常规错误重试为 300 秒。 | **多个故障会在 v0.1.1 落到 RPC error/timeout，用户不能从问号分辨。** 服务端 freshness 与本机 polling 是不同问题。 | 分类 offline / timeout / authentication / server error / rate limited / decode。network path 恢复只触发一次合并后的探测，真正成功才清除错误。若将来识别 429，尊重 `Retry-After`（若可用）并保留 last-good；不要把一般 300 秒轮询当作网络诊断。 |
| 睡眠、屏幕唤醒、应用重启 | 当前工作树/最近发布基线的 AppDelegate 已使用 willSleep/didWake/screensDidWake 与 NWPathMonitor，在唤醒时排程合并刷新；Apple 明确提供 `NSWorkspace.didWakeNotification`。睡眠期间 timer 不应被当作精确时钟。进程内 snapshot 在重启时消失，因此首个恢复请求失败会回到问号。 | **睡眠路径已有设计；重启后的无缓存是有意行为。** 不能仅根据 release notes 证明每种硬件/网络状态下动态恢复成功。 | 保留唤醒后合并查询和单飞保护；设置网络事件去抖与最小间隔。重启首刷失败时明确展示错误和“无本次运行成功值”，避免只留图形符号。磁盘缓存只有在能核实账号/窗口身份、时间、过期和原子写入后才值得考虑；否则错误账号的旧额度比空状态更误导。 |
| 来源返回成功但额度落后 | 监视器成功收到并解析数据，不等于服务端刚生成了该数据。响应的 `resetsAt` 不是数据采样时间。公开 Codex issue 也有 Dashboard/Usage 页面与 app-server 值的延迟/不一致报告。 | **可能性存在，但一般表现为旧百分比而非问号。** 对当前观察到的问号解释力弱。 | UI 显示“本机最后读取时间”，不要把它称为服务端更新时间；如果来源没有生成时间，source lag 标为未知。发生成功但内容不变时不把它误报成新额度。 |
| 菜单栏空间、隐藏或第三方状态栏管理器 | macOS 可以折叠/隐藏 menu extras，竞争软件也可能改变位置。 | **可解释“看不见图标”，不能解释图标本身显示问号。** | 对问号排查优先看 Fetcher Settings 错误；仅在完全找不到图标时再查菜单栏布局。 |

## 竞品公开做法

| 项目 | 公开源码/文档中可确认的做法 | 适用于本项目的启示 | 不宜直接照搬的部分 |
|---|---|---|---|
| [steipete/CodexBar](https://github.com/steipete/CodexBar) | 支持当前 ChatGPT.app 与旧 Codex.app 的 bundled CLI；识别 `codex-cli/bin/codex` 与 legacy launcher，按架构选择，避免 current/relative PATH 随意执行，并为 RPC 设有有界超时、TERM/KILL 回收。Issue #1170 暴露过“未登录被映射成暂时不可用”的诊断缺口；release 后续改进 last-known 保留和原采样时间。 | 学习可验证路径发现、单独的认证错误、进程快速退出/有界清理、错误时保留带时间的 last-good。CodexBar 自己的 issue 表明竞品也会出现抽象错误文案，必须让已知错误能直达用户。 | CodexBar 是多 provider 产品，支持 OAuth/Web 等额外数据源；这会引入 credential/cookie 处理面，不符合本项目只用本机 app-server、不读认证材料的约束。其复杂 trust/cache 实现不应原样移植到小型单用途应用。 |
| [ClaudeWatch](https://github.com/elliotykim/claudewatch) | Claude Code statusline hook 把使用量写入本地 JSON；菜单栏读取该文件而不是自行轮询 usage API。README 明确说明：没有新的终端 session/statusline 更新时数据会变 stale。服务状态另读官方 status API。 | 事件/本地文件可以降低 quota endpoint 轮询，但数据会受 CLI session 是否活动影响；必须明确 stale 和最后更新时刻。 | Codex 当前没有等价、稳定且总会运行的 quota hook 可供该方案直接替代；一个只在活跃终端更新的缓存无法解决 Desktop-only 用户的额度新鲜度。 |
| [ClaudeBar](https://github.com/nerlichman/claudebar) | README 说明以 OAuth usage endpoint 定时查询，并以 statusline 捕获的 rate-limit 信息为本地 fallback；两路按新鲜度选值，fallback 在没有终端交互时可能变 stale。 | 多来源时需要标明 provenance、采样时间与各自失效规则，不应把 poll 时间伪装成数据源更新时间。 | 主路径管理 OAuth token，超出本项目的隐私/安全边界。只借鉴状态与来源标注，不借鉴凭证读取。 |
| [UsageBar](https://github.com/vineellabs/usagebar) | README 描述启动、唤醒、每五分钟及菜单打开且数据 stale 时更新；遇到 429 会暂停 10 分钟并保留 last-good，手动刷新可清除 backoff。 | 失败也应保留最后有效数字并标明年龄；唤醒/打开菜单可触发受去抖的恢复。对 429 应采取与普通网络错误不同的策略。 | 项目会读取 CLI 维护的 credentials；其 10 分钟值是该项目策略，不是通用最佳参数或 Codex 服务保证。 |

这些 README/源码是产品实现证据，不是统一行业标准，也没有公开、可比的耗电 benchmark。竞品的 refresh 秒数不能直接推导为更省电或更实时。

## 推荐的发现与错误状态设计

### 可执行文件发现

1. **显式配置优先。** 若用户明确设置 `CODEX_BIN`，先验证路径存在、可执行并可启动；路径失效时指出这一明确配置，不要静默改用另一个账号/环境的 CLI。
2. **按 bundle ID 找应用。** 可用 `NSWorkspace.urlForApplication(withBundleIdentifier: "com.openai.codex")` 找系统注册的默认 app；同时探测 `/Applications` 与 `~/Applications` 下的 Codex.app / ChatGPT.app，覆盖多个 bundle 副本。OpenAI 自己的 macOS app locator 也会搜索这两个目录和名字，并验证 bundle ID。
3. **识别少量、版本化的已知布局。** 至少覆盖已观察到的 `Contents/Resources/codex`、`Contents/Resources/codex-cli/bin/codex`、`Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`。在 README 写“已观察到/支持的布局”，不要声称 Apple 或 OpenAI 保证路径长期不变。
4. **验证后选一个。** 检查 app bundle ID、签名团队、可执行权限和目标架构；使用短超时的版本/能力探测后才启动 RPC。未验证的同名 PATH 二进制不能无条件优先。
5. **路径缓存需可失效。** 进程内可缓存已验证路径，但 app bundle 更新、文件属性变化或启动错误时重新发现。错误中只列安全的候选路径，不输出环境变量全集、命令行中的敏感内容或进程环境。

Apple 的 `NSWorkspace.urlForApplication(withBundleIdentifier:)` 会返回指定 bundle ID 的默认 app，且当多个 app 有相同 ID 时使用启发式选择；它不是遍历所有副本的保证。因此，LaunchServices 查询最好与有限的标准目录候选合用。

### 错误分类和界面

建议菜单状态至少区分：`正在读取`、`已更新`、`最后成功读数（陈旧）`、`未登录`、`找不到 Codex/CLI`、`CLI 无法启动/架构不兼容`、`app-server 提前退出`、`超时`、`网络或服务暂不可用`、`不支持的响应格式`。每类保留最近成功时间、最近尝试时间和下次重试时间；用户主动 Refresh 可触发一次有界的立即尝试。

状态栏用问号/错误色只作为提示符；点击菜单应直接看到短的可行动原因。Tooltip、VoiceOver label 和 Settings 错误文字保持一致。保留 last-good 时附上“最后读取于…/陈旧”，不要在错误发生时清除值，也不要把失败伪装为 0%、100% 或“刚更新”。底层 app-server 文本只可经白名单映射；未识别错误显示类别和安全摘要，不输出原始 JSON、stderr 或任何认证内容。

### 缓存、唤醒与网络恢复

- 当前只在进程内保存 last-good，避免重启后把另一账号/旧窗口数据显示成当前值；这是合理的安全默认。
- 如以后要持久化，只能写额度数据、采样时间、schema 版本、reset deadline 和可验证的 account/window scope；原子替换、校验、过期，并在账号 scope 不明时拒绝展示。不要写 auth/token/cookie，也不要将任意 `auth.json` 内容作为缓存身份。
- 设备唤醒和路径恢复应合并为单次请求，维持单飞与最小自动间隔；NWPathMonitor 的“有可用路径”只触发重试，不等价于 Codex 服务成功。
- 一个真正由 app-server 发出的 rate-limit update 通知可以降低常态轮询延迟，但不应取代低频 reconciliation：进程可能重启、通知可能稀疏、客户端未在线时不会收到历史事件。官方协议源码需持续核对兼容性。

## 对这位下载者的判断与最小无敏感诊断

当前最有根据的排序是：

1. **路径/CLI 布局不匹配：首要候选。** 下载的 v0.1.1 只找 Codex.app 旧路径，而公开的 ChatGPT.app CLI 布局不同。
2. **app-server 登录态或运行环境不一致：次要候选。** 未登录是已公开复现的真实失败模式，v0.1.1 没有用户友好的错误细分。
3. **子进程快速退出、协议/schema 不匹配或本机网络失败：仍可能。** v0.1.1 的 timeout/error 文案不足以从图标区分。
4. **主应用 Gatekeeper/整个 app 架构错误：相对较低。** 若菜单图标已出现，主 app 至少已启动；这不能排除内嵌 CLI 的架构/信任问题。

要把根因定到一个 case，只需让用户在图标菜单中打开 `Settings...`，提供其中 `Last refresh failed` 的错误句子、Codex Desktop 的 About 版本、Mac 是 Apple Silicon 还是 Intel、以及 Codex.app/ChatGPT.app 的安装名/位置。无需截图账号、终端环境、日志全文或任何认证数据；不要索要/读取 auth 文件、cookie、token/API key。若 Settings 没有错误文字，应记录为 UI 可见性问题，而不是据问号猜路径。

## 尚未知项

- 下载者实际使用的 release ZIP 架构、Mac CPU、Codex Desktop 版本与 app bundle 路径。
- 该用户 Settings 中的真实 fetch error，以及对应 app-server 的安全错误类别/退出状态。
- 用户的 Codex CLI 是否已登录、GUI app 与子进程是否继承相同的非敏感环境配置；本研究未检查其本机认证状态。
- OpenAI 是否承诺任何 bundle 内 CLI 路径、`account/rateLimits/read` 的长期第三方兼容性或后端 freshness 上限。当前公开源码/issue 可证实实现细节和变化案例，不能替代稳定 API 保证。
- CodexBar/Claude 类竞品在同等机器和负载下的真实耗电、CPU、endpoint freshness 与总体成功率；公开资料没有统一基准。
- 当前工作树未提交路径 resolver 变更是否能覆盖所有现行 release 布局、签名/架构边界与环境差异；它尚未纳入 v0.1.1，也未由本研究运行测试。

## 来源

### OpenAI / Apple 第一方

- [OpenAI Codex CLI macOS app discovery source (`desktop_app/mac.rs`)](https://github.com/openai/codex/blob/main/codex-rs/cli/src/desktop_app/mac.rs) — app 名称、应用目录、bundle ID 和签名校验方式。
- [OpenAI issue #48214: macOS app update leaves bundled CLI symlinks dangling](https://github.com/openai/codex/issues/48214) — 2026-09 的 ChatGPT.app 路径布局迁移公开复现。
- [OpenAI issue #48481: bundled CLI path and app-server startup diagnostics](https://github.com/openai/codex/issues/48481) — 记录 `codex-cli/CodexCLI.app/Contents/MacOS/codex` 布局及 CLI 退出错误被映射为泛化 UI 错误的案例。
- [OpenAI app-server protocol definitions (`common.rs`)](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/common.rs) — `account/rateLimits/read` 方法定义。
- [OpenAI rate-limit schema (`account.rs`)](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/v2/account.rs) — rate-limit response 与可选/稀疏字段。
- [Apple `NSWorkspace.urlForApplication(withBundleIdentifier:)`](https://developer.apple.com/documentation/appkit/nsworkspace/urlforapplication%28withbundleidentifier%3A%29) — LaunchServices 默认应用查询语义。
- [Apple `NSWorkspace.didWakeNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification) — 设备唤醒通知。
- [Apple `NWPathMonitor`](https://developer.apple.com/documentation/network/nwpathmonitor) — 当前可用网络路径观察接口。
- [Apple `Process`](https://developer.apple.com/documentation/foundation/process) 与 [`terminationHandler`](https://developer.apple.com/documentation/foundation/process/terminationhandler) — 子进程执行、状态和终止回调。

### 本项目与竞品一手资料

- [本项目 v0.1.1 README](https://github.com/TrevorLt/codex-usage-status/blob/v0.1.1/README.md)、[release notes](https://github.com/TrevorLt/codex-usage-status/blob/v0.1.1/docs/release-notes-v0.1.1.md)、[GitHub Release](https://github.com/TrevorLt/codex-usage-status/releases/tag/v0.1.1)、[Issues](https://github.com/TrevorLt/codex-usage-status/issues)。本地源码：[Configuration.swift](../macos/CodexUsageStatus/Sources/CodexUsageStatus/App/Configuration.swift)、[CodexUsageFetcher.swift](../macos/CodexUsageStatus/Sources/CodexUsageStatus/Codex/CodexUsageFetcher.swift)、[AppDelegate.swift](../macos/CodexUsageStatus/Sources/CodexUsageStatus/App/AppDelegate.swift)、[UsageModels.swift](../macos/CodexUsageStatus/Sources/CodexUsageStatus/Domain/UsageModels.swift)、[wake/cache strategy](wake-cache-strategy.md)。
- [CodexBar Codex provider documentation](https://github.com/steipete/CodexBar/blob/main/docs/codex.md)、[refresh-loop design](https://github.com/steipete/CodexBar/blob/main/docs/refresh-loop.md)、[issue #1170: logged-out Codex CLI guidance](https://github.com/steipete/CodexBar/issues/1170)、[releases](https://github.com/steipete/CodexBar/releases)。
- [ClaudeWatch README](https://github.com/elliotykim/claudewatch) — statusline 文件来源与 stale 条件。
- [ClaudeBar README](https://github.com/nerlichman/claudebar) — API polling、statusline fallback 与 freshness 说明。
- [UsageBar README](https://github.com/vineellabs/usagebar) — wake/menu-open refresh、429 backoff、last-good 与其 credential 模型。

外部链接和 issue 内容核对于 2026-10-15；竞品 `main` 分支及 release 页面会继续变化，后续引用应保留 commit/tag 或复核日期。

## 后续本地实现验证

研究完成后，当前工作树已把首要建议落地为独立的路径解析器和安全错误分类。以下验证已通过：

- `bash scripts/test-codex-path-resolution.sh`
- `bash scripts/test-fetcher-lifecycle.sh`
- `npm test`
- `bash scripts/test-wake-recovery.sh`
- `node branding/verify-logo.mjs`
- `npm run package:macos:all`，并对 arm64/x86_64 ZIP 做 SHA-256 与严格代码签名验证

当前尚未推送或发布 v0.1.2；这些本地改动需要在发布前再完成一次完整审查。
