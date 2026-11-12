# 贡献指南

欢迎通过问题反馈、功能建议、代码、界面设计和文档参与 [PCL-Slash](https://github.com/Sparkzure/PCL-Slash)。本指南适用于所有贡献者；使用 Agent 的贡献还需遵守 [AGENTS.md](AGENTS.md)。

## 开始之前

- 先查看已有 Issue 和 PR，避免重复工作。反馈问题时，提供版本、复现步骤、预期与实际表现，以及移除个人信息后的日志。
- 对较大的功能、架构或兼容性调整，建议先开 Issue 说明使用场景和方案。
- 讨论聚焦问题与方案，尊重其他参与者；评审意见请说明理由，处理分歧时保持友善。
- 阅读并遵循原版 PCL 的 [存储库合理使用指南](LICENCE)，保留上游署名、赞助入口和第三方声明。引入外部代码或素材时说明来源及适用声明，不自行变更项目授权。

## 开发与验证

从上游 `main` 创建工作分支，通常通过 Fork 提交。获取源码后初始化子模块：

```powershell
git submodule update --init --recursive
```

应用使用 VB.NET / C# 和 WPF，目标为 .NET Framework 4.8。请在 Windows 准备支持 C# 13 的 .NET SDK、MSBuild、.NET 桌面开发组件及 .NET Framework 4.8 目标包，然后在 Developer PowerShell 中运行：

```powershell
dotnet restore PCLCS/PCLCS.csproj
msbuild "Plain Craft Launcher 2/Plain Craft Launcher 2.vbproj" -p:Configuration=Debug
```

CI 脚本使用 Node.js 24，无需额外 npm 依赖：

```powershell
node --test .github/scripts/*.test.cjs
```

验证应与改动对应：应用行为变更先构建，再执行 [tests](tests) 中相关的 `verify-*.ps1`；Windows/WPF 脚本使用 `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File <脚本路径>`。只改文档时检查内容、链接与排版即可。具体检查索引见 [AGENTS.md](AGENTS.md#验证要求)。

保持现有代码风格，避免无关重构或整仓格式化。配置、存储、迁入或备份行为变化应说明兼容性和失败处理，并补充有实际价值的验证。构建产物、个人数据、凭据和本机工具目录不应提交。

## 提交规范

提交标题和 PR 标题采用 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/v1.0.0/)：

```text
type(scope): 简明描述
```

- 类型可用 `feat`、`fix`、`perf`、`refactor`、`docs`、`style`、`test`、`build`、`ci`、`chore`、`revert`；scope 可省略，标题不超过 100 个字符。
- 按功能分类提交，每个提交表达清楚的改动；必要的正文与标题空一行，说明原因、行为变化和实际验证。
- 不兼容变更在标题使用 `!`，或在正文标注 `BREAKING CHANGE:` 并说明迁移方法。
- 提交检查仅针对基线 `5ef81e490ae46b1100d61e33d0183094c7a80ca8` 之后、目标分支尚未包含的非合并提交；基线及其祖先不需要重写。

## 提交 Pull Request

1. 同步上游 `main`，按 [PR 模板](.github/PULL_REQUEST_TEMPLATE.md) 填写改动目的、用户可见变化、验证结果和兼容性；关联 Issue 时使用 `Closes #编号` 等说明。
2. 一个 PR 可以包含多项改动，请分别列出内容及验证。尚未完成时标为 Draft。
3. 如有实质 AI 辅助，按模板披露工具、使用范围与验证方式，并为相关提交添加 `Co-Authored-By`。只勾选实际完成的检查，如实区分自动验证和人工审核。
4. 等待自动化测试、提交检查和 Debug / Snapshot / Release 构建，通过后由维护者审查与合并。无法本地执行的检查应说明原因，不能写成已通过。

评审期间尽量保留可追踪的增量提交；确需整理或强推历史时，先与协作者协调并保留备份。

## 版本发布

版本由维护者在上游运行 **Version Bot** 创建版本 PR，审核合并后自动打标签，再由 Build 生成 Release 草稿。核对说明与附件后，由维护者手动发布。

普通功能 PR 不更新版本号、内部编号或 `.github/release-bot.json`。发布通道、凭据和工作流配置以 [.github/workflows](.github/workflows) 为准；PR 构建不注入发布凭据。
