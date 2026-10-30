# 参与开发与版本发布

项目上游为 [sparkzure/PCL-Slash](https://github.com/sparkzure/PCL-Slash)。开发者通过 Fork 与 Pull Request 提交改动，正式版本由上游仓库管理员发布。

## 提交信息

采用 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/v1.0.0/) 格式：

```text
type(scope): 简明描述

改动的原因、行为变化及必要说明。

验证：执行过的检查与结果。
```

- `type` 必填，小写，可选 `feat`、`fix`、`perf`、`refactor`、`docs`、`style`、`test`、`build`、`ci`、`chore`、`revert`。
- `scope` 可省略，例如 `theme`、`about`、`launch`、`release`。
- 标题不超过 100 个字符，支持中文；标题与正文之间空一行。
- 不兼容变更使用 `feat(scope)!: 描述`，或在正文末尾写明 `BREAKING CHANGE: 迁移说明`。
- 正文描述最终效果、原因和验证结果，避免放入密钥、令牌或个人信息。
- PR 标题始终执行规范检查。提交历史以 `5ef81e490ae46b1100d61e33d0183094c7a80ca8` 为界：该提交及其祖先豁免，只检查此基线之后、且尚未包含在 PR 目标分支中的非合并提交；普通合并提交自动跳过。
- 规范基线之前的历史不要求重写。基线之后的不规范提交需在提交 PR 前整理或 squash；调整历史时保留备份，避免改动代码内容。

示例：`feat(theme): 新增苍绿色主题`、`fix(launch): 修复游戏目录包含空格时的启动失败`、`ci(release): 自动生成版本草稿`。

仓库管理员可在分支保护或 Ruleset 中将 `Commit message check` 设为必需检查，并让 squash 提交使用符合规范的 PR 标题。

## 本地检查

应用构建使用本地的 `Plain Craft Launcher 2/bin/build.cmd`。流水线使用 Windows 上的 MSBuild，并使用源码中自带的帮助包。

自动发布逻辑使用 Node.js 24 内置测试运行器，无需安装 npm 依赖：

```text
node --test .github/scripts/automation.test.cjs
```

PR 不注入构建凭据；上游仓库的分支与标签构建可使用 `CLIENT_ID` 和 `CURSEFORGE_API_KEY` 两个仓库 Secret。草稿创建与附件上传使用内置 `GITHUB_TOKEN`，仅草稿任务申请 `contents: write`。

## 标签与草稿发布

管理员将版本标签推送至 **sparkzure/PCL-Slash** 后，流水线自动运行。非 `v` 开头的标签不会启动发布流程；不符合版本格式的 `v` 标签会被检查拒绝。

| 类型 | 标签示例 | 构建配置 | GitHub Releases 中的草稿 |
| --- | --- | --- | --- |
| 正式版 | `v2.14.1.0` 或 `v2.14.1` | `Release` | 普通 Release，`prerelease=false` |
| 快照及测试版 | `v2.14.1.0-snapshot.1`、`v2.14.1-beta.1`、`v2.14.1-rc.1` | `Snapshot` | Pre-release，`prerelease=true` |

两种类型均由管理员编辑草稿后手动发布。快照预发布不会作为 GitHub 的 Latest 正式版。普通分支、PR 和手动构建检查 Debug、Snapshot、Release 三种配置；标签构建只打包对应的发行配置。

1. 先合并改动，并维护代码中单调递增的内部 `VersionCode`。标签构建会自动同步构建工作副本中的 `VersionBaseName`、`AssemblyVersion`、`AssemblyFileVersion` 和 `AssemblyInformationalVersion`，无需手工反复填写这些显示版本。
2. 在管理员的上游仓库克隆中创建并推送标签，例如 `git tag v2.14.1.0`，再执行 `git push origin v2.14.1.0`。
3. 流水线检查自动化脚本、按标签选择 Snapshot 或 Release 构建，并生成 ZIP 和 SHA-256 校验文件。任何构建失败都不会创建草稿。
4. 将对应通道的压缩包、校验文件和完整 `CHANGELOG.md` 附加到 GitHub Release **草稿**。不会将 Release 编译的程序误作快照版上传，也不会将 Snapshot 程序上传到正式版草稿。
5. 草稿保留提交正文与验证说明。快照版汇总上一个可达版本标签之后的非合并提交；正式版以上一个可达正式版标签为界，包含其间的全部快照开发记录。首个版本包含标签之前的全部非合并提交；旧格式提交归入“其他变更”。较长的记录以附件完整保留。
6. 仓库管理员在 Releases 中修改标题、说明、附件及预发布标记，核对完成后自行点击 **Publish release**。流水线始终只创建草稿，不自动正式发布。

同一标签重跑时，仅替换同名构建附件，保留管理员已修改的标题和正文；已发布的版本不再修改。正常分支构建、PR 与手动 Build 任务均不会创建 Release 草稿。需要重新生成正文时，可从附件 `CHANGELOG.md` 中复制所需内容。

工作流首次使用前，管理员需确认仓库允许 Actions 创建 Release（`GITHUB_TOKEN` 可获得 `contents: write`）。仓库或组织的权限策略可能覆盖工作流申请的权限。

## Bot 与自动更新

当前标签版本同步仅作用于构建工作副本，不会提交源码，也不会自动决定内部 `VersionCode`。该字段用于升级迁移和缓存，必须递增，不能直接拼接快照标签或随意重置。

可以进一步接入版本 Bot：由 Bot 创建规范的版本 PR，统一更新显示版本、程序集版本与内部 `VersionCode`，审核合并后再打标签。在管理员发布 Release 后，可再由 `release.published` 工作流生成正式版和快照版各自的更新清单，包含版本、通道、内部版本码、安装包地址与 SHA-256。草稿不应进入用户的更新清单。

启动器中的更新检查、替换和重启函数目前仍是占位实现；要实现客户端在线自动更新，还需接入更新清单读取、通道选择、校验和下载替换流程。仅由 Bot 修改版本号不等于实现了自动更新。

如果 Bot 使用默认 `GITHUB_TOKEN` 推送标签，通常不会再次触发标签构建流程。需要使用 GitHub App 令牌，或显式派发工作流，并保持草稿由管理员发布的步骤。参见 [GitHub 的工作流触发规则](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)。
