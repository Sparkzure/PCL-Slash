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

## Pull Request 流程

1. 从上游 `main` 同步最新代码，通过 Fork 提交 PR；一次 PR 聚焦一个可独立审查的改动，未完成时先标为 Draft。
2. 按本仓库的 [PR 模板](.github/PULL_REQUEST_TEMPLATE.md) 说明改动原因、行为变化、关联 Issue、验证结果和兼容性。模板已从 OpenList 引入并适配本项目，保留双语摘要、测试、检查清单和完整 AI 使用声明。实质 AI 辅助内容按模板注明工具、范围、人工验证及 `Co-Authored-By` 归属信息。
3. PR 标题使用上述 Conventional Commits 格式。标题不合规时自动留言并使 `PR title check` 失败；修改标题后更新同一条评论，避免重复留言。scope 沿用本项目规则，可省略。
4. 所有 PR 均运行 Build 的自动化测试和 Debug、Snapshot、Release 三种配置构建；`Commit message check` 检查标题与基线之后新增的 commit。标题反馈工作流仅运行目标分支上的可信脚本，不执行 PR 代码；Fork 构建不注入凭据。
5. 由维护者审查并决定合并。建议将 `PR title check`、`Commit message check`、`Automation tests` 和三种 Build 检查设为必需项，并要求至少一次人工审查；这些保护规则需仓库管理员在 GitHub 设置中启用，工作流不会自动更改仓库设置。
6. 合并后的 PR 标题会进入对应版本发行说明，PR 正文中的测试报告不会复制到发行说明。发布仍须管理员编辑草稿后手动完成。

模板和标题反馈均由本仓库的 [PR 模板](.github/PULL_REQUEST_TEMPLATE.md) 与 [标题反馈工作流](.github/workflows/pr-feedback.yml) 提供。

## 本地检查

应用构建使用本地的 `Plain Craft Launcher 2/bin/build.cmd`。流水线使用 Windows 上的 MSBuild，并使用源码中自带的帮助包。

自动发布逻辑使用 Node.js 24 内置测试运行器，无需安装 npm 依赖：

```text
node --test .github/scripts/*.test.cjs
```

PR 不注入构建凭据；上游仓库的分支与标签构建可使用 `CLIENT_ID` 和 `CURSEFORGE_API_KEY` 两个仓库 Secret。草稿创建与附件上传使用内置 `GITHUB_TOKEN`，仅草稿任务申请 `contents: write` 以及读取 PR 元数据的 `pull-requests: read`；标题反馈单独申请 `pull-requests: write`，用于管理提示评论。

## 主题配置

主题在代码、界面绑定和持久化中均使用语义化字符串，例如 `tianyi-blue`、`geek-blue`，不使用数字编号。

| 设置键 | 内容 |
| --- | --- |
| `UiThemeSelected` | 当前主题键，默认为 `tianyi-blue` |
| `UiThemeUnlocked` | 已解锁隐藏主题的 JSON 字符串数组，默认为 `[]`；去重且仅接受有效隐藏主题键 |
| `UiThemeCustomHue` | 自定义色调 |
| `UiThemeCustomSaturation` | 自定义饱和度 |
| `UiThemeCustomLightness` | 自定义亮度 |
| `UiThemeCustomGradient` | 自定义标题栏色调渐变 |
| `UiThemeColorfulBackground` | 是否使用主题彩色背景 |

本次配置格式变更不提供旧主题设置、数字编号或解锁记录的兼容与迁移。新增主题需同步 `LauncherTheme`、个性化界面和主题检查；有装饰纹理时补充 `ThemeTitleTextureFiles` 与项目资源引用。

执行 `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/verify-themes.ps1` 验证配色、语义化配置的读写、解锁规则、旧数据拒绝和纹理切换。

## 标签与草稿发布

管理员将版本标签推送至 **sparkzure/PCL-Slash** 后，流水线自动运行。非 `v` 开头的标签不会启动发布流程；不符合版本格式的 `v` 标签会被检查拒绝。

| 类型 | 标签示例 | 构建配置 | GitHub Releases 中的草稿 |
| --- | --- | --- | --- |
| 正式版 | `v2.14.1.0` 或 `v2.14.1` | `Release` | 普通 Release，`prerelease=false` |
| 快照及测试版 | `v2.14.1.0-snapshot.1`、`v2.14.1-beta.1`、`v2.14.1-rc.1` | `Snapshot` | Pre-release，`prerelease=true` |

两种类型均由管理员编辑草稿后手动发布。快照预发布不会作为 GitHub 的 Latest 正式版。普通分支、PR 和手动构建检查 Debug、Snapshot、Release 三种配置；标签构建只打包对应的发行配置。

1. 先合并业务改动。使用下述 Version Bot 创建版本 PR，自动更新显示版本、程序集版本和目标通道的内部 `VersionCode`；审核合并后自动打标签。标签构建仍会同步构建工作副本中的版本字段。
2. 如需手动发布，先维护递增的 `VersionCode` 并合并，再在管理员的上游仓库克隆中创建并推送标签，例如 `git tag v2.14.1.0`，再执行 `git push origin v2.14.1.0`。
3. 流水线检查自动化脚本、按标签选择 Snapshot 或 Release 构建，并生成 ZIP 和 SHA-256 校验文件。任何构建失败都不会创建草稿。
4. 将对应通道的压缩包、校验文件和完整 `CHANGELOG.md` 附加到 GitHub Release **草稿**。不会将 Release 编译的程序误作快照版上传，也不会将 Snapshot 程序上传到正式版草稿。
5. 草稿与 `CHANGELOG.md` 只列出已合并 PR 的完整标题、PR 链接和提出者链接，不收录 commit 信息或 PR 正文。同一个 PR 只出现一次，支持 merge、squash 和 rebase 合并。正式版以上一个可达正式版标签为起点；Snapshot 以上一个可达版本标签（包括 Snapshot、Beta、正式版等）为起点；Beta 以上一个可达 Beta 标签为起点，即使中间有正式版也不会截断。范围不包含起点、包含当前标签。没有同类起点时，从当前标签可达的全部历史中收集 PR。直接提交、未合并 PR 和范围外 PR 不进入说明；没有 PR 时明确提示。较长的记录以附件完整保留。
6. 仓库管理员在 Releases 中修改标题、说明、附件及预发布标记，核对完成后自行点击 **Publish release**。流水线始终只创建草稿，不自动正式发布。

同一标签重跑时，仅替换同名构建附件，保留管理员已修改的标题和正文；已发布的版本不再修改。正常分支构建、PR 与手动 Build 任务均不会创建 Release 草稿。需要重新生成正文时，可从附件 `CHANGELOG.md` 中复制所需内容。

工作流首次使用前，管理员需确认仓库允许 Actions 创建 Release（`GITHUB_TOKEN` 可获得 `contents: write`）。仓库或组织的权限策略可能覆盖工作流申请的权限。

## Version Bot

工作流为 `.github/workflows/release-bot.yml`，仅在 `sparkzure/PCL-Slash` 执行。先将工作流和脚本合并到默认分支，再使用 Actions 页面操作，无需独立服务器。

### 首次配置

在 GitHub 创建并安装一个 GitHub App 到 `sparkzure/PCL-Slash`，仓库权限为 `Contents: Read and write` 和 `Pull requests: Read and write`。仅用于 Actions 认证时关闭 Webhook，不需要 Callback URL 或 Client secret。

在仓库 Settings → Secrets and variables → Actions 中保存：

| 类型 | 名称 | 内容 |
| --- | --- | --- |
| Variable | `RELEASE_BOT_CLIENT_ID` | GitHub App 的 Client ID，与微软登录的 `CLIENT_ID` 无关 |
| Secret | `RELEASE_BOT_PRIVATE_KEY` | App 私钥 PEM 文件全文，包含首尾标记和换行 |

也可以使用组织级同名 Variable 和 Secret，但必须授权该仓库访问。组织 Actions 策略需要允许工作流使用 `actions/create-github-app-token@v3` 等所引用的 Actions。

### 选择通道并创建版本 PR

1. 先合并准备发布的业务改动，进入仓库 Actions → **Version Bot** → **Run workflow**。
2. 分支选择默认分支。`channel` 选择 `snapshot`（快照）或 `release`（正式）。
3. `version` 填写不带 `v` 的目标版本，如下表。版本标签不能重复使用。
4. 运行后，在该次运行的摘要中打开 Bot 创建的 PR；等待 Build 和提交规范检查通过，再由管理员审核合并。Bot 不自动批准或合并 PR。

| channel | version 示例 | 标签 | 构建和草稿类型 |
| --- | --- | --- | --- |
| `snapshot` | `2.14.1.0-snapshot.1` | `v2.14.1.0-snapshot.1` | Snapshot / Pre-release |
| `snapshot` | `2.14.1.0-beta.1` 或 `2.14.1.0-rc.1` | 相应的 `v` 标签 | Snapshot / Pre-release |
| `release` | `2.14.1.0` | `v2.14.1.0` | Release / 普通 Release |

三段数字版本也支持。快照必须包含预发布后缀，正式版不能包含预发布后缀，填写不一致会失败。Bot 取两个通道现有 `VersionCode` 的最大值加一，仅修改目标通道的编号；另一个通道保持原值。显示版本、程序集数字版本及信息版本同时更新。

一次仅允许一个待合并的版本 PR，跨通道也不能同时占用编号。同版本重复运行返回原 PR，不重复加号。版本 PR 只修改 `ModBase.vb`、`AssemblyInfo.vb` 和 `.github/release-bot.json`；清单记录这次发布的标签、通道和编号，供合并后校验。

### 合并、打标签和发布

PR 合并后，Version Bot 使用默认分支上的可信脚本校验：PR 必须来自当前 App 和本仓库，目标为默认分支，仅包含预期版本文件，合并后的版本字段必须对应其第一父提交的最大编号加一。它不会检出或执行 PR 分支代码。

校验通过后，Bot 用 App 安装令牌给 **PR 的合并提交** 创建标签，继续触发 Build → 构建、打包、生成 Release 草稿。管理员检查附件和说明后手动发布；Bot 不直接发布 Release。

### 失败和重跑

- 创建 PR 前失败：检查运行日志中的凭据、通道、版本或权限错误，修正后重新 Run workflow。
- 分支已创建但 PR 创建失败：修复权限后重新 Run workflow。仅在原分支的文件树和父提交与本次预期完全一致时，Bot 才复用分支并补建 PR；否则请使用新的版本号，不会强制覆盖已有分支。
- 不再发布某个版本：关闭版本 PR；建议下次使用新的标签名称，旧分支不会被强制覆盖。
- 合并后打标签失败：修复 App 安装、权限或凭据后，在该次 **合并事件** 的 Version Bot 运行中选择 Re-run failed jobs。不要用 Run workflow 再申请同一个版本。
- 如果等待合并期间有人修改了版本字段，合并校验会拒绝旧编号；请在合并前关闭过期 PR，使用新的版本号重新创建。若已经合并且校验失败，需要管理员修正或撤销这次版本变更后恢复流程。
- 已有标签指向同一合并提交时重跑不做修改；指向其他提交时拒绝覆盖。上个版本合并后尚未成功打标签时，Bot 阻止创建下一个版本 PR，应先恢复上个版本的打标签任务。

## 启动器更新通知

Version Bot 负责源码中的版本信息和内部编号；独立的手动标签构建仍不会自动递增编号。客户端直接读取上游 GitHub Releases：正式版读取最新正式发布，预发布构建按自身版本标签区分通知通道，`snapshot` 只检查 Snapshot，`beta` 只检查 Beta，`rc` 只检查 RC；各预发布通道都可收到后续正式版通知。预发布通道检查最近 100 个发布，未带后缀的本地 Snapshot / Debug 构建使用 Snapshot 通知通道。Beta 和 Snapshot 仍使用相同的 Snapshot 编译配置，但不会互相通知。草稿及不符合项目版本格式的标签不参与更新判断，三段和四段版本统一比较，同通道的预发布序号按数值排序。

启动时在后台检查新版，获取中、已是最新版、发现新版或获取失败等结果仅通过左下角提示显示，可在“设置 → 其他 → 启动器”关闭“启动时检查新版”。已移除升级后的更新内容窗口、发现新版时的自动弹窗、公告设置及其状态记录。网络失败、API 限流或没有有效发布时，不会将当前版本误判为最新版，也不阻断启动。“查看更新”及其他更新入口统一显示手动更新说明，提供“前往 Releases”和“取消”两个按钮。用户下载新版后退出启动器，自行替换 EXE；保留 PCL 与游戏文件夹。程序不自动下载、替换 EXE，也不为更新而重启或处理 `--update` 参数。

客户端更新通知回归检查（先通过指定 `build.cmd` 构建）：

```text
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/verify-launcher-updates.ps1
```

如果 Bot 使用默认 `GITHUB_TOKEN` 推送标签，通常不会再次触发标签构建流程。需要使用 GitHub App 令牌，或显式派发工作流，并保持草稿由管理员发布的步骤。参见 [GitHub 的工作流触发规则](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)。

## 内置联机功能移除

本分支不再包含联机页面、联机设置、邀请码事件、剪贴板自动加入、EasyTier 模块下载与启动、云端联机配置及相应资源。自定义事件中的 `加入房间`、页面 `Link` 和子页面 `SetupLink` / `LinkMain` 已删除；其余事件和页面的数字编号保持不变，导航按控件的 `Tag` 匹配。

构建后执行 `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/verify-no-link.ps1`，检查联机类型、配置和资源已移除，现有页面编号、设置导航与更新通知仍可用。
