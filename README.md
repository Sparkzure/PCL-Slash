# Plain Craft Launcher Slash

**PCL-Slash** 是基于 [Plain Craft Launcher](https://github.com/Meloong-Git/PCL) 的 Minecraft Java 版启动器，帮助你下载游戏、管理版本和整合包。

## 功能

- **游戏管理**：下载、安装和启动 Minecraft，管理多个游戏版本。
- **资源下载**：查找和下载 Mod、资源包等游戏内容。
- **整合包管理**：导入整合包，也可以将自己的游戏配置导出分享。
- **个性化界面**：默认使用天依蓝主题（#66CCFF），天依蓝与苍绿色分别配有洛天依、初音未来标题栏纹理；支持设置主页、背景图片和背景音乐，解锁 5 个隐藏主题后可使用自定义配色。
- **问题排查**：查看启动日志，分析游戏崩溃原因。

主题设置已采用全新格式，旧版的主题选择、自定义配色和隐藏主题解锁记录不会导入。升级后默认使用天依蓝，自定义配色需重新设置，隐藏主题按彩蛋规则重新解锁。

## 开始使用

运行环境：Windows，需要安装 .NET Framework 4.8。

1. 在[版本发布页面](https://github.com/sparkzure/PCL-Slash/releases)查看可用版本与更新说明。
2. 将下载的文件解压到你希望存放启动器的文件夹，运行 `Plain Craft Launcher Slash.exe`。
3. 添加游戏账号，选择已有游戏目录或下载游戏版本，然后启动游戏。

启动器会在后台检查新版，在左下角显示检查结果，发现新版时弹窗通知，同一版本仅通知一次。Beta 和 Snapshot 分别检查各自通道，也会检查后续正式版。更新时请前往 Releases 下载新版，退出启动器后替换 `Plain Craft Launcher Slash.exe`，并保留原有的 `PCL` 文件夹和游戏文件夹。可以在“设置 → 其他 → 启动器”中点击“查看更新”打开手动更新说明，或关闭“启动时检查新版”。启动器升级后不弹出更新日志。

“更新检查源”可选择 GitHub 官方、GH-Proxy 镜像或自定义源。自定义源填写完整的更新检查链接，例如 `https://exmple.com/repos/sparkzure/PCL-Slash/releases?per_page=100`；前缀代理可填写 `https://exmple.com/https://api.github.com/repos/sparkzure/PCL-Slash/releases?per_page=100`。程序直接请求填写的地址，返回数据须为 GitHub Releases 格式的 JSON。

本分支已移除内置联机功能，包括邀请码、联机模块下载和云端联机配置。

## 帮助与反馈

使用中遇到问题，可以先查看启动器内的“更多 → 帮助”。

如果问题仍未解决，欢迎到 [Issues](https://github.com/sparkzure/PCL-Slash/issues) 反馈。请附上启动器版本、复现步骤和相关日志；提交前请检查日志中是否包含个人信息。功能建议也可以在这里提出。

## 致谢

感谢原版 PCL 的开发者龙腾猫跃、HerobrineXia，以及所有贡献者和社区成员。PCL-Slash 在原项目的基础上开发，原作者署名与第三方组件许可可在启动器的“关于”页面查看。

- [原版 Plain Craft Launcher](https://github.com/Meloong-Git/PCL)
- [原版 PCL 下载](https://meloong.com/pcl)
- [帮助文档库](https://github.com/LTCatt/PCL2Help)
