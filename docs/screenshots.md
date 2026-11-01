# 自动更新手表 UI 截图

在项目根目录运行：

```bash
python3 scripts/capture_watch_ui.py
# Flutter 不在 PATH 时：
python3 scripts/capture_watch_ui.py --flutter /path/to/flutter
```

需要 Python 3.10+ 和项目锁定的 Flutter 3.47.8；建议在 Linux 上生成，以减少跨平台字体渲染差异。首次执行会从 Google Fonts 下载 Noto Sans SC 到 `build/screenshots-cache/`，校验固定 SHA-256；以后复用缓存。字体不打包进应用或源码包，其许可见 [NotoSansSC-OFL.txt](licenses/NotoSansSC-OFL.txt)。字体版本固定在 [Google Fonts 的源提交](https://github.com/google/fonts/tree/a85815a42757630ce188fdad368c2dfc444d4773/ofl/notosanssc)。

脚本使用实际 `MyApp` 主题和页面组件，在 Flutter 测试引擎中依次打开任务首页、日历、任务详情、专注设置、专注计时和专注结束页，捕获 240×240 逻辑像素、2 倍像素比的圆屏。最终生成六张 480×480 PNG，而非真实手表系统截图；厂商字体、系统权限弹窗和系统栏不在捕获范围。

数据来自测试替身，日期固定为 2026-11-01，顶部时间固定为北京时间 10:08，专注状态由模拟计时引擎推进。不会读取个人任务、连接 MySQL、调用原生计时/勿扰或安装到设备。已有数据库配置保持原样；源码刚下载、缺少 Flutter 声明的配置资源时，仅临时创建示例资源并在退出时清理。

输出到 `docs/screenshots/`，附带尺寸、时间、字体和图片 SHA-256 清单。全部页面捕获成功并通过文件检查后，才替换图片并更新 README 的 `BEGIN WATCH SCREENSHOTS` / `END WATCH SCREENSHOTS` 标记区块，保留区块之外的文字。图片不会由脚本自动做视觉验收。

GitHub CI 也会运行同一命令，上传包含 README 和图片的 `watch-ui-docs` 产物，保留 14 天；CI 不自动提交文件到仓库。本地运行后，将 README 和 `docs/screenshots/` 一起提交即可。

修改任务样例或捕获状态时，维护 `test/screenshots/watch_screenshots_test.dart`；增加页面时，同时维护 Python 脚本中的页面清单。共享时钟位于 `lib/widgets/app_clock.dart`，实际运行仍默认使用系统时间。

普通 `flutter test` 会跳过截图生成入口，避免日常回归覆盖文档图片。生成命令会显式启用该入口，并检查目标页面和关键状态。
