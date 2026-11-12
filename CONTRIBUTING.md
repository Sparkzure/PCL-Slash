# 参与开发与版本发布

项目上游为 [sparkzure/PCL-Slash](https://github.com/sparkzure/PCL-Slash)。开发者通过 Fork 与 Pull Request 提交改动，正式版本由上游仓库管理员发布。

本项目沿用原版 PCL 的 [存储库合理使用指南](LICENCE)。

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

1. 从上游 `main` 同步最新代码，通过 Fork 提交 PR。一个 PR 可以包含多项功能、修复或其他改动，请在描述中清楚列出各项内容与验证结果；未完成时先标为 Draft。
2. 按本仓库的 [PR 模板](.github/PULL_REQUEST_TEMPLATE.md) 说明改动原因、行为变化、关联 Issue、验证结果和兼容性。模板已从 OpenList 引入并适配本项目，保留双语摘要、测试、检查清单和完整 AI 使用声明。实质 AI 辅助内容按模板注明工具、范围、人工验证及 `Co-Authored-By` 归属信息。
3. PR 标题使用上述 Conventional Commits 格式。标题不合规时自动留言并使 `PR title check` 失败；修改标题后更新同一条评论，避免重复留言。scope 沿用本项目规则，可省略。
4. 所有 PR 均运行 Build 的自动化测试和 Debug、Snapshot、Release 三种配置构建；`Commit message check` 检查标题与基线之后新增的 commit。标题反馈工作流仅运行目标分支上的可信脚本，不执行 PR 代码；Fork 构建不注入凭据。
5. 由维护者审查并决定合并。建议将 `PR title check`、`Commit message check`、`Automation tests` 和三种 Build 检查设为必需项，并要求至少一次人工审查；这些保护规则需仓库管理员在 GitHub 设置中启用，工作流不会自动更改仓库设置。
6. 发行说明从版本范围内的 commit 标题生成，按提交类型分类，并链接到 commit 和提交作者；PR 标题与正文不再作为日志来源。发布仍须管理员编辑草稿后手动完成。

模板和标题反馈均由本仓库的 [PR 模板](.github/PULL_REQUEST_TEMPLATE.md) 与 [标题反馈工作流](.github/workflows/pr-feedback.yml) 提供。

## 本地检查

应用构建使用本地的 `Plain Craft Launcher 2/bin/build.cmd`。流水线使用 Windows 上的 MSBuild。

自动发布逻辑使用 Node.js 24 内置测试运行器，无需安装 npm 依赖：

```text
node --test .github/scripts/*.test.cjs
```

PR 不注入构建凭据；上游仓库的分支与标签构建可使用 `CLIENT_ID` 和 `CURSEFORGE_API_KEY` 两个仓库 Secret。提交日志读取、草稿创建与附件上传使用内置 `GITHUB_TOKEN`，仅草稿任务申请 `contents: write`；标题反馈单独申请 `pull-requests: write`，用于管理提示评论。

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

## 便携配置与设置备份

启动器数据保存在 EXE 所在目录，普通配置分别使用 `PCL/Setup.ini` 和 `PCL/Portable.json`。首次创建本地配置时只读导入旧注册表中的普通设置，不改写原记录；Windows 显卡偏好、字体修复等系统功能仍保留其必要的系统配置操作。

登录凭据和关联账号缓存使用 Windows DPAPI `CurrentUser` 加密，并绑定具体配置字段。旧 DES 登录缓存不迁移，无法解密时保留原密文并要求重新登录。复制启动器文件夹到其他 Windows 用户后，账号通常需要重新登录。

在“设置 → 启动器 → 启动器”中使用“导出设置”和“导入设置”保存或恢复一个 ZIP 压缩包。操作前弹窗说明支持范围：

- 包含普通全局设置、自定义主页变量、`PCL/Logo.png`、`PCL/Custom.xaml`、`PCL/CustomSkin.png`、`PCL/Pictures` 和 `PCL/Musics`，以及已注册或本地发现的游戏目录中的实例。
- 实例采用 Modrinth 整合包的清单和 `overrides` 布局，保留 Mod、配置、脚本、材质、光影及普通实例设置；不打包 Minecraft 本体、`libraries`、`assets`、Java、存档、日志或缓存。导出不依赖在线查询 Mod 下载地址，Mod 文件直接保存在整合包内。
- 不包含所有标记为加密的设置（包括账号、令牌和主题解锁记录）、Java 路径、Java 扫描列表及原游戏目录路径。旧配置包中的 Java 与游戏路径也会忽略，保留本机 Java 选择。自定义主页、变量及启动参数可能包含个人信息或执行操作，仅导入可信来源的备份。
- 导入覆盖包内对应的普通设置和同名启动器资源，不删除其他资源，保留本机账号及其他加密设置。实例恢复到新的 `PCL/Instances/<会话>/versions` 目录并注册为游戏目录，不覆盖原实例，重名实例自动区分。写入失败时回滚已覆盖文件。
- 成功后关闭启动器，重新打开生效。原版运行资源在启动时联网补全；Mod Loader 实例首次点击启动会复用正常组件安装流程，完成后再次点击启动，避免缺失 Forge/NeoForge 安装器产物。独立 OptiFine 实例需要原安装清单；作为 Mod 安装的 OptiFine 随 Mod 文件保留。

配置包使用版本为 `2`、格式标识为 `PCL-Slash.Settings` 的 `settings.json`，启动器资源位于 `assets/`，实例包位于 `instances/*.mrpack`。仍可读取版本 `1` 的配置包。实例包通过附加的 `pcl-slash.instance.json` 保存自包含版本元数据及经过过滤的普通实例设置，不复制原始 `PCL/config.json` 或 Java 选择。导入、导出均按显式支持范围过滤，嵌套实例包同样校验路径与大小。展开总大小上限为 2 GB，最多 10000 个 ZIP 条目；临时文件和回滚备份保存在 EXE 旁的 `PCL/Temp` 内，正常完成或取消后清理。

构建后执行 `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/verify-settings-archive.ps1`，验证设置和资源往返、加密配置排除及保留、自定义变量、失败回滚、非法路径、异常包和临时文件清理。便携存储与 DPAPI 使用 `tests/verify-portable-settings.ps1` 检查。

## 设置与更多页面

下载设置分为三个独立板块：“下载镜像”选择实际镜像服务，“下载策略”控制游戏文件和版本列表的官方源/镜像源优先级、并发与限速，“社区资源”保留社区来源策略及显示选项。镜像默认沿用 BMCLAPI 与 MCIM，也可分别选择自定义根地址。

游戏镜像须兼容 BMCLAPI 的路径协议，社区镜像须兼容 MCIM 的 `/modrinth`、`/curseforge` 和文件路径协议。填写完整 HTTP/HTTPS 根地址，可包含路径前缀和端口，不能包含凭据、查询参数或片段。无效或空地址暂用原预设；仅影响之后创建的请求及下载任务。自定义地址同时用于版本列表、小文件、游戏资源、安装器及 Java 等原预设调用，保留官方源的原有优先级和回退规则。设置以普通配置保存，可随配置 ZIP 导入导出，下载页重置会恢复预设并清空自定义地址。

构建后执行 `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/verify-download-mirrors.ps1`，验证独立板块、预设、自定义路径、地址校验、优先级、文件下载入口、本地模拟 HTTP 请求、设置持久化及重置范围。

设置侧边栏依次为“启动”“游戏功能”“下载”“个性化”“启动器”和“其他”。离线皮肤与辅助功能位于游戏功能页，下载和启动器选项各自独立，其他页仅保留调试选项。各页面的功能隐藏与重置范围分别管理。

“更多”中的“关于”和“鸣谢”分别提供版本及法律信息、原版 PCL 特别鸣谢名单。EasyTier 的历史鸣谢文字、头像和项目链接保留，联机实现仍已移除。内置帮助页面、文档包和帮助事件已删除，旧自定义主页使用的相关事件需自行调整。

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
5. 草稿与 `CHANGELOG.md` 从 commit 生成，包含完整提交标题、短 SHA（链接至完整 commit）及提交作者链接，不收录提交正文、验证报告或 PR 元数据。按 Conventional Commits 类型分为新增功能、问题修复、性能优化、代码重构、文档、代码风格、测试、构建、持续集成、维护和回退；旧格式或未知类型归入“其他”。标题带 `!` 或正文含 `BREAKING CHANGE:` / `BREAKING-CHANGE:` 的提交单列为“破坏性变更”，每个 SHA 仅出现一次。同一分类内按版本范围中的提交顺序排列，空分类不显示。普通合并提交跳过，其分支上的实际提交正常收录；直接提交、squash 和 rebase 后的提交均收录。作者已关联 GitHub 时链接到其个人或 Bot 页面；未关联账号时显示 Git 作者姓名，并链接到按其邮箱或姓名筛选的仓库提交记录。正式版以上一个可达正式版标签为起点；Snapshot 以上一个可达版本标签（包括 Snapshot、Beta、正式版等）为起点；Beta 以上一个可达 Beta 标签为起点，即使中间有正式版也不会截断。范围不包含起点、包含当前标签，并始终排除历史基线 `5ef81e490ae46b1100d61e33d0183094c7a80ca8` 本身及其全部祖先（包括基线前已合并的分支提交）。没有同类起点时，只收录当前标签可达、且不属于基线及其祖先的非合并提交。基线及更早的版本不会生成旧记录。没有可记录的提交时明确提示。提交元数据分页获取，并与本地 Git 范围逐一校验；无法读取基线、API 获取失败或缺少提交时停止生成，避免日志被截断。较长的记录以附件完整保留。
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

Version Bot 负责源码中的版本信息和内部编号；独立的手动标签构建仍不会自动递增编号。客户端通过所选更新检查源读取上游 GitHub Releases：正式版读取最新正式发布，预发布构建按自身版本标签区分通知通道，`snapshot` 只检查 Snapshot，`beta` 只检查 Beta，`rc` 只检查 RC；各预发布通道都可收到后续正式版通知。预发布通道检查最近 100 个发布，未带后缀的本地 Snapshot / Debug 构建使用 Snapshot 通知通道。Beta 和 Snapshot 仍使用相同的 Snapshot 编译配置，但不会互相通知。草稿及不符合项目版本格式的标签不参与更新判断，三段和四段版本统一比较，同通道的预发布序号按数值排序。

启动时在后台检查新版，获取中、已是最新版、发现新版或获取失败等结果通过左下角提示显示，发现新版时另外弹窗通知，同一版本仅通知一次，记录在 `HintLauncherReleaseTag` 中。可在“设置 → 其他 → 启动器”关闭“启动时检查新版”。升级后的更新日志窗口、公告设置及其状态记录继续移除。网络失败、API 限流或没有有效发布时，不会将当前版本误判为最新版，也不阻断启动。“查看更新”及其他更新入口统一显示手动更新说明，提供“前往 Releases”和“取消”两个按钮。新版通知仅展示版本号及手动更新步骤，不展示更新日志。用户下载新版后退出启动器，自行替换 EXE；保留 PCL 与游戏文件夹。程序不自动下载、替换 EXE，也不为更新而重启或处理 `--update` 参数。

`SystemLauncherUpdateSource` 控制检查源：`0` 为 GitHub 官方（默认），`1` 为 GH-Proxy 镜像，`2` 为自定义源。自定义地址保存在 `SystemLauncherUpdateCustomSource`，仅在选择自定义时显示输入框。填写完整链接，例如 `https://exmple.com/repos/sparkzure/PCL-Slash/releases?per_page=100`；前缀代理可填写 `https://exmple.com/https://api.github.com/repos/sparkzure/PCL-Slash/releases?per_page=100`。程序直接请求填写的地址，保留路径和查询参数。地址须为有效 HTTP / HTTPS URL，不能包含用户名、密码、片段或占位符；返回数据须为 GitHub Releases 格式的发布对象或发布列表，并按当前通知通道筛选。预发布通道应使用发布列表链接，以便检查同通道版本。检查请求仅使用所选源，错误通过左下角提示及日志报告。

客户端更新通知回归检查（先通过指定 `build.cmd` 构建）：

```text
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/verify-launcher-updates.ps1
```

如果 Bot 使用默认 `GITHUB_TOKEN` 推送标签，通常不会再次触发标签构建流程。需要使用 GitHub App 令牌，或显式派发工作流，并保持草稿由管理员发布的步骤。参见 [GitHub 的工作流触发规则](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)。

## 内置联机功能移除

本分支不再包含联机页面、联机设置、邀请码事件、剪贴板自动加入、EasyTier 模块下载与启动、云端联机配置及相应资源。自定义事件中的 `加入房间`、页面 `Link` 和子页面 `SetupLink` / `LinkMain` 已删除；其余事件和页面的数字编号保持不变，导航按控件的 `Tag` 匹配。

构建后执行 `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/verify-no-link.ps1`，检查联机类型、配置和资源已移除，现有页面编号、设置导航与更新通知仍可用。
