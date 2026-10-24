# 高质量开源项目 README 的权威写作指南

> 研究日期：2026-10-18
> 适用对象：GitHub 上需要被真实用户安装、使用、构建、测试或贡献的开源项目
> 研究范围：优先采用 GitHub 官方文档、GitHub 维护的 Open Source Guides、标准版本/变更记录规范；本文件中的仓库特定检查项以当前 `codex-usage-status` 工作副本为准。

## 结论先行

README 是项目首页的“最短可行路径”，不是完整手册，也不是发布日志的替代品。首屏应让陌生读者快速回答：项目做什么、为什么有用、如何开始、哪里求助；随后给出一条可复制的安装/使用路径，并把构建、测试、安全、贡献、发布等深层信息链接到维护更合适的文件。这个信息模型直接来自 [GitHub 的 README 说明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes) 和 GitHub 维护的 [Starting an Open Source Project](https://github.com/github/opensource.guide/blob/main/_articles/starting-a-project.md)。

高质量 README 的判断标准不是“章节越多越专业”，而是：

1. 读者在几分钟内能完成一次成功的安装或最小使用。
2. 每条命令、版本、路径、截图和状态徽章都能追溯到当前项目，且没有把未验证的能力写成承诺。
3. README 负责导航和首条成功路径；详细架构、诊断、贡献流程、安全政策和发布流程放到专门文档，并保持链接有效。
4. 读者知道项目的支持范围、已知限制、求助入口和贡献入口，而不是只能靠猜。

### 关于“权威模板”的边界

GitHub 的官方材料提供的是内容职责、社区健康文件机制和 Markdown 能力，而不是一份适用于所有语言和产品的强制 README 模板；GitHub 维护的 Open Source Guides 也把 README 写作表述为应回答一组用户问题，并允许项目补充贡献、目标、许可和归属信息：[Starting an Open Source Project](https://github.com/github/opensource.guide/blob/main/_articles/starting-a-project.md)。因此，本文件把官方问题集合转化为可执行的信息架构，不把第三方“万能模板”的章节列表当成规范。

## 一、README 信息架构

下面是建议的默认顺序。不是每个项目都必须有每一节；如果一节没有真实内容，应省略或明确写“暂不支持”，不要填充模板化文案。GitHub 会从标题自动生成文档大纲，并建议在 README 中使用仓库内的相对链接；README 超过 500 KiB 时，GitHub 页面会截断内容。依据：[About the repository README file](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)。

| 顺序 | 章节 | 应回答的问题 | 写作边界与依据 |
| --- | --- | --- | --- |
| 1 | 标题 + 一句话定位 | 这是什么，给谁用，解决什么问题？ | 用项目名和可验证的一句话描述，不先写历史或内部实现。GitHub 要求 README 说明项目做什么、为什么有用：[About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)。 |
| 2 | 首屏信号 | 项目现在是否可用、适用于什么环境？ | 可放少量有意义的 CI/发布/许可证徽章；徽章必须链接到其事实来源。工作流状态徽章的语义和生成方法见 [Adding a workflow status badge](https://docs.github.com/en/actions/how-tos/monitor-workflows/add-a-status-badge)。 |
| 3 | Demo 或截图 | 用户运行后看到什么？ | 只有视觉结果本身能降低理解成本时才放；为图片写等价的 alt text，使用仓库内相对路径。依据：[GitHub 图片与 alt text 语法](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)。 |
| 4 | 功能/适用范围 | 能做什么，不能做什么？ | 只列当前实现和已验证的行为；把“不支持/已知限制”放在用户会做决定的位置。GitHub 维护的 Open Source Guides 强调 README 还要解释项目为什么重要、用户能做什么：[Writing a README](https://github.com/github/opensource.guide/blob/main/_articles/starting-a-project.md)。 |
| 5 | Requirements | 支持哪些操作系统、运行时、工具和版本？ | 列出硬性前置条件、架构差异、账号/权限要求；不要把 CI 使用的环境误写成所有用户都必须安装的环境。有关项目文档应让读者知道如何开始，见 [GitHub README guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)。 |
| 6 | Installation | 如何最快得到一个可运行版本？ | 默认先写发布版安装，再写源码安装；命令应可复制，注明成功后的可见结果和常见失败原因。GitHub 的官方 README 示例要求 README 说明用户如何开始：[About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)。 |
| 7 | Quick start / Usage | 第一次运行的最短端到端路径是什么？ | 给一个最小成功示例，再给常用配置、参数和退出/错误解释；不要只列 API 名称。GitHub 维护的 Open Source Guides 明确把“如何开始”列为 README 必答问题：[Starting an Open Source Project](https://github.com/github/opensource.guide/blob/main/_articles/starting-a-project.md)。 |
| 8 | Build / Test | 贡献者如何从源码构建并证明改动没有破坏项目？ | 分开构建、单元测试、集成测试、平台/GUI 前置条件和已知未覆盖项；命令必须与 CI 或脚本一致。GitHub 的开源指南建议贡献文档说明如何设置环境和运行测试：[Writing your contributing guidelines](https://github.com/github/opensource.guide/blob/main/_articles/starting-a-project.md)。 |
| 9 | Security / Privacy | 项目接触什么数据，如何报告漏洞？ | README 给出简明安全边界并链接 `SECURITY.md`；不要在 README 示例中放真实凭据、cookie、token 或隐私数据。GitHub 要求安全政策说明受支持版本和漏洞报告方式：[Adding a security policy](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/add-security-policy)。 |
| 10 | Support / Troubleshooting | 遇到问题去哪里，先检查什么？ | 链接诊断文档、Issue/Discussion 模板或支持渠道；把高概率错误和修复动作写在用户遇到它的地方。GitHub 将“哪里求助”列为 README 的典型内容：[About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)。 |
| 11 | Contributing | 想贡献代码、文档或 issue，第一步是什么？ | README 只保留入口和最短流程，完整约束放 `CONTRIBUTING.md`；明确欢迎的贡献类型、开发环境、测试命令和 PR 要求。GitHub 会在 issue/PR 和仓库侧栏暴露 `CONTRIBUTING.md`：[Setting guidelines for repository contributors](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/setting-guidelines-for-repository-contributors)。 |
| 12 | Releases / Versioning / License | 用户如何找到稳定版本、变更和许可？ | 链接 Releases、版本说明、校验和及许可证；说明版本方案。GitHub Releases 用 tag 标记代码历史中的具体点，并可附 release notes 和二进制文件：[About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)。 |

### README 与其他文件的分工

GitHub 维护的 Open Source Guides 把 `README`、`CONTRIBUTING`、`CODE_OF_CONDUCT` 和 `LICENSE` 视为开源项目应有的基础文档，并说明把它们放在根目录可帮助 GitHub 自动识别和展示：[Starting an Open Source Project](https://github.com/github/opensource.guide/blob/main/_articles/starting-a-project.md)。因此建议采用以下分工：

- `README.md`：项目定位、首个成功路径、常见用户入口和重要限制。
- `CONTRIBUTING.md`：开发环境、测试、代码风格、issue/PR 流程和适合贡献的任务；GitHub 对其位置和展示方式有明确说明：[Setting guidelines for repository contributors](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/setting-guidelines-for-repository-contributors)。
- `SECURITY.md`：受支持版本、漏洞报告方式和披露边界；依据：[Adding a security policy](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/add-security-policy)。
- `CHANGELOG.md` 或 GitHub Releases：按版本记录面向用户的显著变化；[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) 建议每个版本一个条目、最新版本在前、按变更类型分组，并避免直接倾倒 git log。
- `docs/`：架构、诊断、设计决策、详细发布流程等需要长期维护但不应阻塞首次使用的内容。README 用仓库内相对链接导航；GitHub 对相对链接和图片路径的处理见 [About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)。

## 二、安装、使用、构建、测试、安全、贡献与版本发布

### 安装

安装段落应按用户目标排序：

1. **Release first**：给出稳定版本页、平台/架构选择、下载物、校验和或签名验证、安装动作和卸载/升级注意事项。
2. **Source second**：给出 clone、运行时版本、依赖安装、构建和启动命令。
3. **Post-install check**：告诉用户成功时应看到什么；如果首次运行需要登录、权限、环境变量或特定系统状态，应在命令前写出。
4. **Failure path**：至少覆盖找不到依赖、版本不支持、架构不匹配、权限/签名、网络或认证失败，并链接诊断文档。

这是对 GitHub “说明如何开始”要求的可执行化解释；每条安装命令都应能在当前项目的脚本、CI 或发布流程中找到事实依据：[About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)；发布文件和二进制的官方语义见 [Releasing projects on GitHub](https://docs.github.com/en/repositories/releasing-projects-on-github)。

### 使用

Usage 应包含一条“最小可成功”路径，而不是把所有选项平铺出来：

- 先给可复制命令或最小代码片段，再解释结果；GitHub 支持代码块和 Markdown 格式，语法依据：[Basic writing and formatting syntax](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)。
- 明确默认行为、可选配置、环境变量、输入输出和退出码；敏感变量只展示占位符，不展示真实值。
- 把“不支持什么”写出来，尤其是权限、平台、网络、账号和数据边界；这比一个笼统的“安全”徽章更能减少误用。
- 将 FAQ/诊断按用户观察到的症状组织，例如“没有输出”“找不到可执行文件”“架构不匹配”，而不是按内部类名组织；“哪里获得帮助”是 GitHub README 的典型职责：[About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)。

### 构建与测试

README 中的构建/测试信息应让贡献者回答：我需要什么环境、运行什么命令、什么结果算通过、哪些检查只能在特定机器上完成。建议：

- 把 `build`、`test`、`lint`、`integration`、`package` 分成独立命令，并说明它们的成本和前置条件。
- 说明“退出码为 0”是否足够；如果项目使用 PASS marker、快照、人工确认或 GUI 会话，应写明判定标准。
- 对跨平台或多架构项目列出矩阵，不把单一开发机上的成功泛化为所有平台已验证。
- 让 README 命令与 `package.json`、CI workflow、`CONTRIBUTING.md` 和发布检查清单保持一致；GitHub 的开源指南建议贡献文档覆盖环境设置和测试：[Writing your contributing guidelines](https://github.com/github/opensource.guide/blob/main/_articles/starting-a-project.md)。

### 安全与隐私

安全段落不是“项目安全”的营销口号，应是可审计的边界声明：

- 说明项目读取、写入、发送和持久化哪些数据，以及明确不处理哪些敏感数据。
- 指向 `SECURITY.md`，其中写明受支持版本和漏洞报告渠道；这是 GitHub 官方安全政策页面要求的最低信息：[Adding a security policy](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/add-security-policy)。
- 不把“使用官方 API”“没有已知漏洞”“安全”“隐私友好”写成互相等价的结论；每一项都应有具体边界或验证证据。
- 发布二进制时说明签名、notarization、校验和、权限和已知系统警告；如果尚未做到，应写成限制而不是暗示已完成。GitHub Releases 支持附二进制和 release notes，但不替代项目自身的安全说明：[About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)。

### 贡献

README 的贡献入口应短而明确：链接 `CONTRIBUTING.md`、说明 issue/PR 的用途、列出最小检查命令，并注明哪些贡献不在项目范围内。完整指南至少应说明如何报告 bug、提出功能、设置环境和运行测试；这是 GitHub 维护的 Open Source Guides 对 `CONTRIBUTING` 的明确建议：[Writing your contributing guidelines](https://github.com/github/opensource.guide/blob/main/_articles/starting-a-project.md)。GitHub 还会在贡献者创建 issue 或 PR 时显示贡献指南链接：[Setting guidelines for repository contributors](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/setting-guidelines-for-repository-contributors)。

### 版本与发布

- 如果项目有公开 API、CLI 行为或用户可安装的二进制，采用并声明 [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html)：兼容 bug fix 增加 PATCH，向后兼容功能增加 MINOR，不兼容变更增加 MAJOR；预发布和 build metadata 使用规范定义的格式。
- 已发布版本不可原地修改；SemVer 明确要求任何修改都通过新版本发布：[Semantic Versioning 2.0.0，规范第 3 条](https://semver.org/spec/v2.0.0.html#spec-item-3)。
- Release notes 面向用户写“新增/变更/弃用/移除/修复/安全”，不要直接复制 commit log；依据：[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/)。
- GitHub Release 应绑定明确 tag，附适用平台的二进制、校验和、已知限制和升级说明；GitHub 说明 release 是用来打包软件、release notes 和二进制文件的：[Releasing projects on GitHub](https://docs.github.com/en/repositories/releasing-projects-on-github)。

## 三、徽章和截图的适用边界

### 徽章：信号，不是装饰

适合放在 README 首屏的徽章通常只有三类：

1. **当前 CI 状态**：确实反映默认分支或明确分支上的测试/构建；使用 GitHub 生成的 workflow status badge，并链接到对应 workflow。官方说明徽章代表 workflow 当前通过或失败，并支持指定 branch/event：[Adding a workflow status badge](https://docs.github.com/en/actions/how-tos/monitor-workflows/add-a-status-badge)。
2. **稳定发布/版本**：能让用户直接到 release/tag/包管理器选择版本；版本信息应和 tag 或发布页一致。GitHub release/tag 的关系见 [About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)。
3. **许可证或支持平台**：只有当它能帮助用户做安装/使用决策，并且目标 URL 是维护者可控制的事实来源时才放；项目许可证本身应以仓库中的 LICENSE 为准，GitHub 的开源项目指南说明许可证是开源项目的基础文档：[Starting an Open Source Project](https://github.com/github/opensource.guide/blob/main/_articles/starting-a-project.md)。

本指南的审核规则：

- 每个徽章必须回答一个真实问题，并可点击到证据；没有证据、没有维护者控制权或容易滞后的下载量/星标/“质量”徽章应删除。
- 徽章数量以不遮挡项目定位和 Quick Start 为限；不要用一排徽章替代 Requirements、支持矩阵或测试说明。
- 私有仓库的 GitHub workflow badge 不能被外部访问；若项目公开分发，必须检查徽章在未登录状态下是否可见：[Adding a workflow status badge](https://docs.github.com/en/actions/how-tos/monitor-workflows/add-a-status-badge)。
- “CI passing”只证明该 workflow 的范围和那次环境通过，不证明所有操作系统、架构、版本和真实数据场景都通过；README 应保留测试范围和限制。

### 截图：展示结果，不承载唯一说明

截图适合展示 UI、视觉输出、终端结果或安装流程中“用户确实会看到”的状态；不适合承载唯一的命令、配置、错误文本或可访问性关键信息。后者应同时提供可复制文本或链接。GitHub 要求图片提供简短的等价 alt text，并建议仓库图片使用相对链接：[Basic writing and formatting syntax — Images](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)。

截图审核规则：

- 截图前说明它展示的版本、平台、主题或状态；动态值、账号名、路径、token、cookie 和个人数据必须移除或替换。
- 只保留能帮助用户理解产品或验证安装成功的截图；代码块和文字说明不要截图化。
- 图片应有准确 alt text；如果深色/浅色主题都会影响理解，可使用 GitHub 支持的 `<picture>` 方式提供主题变体，并保留默认图片：[Quickstart for writing on GitHub](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/quickstart-for-writing-on-github)。
- 使用仓库内相对路径，避免 README 因外部图片服务失效；GitHub 对仓库图片的相对路径有专门说明：[About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)。
- 截图不是测试证据。功能、性能、安全和兼容性结论必须由可复现命令、日志、CI 或明确的验证记录支持；截图最多是辅助说明。

## 四、对本仓库的落地检查清单

依据快照：当前 README、`CONTRIBUTING.md`、`SECURITY.md`、`package.json`、`.github/workflows/ci.yml`、`.github/workflows/release.yml`、`docs/release.md` 和 `docs/release-checklist.md`。检查时应以这些仓库文件的实际命令和事实为准，而不是把本指南中的示例当成项目事实。

### 首屏与导航

- [x] 标题和一句话定位清楚：这是独立的 macOS 菜单栏 Codex usage companion；见 [`README.md`](../README.md)。
- [x] 有当前界面截图，且使用仓库内相对路径；截图 alt text 说明它展示的内容；依据：[GitHub 图片语法](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)。
- [x] README 解释独立维护、上游归属和当前 UI 的边界；不要将上游项目的行为自动归因给本仓库；依据：[About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)。
- [ ] 评估增加一个真正有用的 CI workflow badge，目标指向 `.github/workflows/ci.yml` 对应 workflow；只有在公开页面可访问并持续维护时才加入。依据：[Adding a workflow status badge](https://docs.github.com/en/actions/how-tos/monitor-workflows/add-a-status-badge)。

### Requirements、安装与使用

- [x] 明确 macOS 13+、Codex desktop 已安装并登录、Node.js 20+ 的前置条件；见 [`README.md`](../README.md) 和 [`package.json`](../package.json)。
- [x] Release 安装说明区分 Apple Silicon `arm64` 与 Intel `x86_64`，并给出 ZIP/DMG 的动作；见 [`README.md`](../README.md) 和 [`docs/release.md`](release.md)。
- [x] Source build、启动、CLI probe、`CODEX_BIN` 自定义路径和固定刷新间隔均有命令示例；见 [`README.md`](../README.md)。
- [x] 说明菜单栏应用不出现在 Dock、首次找不到 Codex 可执行文件时的诊断入口，以及 Gatekeeper/未签名构建限制；见 [`README.md`](../README.md) 和 [`docs/diagnostics.md`](diagnostics.md)。
- [ ] 每次修改安装器、架构命名、版本号或环境变量后，逐条执行 README 中的复制粘贴命令，并把结果同步回文档；依据：[GitHub README 的“如何开始”要求](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)。

### 构建与测试

- [x] README 给出 `npm test`、`npm run test:native`、`npm run build:macos`、`npm run start:macos`；命令与 [`package.json`](../package.json) 一致。
- [x] README 区分 Node tests、native harness、SwiftPM XCTest 的覆盖范围和 GUI 前置条件；见 [`README.md`](../README.md)。
- [x] 发布检查清单要求两个架构构建、打包、签名验证、DMG/校验和检查和一次只读 live check；见 [`docs/release-checklist.md`](release-checklist.md)。这比只写“tests pass”可审计；依据：[GitHub Open Source Guides 关于环境与测试](https://github.com/github/opensource.guide/blob/main/_articles/starting-a-project.md)。
- [ ] README 可再增加一个短的“验证判定”表：命令、通过标记、是否需要已登录 macOS 图形会话、是否使用 fake account response；来源必须保持与 [`docs/release-checklist.md`](release-checklist.md) 同步，避免把退出码 0 当成所有测试都真正执行。

### 安全与隐私

- [x] README 链接 [`PRIVACY.md`](../PRIVACY.md) 与 [`SECURITY.md`](../SECURITY.md)，并说明只通过官方本地 app-server 方法获取结构化 rate-limit response。
- [x] README 和安全政策都明确不读取 `~/.codex/auth.json`，不处理 token/cookie/session/OAuth/API key，不做浏览器抓取、OCR、登录自动化或 quota bypass；见 [`SECURITY.md`](../SECURITY.md)。
- [x] README 说明 last-known snapshot 只保存在进程内、失败时的 stale 语义和 24 小时显示上限；见 [`README.md`](../README.md) 与 [`SECURITY.md`](../SECURITY.md)。
- [ ] 每个新截图、录屏、日志和示例在合并前检查是否泄露账号标识、路径、令牌或 usage 数据；安全政策必须继续说明受支持版本和漏洞报告方式。依据：[Adding a security policy](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/add-security-policy)。

### 贡献与支持

- [x] 根目录存在 [`CONTRIBUTING.md`](../CONTRIBUTING.md)，包含范围边界和本地检查命令；GitHub 会在 issue/PR 场景暴露贡献指南：[Setting guidelines for repository contributors](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/setting-guidelines-for-repository-contributors)。
- [x] README 为故障用户链接 [`docs/diagnostics.md`](diagnostics.md)，并保留“安全边界改变不属于普通 fallback”的说明；依据：[About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)。
- [ ] 若开放更多外部贡献，补充 issue/PR 模板或在 `CONTRIBUTING.md` 写明变更描述、测试结果、平台/架构和是否触及隐私边界；GitHub 的社区健康文件机制支持 CONTRIBUTING、SECURITY、CODE_OF_CONDUCT 及 issue/PR 模板：[Creating a default community health file](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file)。

### 版本、发布与一致性

- [x] README 链接 GitHub Releases，列出架构特定 ZIP/DMG、`SHA256SUMS.txt` 和 DMG 的已知属性；见 [`README.md`](../README.md) 与 [`docs/release.md`](release.md)。
- [x] 仓库保留逐版本 release notes（例如 [`docs/release-notes-v0.1.3.md`](release-notes-v0.1.3.md)），并有发布前检查清单；这符合 Keep a Changelog 对“每个版本一个、面向人类、按类型分组”的原则：[Keep a Changelog](https://keepachangelog.com/en/1.1.0/)。
- [ ] 每次发布前核对 `package.json` 版本、tag、release title、release notes、README 的下载命名、产物架构和校验和完全一致；GitHub Release 是 tag 对应的可下载迭代，依据：[About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)。
- [ ] 如果未来把公开 API/CLI 行为视为稳定契约，在 README 或发布文档明确采用 SemVer；对兼容性破坏、新功能、兼容 bug fix 分别使用 MAJOR/MINOR/PATCH，并不修改已发布产物。依据：[Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html)。
- [ ] 在 README 中保留“未签名/未 notarize 的构建可能触发 Gatekeeper”这类可影响安装决定的限制，直到发布流程和证据实际改变；不要用“release”一词暗示已完成签名或 notarization。依据：[GitHub release packaging](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) 与仓库 [`docs/release-checklist.md`](release-checklist.md)。

## 五、维护时的最小 README 审核流程

每次改变安装命令、用户可见行为、支持平台、数据边界、CI、版本或发布资产时，按以下顺序复核：

1. 从 README 的首个用户路径开始，实际运行安装、最小使用和故障诊断命令；依据：[About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)。
2. 对照 `package.json`、脚本、CI、`CONTRIBUTING.md`、`SECURITY.md` 和发布清单，删除失效命令和过期承诺；贡献环境与测试应有专门指南，依据：[Starting an Open Source Project](https://github.com/github/opensource.guide/blob/main/_articles/starting-a-project.md)。
3. 检查所有内部链接、外部 URL、图片相对路径、alt text、代码块和徽章目标；GitHub Markdown/图片规则见 [Basic writing and formatting syntax](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)。
4. 对截图、日志、示例和发布资产做一次隐私/安全检查；漏洞报告渠道和支持版本必须与 `SECURITY.md` 一致，依据：[Adding a security policy](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/add-security-policy)。
5. 若涉及 release，核对 tag、版本、变更说明、架构产物、校验和及下载链接；遵循 [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)、[Semantic Versioning](https://semver.org/spec/v2.0.0.html) 和 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) 的分工。

## 来源索引

- [GitHub Docs：About the repository README file](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)
- [GitHub Open Source Guides：Starting an Open Source Project](https://github.com/github/opensource.guide/blob/main/_articles/starting-a-project.md)
- [GitHub Open Source Guides：仓库说明与项目背景](https://github.com/github/opensource.guide/blob/main/README.md)
- [GitHub Docs：Basic writing and formatting syntax](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)
- [GitHub Docs：Setting up your project for healthy contributions](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions)
- [GitHub Docs：Setting guidelines for repository contributors](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/setting-guidelines-for-repository-contributors)
- [GitHub Docs：Creating a default community health file](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file)
- [GitHub Docs：Adding a security policy](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/add-security-policy)
- [GitHub Docs：Releasing projects on GitHub](https://docs.github.com/en/repositories/releasing-projects-on-github)
- [GitHub Docs：Adding a workflow status badge](https://docs.github.com/en/actions/how-tos/monitor-workflows/add-a-status-badge)
- [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html)
- [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/)
