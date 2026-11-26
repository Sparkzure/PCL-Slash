# Minecraft 版本分类图标

| 资源 | 分类 | 图案与来源 |
| --- | --- | --- |
| `Release.png` | 正式版 | Minecraft Java Edition 草方块图标 |
| `Snapshot.png` | 预览版、快照 | Minecraft Java Edition 泥土块图标 |
| `Old.png` | 远古版 | 参考同套图标风格，由内置 image_gen 生成的圆石块 |
| `AprilFools.png` | 愚人节版 | 参考同套图标风格，由内置 image_gen 生成的菌丝块 |

草方块、泥土块基于 Minecraft 1.21.4 客户端图标，原图取自公开资源镜像的 [正式版图标](https://raw.githubusercontent.com/InventivetalentDev/minecraft-assets/1.21.4/assets/icons/icon_256x256.png) 和 [快照图标](https://raw.githubusercontent.com/InventivetalentDev/minecraft-assets/1.21.4/assets/icons/snapshot/icon_256x256.png)。同款图标亦见 [Wiki 草方块](https://zh.minecraft.wiki/images/thumb/Java_Edition_icon_2.png/240px-Java_Edition_icon_2.png?84f96) 与 [Wiki 泥土块](https://zh.minecraft.wiki/images/thumb/Java_Edition_snapshot_icon.png/240px-Java_Edition_snapshot_icon.png?1ed04)。

生成图标参考了 Minecraft 官方 [Our icons are changing](https://www.minecraft.net/en-us/article/our-icons-are-changing) 中新 Java 图标的等距透视、粗像素纹理和三面明暗，生成与超分使用内置 image_gen。最终运行资源通过高质量重采样缩小为 **64×64 透明 PNG**，与原有 `Images/Blocks/` 分类图标的尺寸一致。

四张图标统一主体占位与透明留白：以半透明度阈值衡量，主体均为 **58×64**，水平居中，两侧各留约 3 像素，与原有分类图标一致。该调整仅作用于图片资源。

这些资源用于已安装版本和下载列表的自动分类图标。手动选择的实例图标及原有 `Images/Blocks/` 资源保持各自用途。
