# 手表截图字体

`MiSansVF.ttf` 提取自小米手表 5（M2505W1）的 `/system/fonts/MiSansVF.ttf`，仅留本地用于自动截图测试，不通过 Flutter assets 打包进应用，也不提交到 Git 或导出到公开源码包。

SHA-256：`0356e26c35740d2f5802f9f0c033a8a1d0baf1c70a12ad42c3d51c3ff7e707e9`。

字体内嵌版权声明：Copyright © 2020-2024 Beijing Xiaomi Mobile Software Co.,Ltd. All Rights Reserved.
字体不适用本项目 MIT 许可证；设备文件没有内嵌许可文本。仓库不提供该字体下载或再分发授权。需要复现实机字体时，请自行确认使用权限并将文件放到此目录；脚本会校验上述 SHA-256。没有本地字体时，脚本下载并校验固定版本的 Noto Sans SC（SIL OFL 1.1），因此公开仓库与 CI 仍可生成截图，效果与实机字体有差异。

手表 `/system/etc/fonts.xml` 的 sans-serif 字重映射：100→150、200→200、300→250、350→305、400→330、500→380、600→450、700→520、800→630、900→700。截图脚本在 `build/screenshots-cache/` 生成适配 Flutter 字重的副本，仓库原始字体保持不变。
