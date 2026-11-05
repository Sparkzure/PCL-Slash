<!-- Adapted from the OpenListTeam/OpenList pull request template. -->
<!--
PR title / PR 标题:
- Use Conventional Commits: `type(scope): summary`
- Allowed types: `feat`, `fix`, `perf`, `refactor`, `docs`, `style`, `test`, `build`, `ci`, `chore`, `revert`
- Scope is optional; the title must not exceed 100 characters.
- For breaking changes, add `!`: `feat(login)!: change auth flow`
- Release notes use commit titles, grouped by type, with links to each commit and its author.

- 使用 Conventional Commits：`type(scope): 描述`。
- scope 可省略；标题不超过 100 个字符。
- 不兼容变更加 `!`，例如 `feat(login)!: 调整登录流程`。
- 发行说明使用 commit 标题，按类型分类并链接至 commit 和提交作者；PR 标题仍须准确描述最终改动。
-->

## Summary / 摘要

<!--
Briefly describe what changed and why.
简要说明改了什么，以及为什么需要改。
-->

<!--
- List user-visible behavior changes.
- List important implementation changes.
- Mention config, storage, API, or compatibility changes if any.

- 列出用户可感知的行为变化。
- 列出重要实现变化。
- 如涉及配置、存储、API 或兼容性变化，请明确说明。
-->

- [ ] This PR has breaking changes.
      / 此 PR 包含破坏性变更。
- [ ] This PR changes public API, config, storage format, or migration behavior.
      / 此 PR 修改了公开 API、配置、存储格式或迁移行为。
- [ ] This PR requires corresponding changes in related repositories.
      / 此 PR 需要关联仓库同步修改。

Related repository PRs / 关联仓库 PR:

<!-- List repository names and PR links; remove if not applicable.
填写关联仓库名称与 PR 链接；不适用时删除。 -->

-

## Related Issues / 关联 Issue

<!--
Use `Closes #123`, `Fixes #123`, or `Relates to #123`.
Remove this section if not applicable.
使用 `Closes #123`、`Fixes #123` 或 `Relates to #123`。
不适用时请删除本节。
-->

## Testing / 测试

<!--
Describe commands, platforms, and manual checks.
If not tested, explain why. Remove checks that do not apply.

说明执行过的命令、测试平台和手动验证。
如果未测试，请说明原因；不适用的检查项请删除。
-->

- [ ] Release build / Release 构建：`& '.\Plain Craft Launcher 2\bin\build.cmd' -Configuration Release -NoRestore`
- [ ] Automation tests / 自动化测试：`node --test .github/scripts/*.test.cjs`
- [ ] Theme checks / 主题检查：`powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/verify-themes.ps1`
- [ ] Update checks / 更新检查：`powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/verify-launcher-updates.ps1`
- [ ] Manual test / 手动测试:

## Checklist / 检查清单

- [ ] I have read [CONTRIBUTING](https://github.com/Sparkzure/PCL-Slash/blob/main/CONTRIBUTING.md).
      / 我已阅读 [贡献指南](https://github.com/Sparkzure/PCL-Slash/blob/main/CONTRIBUTING.md)。
- [ ] I confirm this contribution follows the repository license and contribution policy.
      / 我确认此贡献符合仓库许可证和贡献规范。
- [ ] I have the right to submit this contribution and agree to the project's GPL-3.0-only policy for all PCL-Slash-original code since its fork from PCL, as described in [LICENSING.md](https://github.com/Sparkzure/PCL-Slash/blob/main/LICENSING.md); I have identified upstream and third-party content and their licenses.
      / 我有权提交本次贡献，并同意按 [LICENSING.md](https://github.com/Sparkzure/PCL-Slash/blob/main/LICENSING.md) 所述，对 PCL-Slash 自原版分支后的全部项目原创代码统一采用 GPL-3.0-only；已注明引入的上游和第三方内容及其许可。
- [ ] I have formatted the changed code following the existing VB.NET, C#, XAML, or script style where applicable.
      / 我已按适用情况遵循现有 VB.NET、C#、XAML 或脚本风格格式化变更代码。
- [ ] I have updated the relevant user or developer documentation where applicable.
      / 我已在适用情况下同步相关用户文档或开发文档。
- [ ] I have ensured that the changes contain no secrets, tokens, or private information.
      / 我已确认改动未包含密钥、令牌或个人隐私信息。
- [ ] I have requested review from relevant maintainers or code owners where applicable.
      / 我已在适用情况下请求相关维护者或代码所有者审查。

## AI Disclosure / AI 使用声明

<!--
Please disclose any substantial AI assistance used in this PR.
Minor AI assistance, such as typo fixes, autocomplete, formatting suggestions,
or wording polish, does not need to be disclosed.
Remove this section if not applicable.

请披露此 PR 中使用的重要 AI 辅助内容。
轻微 AI 辅助，例如拼写修正、自动补全、格式建议或文字润色，无需披露。
如不适用，请删除本节。

Deliberate non-disclosure may be treated as a trust and compliance issue.

故意隐瞒 AI 使用情况可能被视为信任与合规问题。
-->

- [ ] This PR includes AI-assisted content.
      / 此 PR 包含 AI 辅助内容。

Tools used / 使用工具:

- [ ] ChatGPT
- [ ] Codex
- [ ] GitHub Copilot
- [ ] Claude
- [ ] Gemini
- [ ] Other (please specify) / 其他（请注明）:

Usage scope / 使用范围:

- [ ] Code generation / 代码生成
- [ ] Refactoring / 重构
- [ ] Documentation / 文档
- [ ] Tests / 测试
- [ ] Translation / 翻译
- [ ] Review assistance / 审查辅助

- [ ] I have reviewed and validated all AI-assisted content included in this PR.
      / 我已审核并验证此 PR 中的所有 AI 辅助内容。
- [ ] I have ensured that all AI-assisted commits include `Co-Authored-By` attribution.
      / 我已确保所有 AI 辅助提交都包含 `Co-Authored-By` 归属信息。
- [ ] I can reproduce all AI-assisted content included in this PR without any AI tools.
      / 我可以在没有任何 AI 工具的情况下重现此 PR 中包含的所有 AI 辅助内容。
