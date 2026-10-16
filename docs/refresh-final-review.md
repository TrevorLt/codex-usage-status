# Logo 与刷新研究最终交叉审查

> 历史交叉审查快照（2026-10-15）。本文件记录审查当时的边界；后续已将刷新/唤醒实现和 1B-M 图标接入 app bundle。当前状态以 [README](../README.md)、[technical review](technical-review.md) 和 [wake/cache 实施记录](wake-cache-strategy.md) 为准。

审查日期：2026-10-15（America/Chicago）。范围：审查四个 worker 产物及主方案、离线回放；本审查仅写入本文件。

结论：本轮 logo 修复与研究任务可以交付。默认 30/60/120 秒、300 秒单列 eco 实验，是有明确取舍的后续实现候选；尚无实机能耗或端到端验证支持直接上线或宣称全面更优。下列文档精度问题应随整合修正，不需要扩展本轮实现或新增实验才能完成研究交付。

## 审查输入与证据边界

- [Logo 说明](../branding/README.md)、[验证指标](../branding/validation/metrics.json)及验证脚本。
- [当前实现审计](refresh-current-audit.md)。此前审查已读相关实现；本次交叉核对报告的参数、生命周期、测试与安装来源边界。
- [论文与平台研究](refresh-scheduling-research.md)。论文题名、作者及摘要复核由主 agent 完成；本审查未将摘要核对扩大成所有全文结论均获独立复现。
- [竞品源码研究](refresh-products-research.md)。本审查另行通过 GitHub 官方 API 核实四个外部项目的完整提交 SHA 与日期，并读取相应固定提交 raw 源码；主 agent 亦独立抽查。
- [优化设计稿](refresh-optimization-plan.md)、[评估说明](refresh-evaluation/README.md)、`refresh-evaluation/replay.mjs`。本审查读到新增 `--cap120` 实现与独立结果表；本次未重新运行回放。

主 agent 已独立运行完整 logo 验证、四个 SVG 的 XML 校验，并目视检查并排及小尺寸图；这些执行结果与落盘指标相符。审计 worker 的 Swift harness 两个 case 已由接手 worker 重新编译验证；这不等同于完整 XCTest、Fetcher 集成或运行程序验证。

## 1. Logo：可交付，精确说明还原范围

原错误是构形错误，而非仅颜色或抗锯齿差异：目标外环由左侧长弧、右上短弧、右下弧三部分组成，内环开口在右上；原 SVG 的 dash 圆环未还原这套布局。

修正版采用参考图轮廓描摹，四个闭合轮廓存于一个真实 SVG path 的四个子路径中；保留参考图的轻微曲率和线宽不规则性。它是以还原为优先的矢量轮廓，不应再称为由少数理想同心圆弧精确拟合。

| 验证项 | 已记录证据 | 可以支持的结论 |
|---|---|---|
| 1254×1254 原尺寸、白底、亮度阈值 `<128` | 参考和修正版前景均 312,645 像素；mask 差异 0；IoU 1.0 | 在指定渲染与阈值下，二值轮廓完全一致 |
| 256×256 归一化比较 | silhouette IoU 0.997682；差异/并集约 0.232%；归一灰度 MAE 0.007999 | 缩放后轮廓高度吻合，存在重采样、边缘及灰度差异 |
| 四个变体 | 几何一致；template/dark/light alpha 一致；无嵌入位图 | 颜色变体没有各自偏移或变形 |
| 参考和旧基线 | 已放入 `branding/reference/` | 默认复核不再依赖临时目录中的旧截图 |

不得把原尺寸二值轮廓一致扩大为 RGB 像素完全一致：原图有软阴影与抗锯齿，矢量使用平涂。也不应把 0.232% 的轮廓差异全部归因于抗锯齿，当前指标没有单独分解误差来源。

验证脚本使用本机 Codex bundled runtime 内的 Sharp 绝对路径。这是复核工具的可移植性限制，不是 app 新增依赖；换机器运行需提供可用 Sharp 路径。当时的运行 app 尚未接入这些品牌资产；后续构建已将 `CodexUsageStatus.icns` 接入 bundle。

## 2. 四个竞品：固定提交与主要 cadence 获源码支持

以下 SHA 和日期由本审查直接查询官方 GitHub API 核实，读取的源码也固定到同一提交，而非浮动 main。上游项目与本地分支分别处理，四个外部项目并未用本地分支凑数。

| 项目与完整 SHA | 直接核查的实现 | 结论 |
|---|---|---|
| CodexBar `d846ceb47f3151df6caa88cd9aa61b17cb7185aa`，2026-10-16 01:49:22 UTC | [策略核心](https://github.com/steipete/CodexBar/blob/d846ceb47f3151df6caa88cd9aa61b17cb7185aa/Sources/AdaptiveRefreshCore/AdaptiveRefreshPolicyCore.swift)、[决策记录](https://github.com/steipete/CodexBar/blob/d846ceb47f3151df6caa88cd9aa61b17cb7185aa/docs/predictive-refresh-policy.md) | provider batch 为 2/5/15/30 分钟；低电量或受约束热状态优先采用 30 分钟；近期 coding activity 只能把较慢决策压至 5 分钟。决策记录支持 fresh-install plain Adaptive 与旧安装缺失设置时 legacy 5 分钟的区别。30 秒活动扫描不是 30 秒 quota 请求。 |
| tollenceld/codex-usage-status `d8438da30833eadb660cb35d632d6da665a6ba23`，2026-05-26 15:52:41 UTC | [Configuration](https://github.com/tollenceld/codex-usage-status/blob/d8438da30833eadb660cb35d632d6da665a6ba23/macos/CodexUsageStatus/Sources/CodexUsageStatus/App/Configuration.swift)、[AppDelegate](https://github.com/tollenceld/codex-usage-status/blob/d8438da30833eadb660cb35d632d6da665a6ba23/macos/CodexUsageStatus/Sources/CodexUsageStatus/App/AppDelegate.swift) | 下限 60 秒、默认 120 秒、失败 300 秒；成功后使用固定配置周期，不是本地新增的自适应策略。 |
| Bread-bang/claude-usage `25b30ddf8e27bf4b3be9c6368e0879e6ea68bfa5`，2026-10-13 10:46:40 UTC | [UsageViewModel](https://github.com/Bread-bang/claude-usage/blob/25b30ddf8e27bf4b3be9c6368e0879e6ea68bfa5/Sources/ClaudeUsageMiniBar/ViewModel/UsageViewModel.swift) | 默认 60 秒；无 report 时下一轮 15 秒；已有 report 且 rateLimited 时等待配置周期的两倍。`refreshNow()` 另起 Task，而 `load()` 未以 isRefreshing guard 拒绝重叠，报告指出的手动/轮询竞争成立。存储值边界有一处误述，见下节。 |
| exelban/Stats `4ecf4f736056eb488c75aa2fa62e749abd87c4a4`，2026-10-15 14:39:46 UTC | [Reader](https://github.com/exelban/Stats/blob/4ecf4f736056eb488c75aa2fa62e749abd87c4a4/Kit/module/reader.swift)、[Repeater](https://github.com/exelban/Stats/blob/4ecf4f736056eb488c75aa2fa62e749abd87c4a4/Kit/plugins/Repeater.swift) | Reader 基类默认 1 秒；Repeater 的 Dispatch timer leeway 为 200 ms。它是本机采样机制，不能当作远端额度接口允许高频查询的证据。 |

产品报告具备具体提交、实现差异及 Unknown 项，不是泛泛罗列产品。常驻进程是否更省、额度通知是否跨会话/设备覆盖，仍没有从这些策略文件获得足够证据；报告保留 Unknown 合理。对“未见 sleep/wake、统一 429”之类否定结论，应保持“在所查路径中”的范围限定。

## 3. 当前实现：优先修数据与生命周期，再调度

审计与主方案对主要问题已经对齐：

1. 当前只比较相邻、取整后的剩余额度；持续小幅下降不会更新显著下降时间，故可能持续 120 秒或在一次突发后回退至 240/300 秒。harness 验证了指定序列，不能将这些合成时间当作真实请求耗时。
2. `usedPercent=nil` 被解释为 100% remaining，以及单个 weekly 窗口可能同时成为 5H/7D，都会污染变化判断。样本有效性应先于变化率和静默计时。
3. child 无有效响应即提前退出时，响应等待仍可能耗满 20 秒；退出和响应需要协同处理，再做 one-shot/persistent 成本比较。
4. `base=600` 导致 effective maximum=600，是已确认行为，但是否构成缺陷取决于环境覆盖契约；不能仅凭常量名判错。
5. 在该审查时，安装二进制与当前 HEAD 的构建来源尚未闭环。源码审计结果不能直接改写成“运行程序已证明如此”；后续安装验证已闭环这一点。

这些项目足以支持后续实现排序，不需要本轮为所有边界新增生产修复。

## 4. 回放与候选：120 cap 已模拟，保留成本与负例

`Candidate120Policy.success()` 仅对同一候选的成功返回值施加 `min(120, ...)`，继承失败策略；适合隔离 idle cap 这一变量。它没有实现主方案的 raw precision、窗口身份、分类错误及系统事件，不能称为完整首发实现已验证。

| 合成场景 | current | cap120 候选 | 可用解释 |
|---|---|---|---|
| 空闲首小时 | 30 次 | 35 次 | 候选启动 warm-up 增加请求；不能称默认方案降低所有空闲成本 |
| 每分钟下降 1 点 | 30 次、下一成功读取 P95 103 秒 | 120 次、P95 13 秒 | 指定相位下更快，代价为更多请求；current 末尾有 2 个截断变化，候选 0 个 |
| 指定充分空闲后突发 | current 最大 119 秒 | cap300 最大 299 秒；cap120 最大 119 秒 | cap120 收回该轨迹的 300 秒盲区；不是对所有相位及实机的 119 秒保证 |
| 暂时失败 | 最大 403 秒 | 最大 433 秒 | 指变化到下一成功读取，包含故障期间等待；不是网络恢复后的等待，也不是候选全面占优 |

README 现在分别列出 cap300、cap120 与截断数，主方案也没有混用它们。相位扫描、尾随观察、请求耗时和能耗实测仍是上线评估建议，不应阻碍本轮研究交付；现有结果应保持“特定合成轨迹示例”的定位。

默认候选为成功状态 30/60/120 秒；300 秒 idle、5–10 秒 boost、常驻 app-server 均单列实验。失败、低电量和设备睡眠是独立状态，不能拿健康 idle cap 给所有失败恢复延迟作上界。

## 5. 审查发现与整合修正

下列条目是审查时发现的必要表述修正。本审查按 scope 只记录，不编辑其他文件；后续整合完成情况见本节末尾。

1. **Claude 存储值不是钳制到 30 秒。** 产品报告写“存储值下限钳制为 30 秒”，但 `storedRefreshInterval()` 实际为 `stored >= 30 ? stored : 60`：有效存储值至少 30 秒；小于 30 秒或未设置时回退 60 秒。主 cadence 与失败机制结论不受此修正影响。
2. **tolerance 不是所有系统状态下的最大延迟保证。** 学术稿延迟模型的 `T+J` 应限定为没有额外调度阻塞的理想模型。Apple 明确说明 Timer 不是实时机制，run-loop 长调用或模式不匹配能使触发明显晚于计划。当前又是从完成时重排 timer，不能把名义间隔直接当作固定采样周期；参考 [Apple Timer](https://developer.apple.com/documentation/foundation/timer)。本审查经 Apple 官方 Markdown 页面复核了这项限制。
3. **回放的 displayed error 不等于故障时实际屏幕误差。** 回放保留上一成功数值，审计指出当前 UI 会用 error badge 覆盖数值。应解释为“模型保留的最后成功快照对已发布值的误差”，而非当前真实 app 错误画面的重演。下一成功采样延迟指标不因此失效。
4. **检测成功不得包含请求发起或错误展示。** 审计实验计划的 `ground_truth_change → refresh admitted` 应叫尝试启动延迟；`→ error applied` 应叫错误反馈延迟。有效变化首次被成功快照应用，才属于成功发现/可见延迟。真实数据源公开时刻未知时继续采用区间或 Unknown。
5. **量化与配置边界应保持准确。** 小于 1 点的真实变化“可能被隐藏”，而非必然不可见：跨越 rounding 边界时仍可使整数变化。学术稿“最大 300 秒”应限定默认 base 配置，与审计的环境覆盖例外一致。
6. **学术稿末尾的交叉评审已经过时。** 它仍称主方案默认 300 秒，与当前主方案明确的 120 秒默认 cap、300 秒 eco 行不符；应改为“该分歧已在主方案解决”，避免最终材料互相指责一个已经修正的问题。

论文/Scholar 边界已改善：Scholar 链接保留为检索入口，本轮无法独立访问其结果，不应宣称本轮已完成 Scholar 检索验证。可交付的证据来自已经核对的 arXiv/出版方资料，具体 30/60/120 秒参数属于工程候选，不能借论文宣称最优或给出 Mac 节电百分比。

整合完成记录（主 agent，2026-10-15）：以上六项均已落实到对应报告。产品稿已改为低存储值回退 60 秒；学术稿已限定理想延迟模型并补充系统调度延迟、量化边界和默认配置例外；评估说明已区分模型 last-good 误差与真实错误画面；审计已分开尝试启动、成功发现和错误反馈延迟；学术稿末尾已与 120 秒默认 cap 和独立 `--cap120` 结果对齐。均为文档整合，未改变生产代码或回放算法。

## 6. 可供用户的总结

Logo 已按选定 1B-M 原图修正：外环三段、内环开口和留白恢复；原尺寸的指定阈值轮廓完全吻合，缩小后约 99.768% 吻合，四种矢量版本一致。该审查时 app 尚未替换图标；当前构建已将它打包为 `CodexUsageStatus.icns`。

研究确认了一个可改进的原因：现有刷新只对单次至少 5 个整数百分点的下降提速，持续小幅消耗反而可能保持慢刷。建议首版改成“任何有效消耗延续活跃”，按 30/60/120 秒退阶，并优先修正无效快照和 child 提前退出的错误等待。所有自动触发统一去重并遵守最短间隔及可获得的限流期限。

120 秒封顶候选已有独立离线回放：持续小幅消耗的指定轨迹更新更快，但请求从每小时 30 次增至 120 次；空闲首小时也从 30 次增至 35 次。300 秒 eco 会加长首次发现盲区，指数重试存在更慢反例，因此未将其写成全面胜出。常驻进程、额度事件及 5–10 秒短促加速留待有真实数据新鲜度和资源测量后决定。

本轮完成的是 logo 修复、四项目源码调研、论文/macOS 研究和可审阅优化方案；没有修改运行算法、安装依赖或推送发布。后续可以据此实施并验证，不需要把研究交付误写成正式上线已经完成。
