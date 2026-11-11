# 自动更新手表 UI 截图

在项目根目录运行：

```bash
python3 scripts/capture_watch_ui.py
# Flutter 不在 PATH 时：
python3 scripts/capture_watch_ui.py --flutter /path/to/flutter
```

需要 Python 3.10+ 和项目锁定的 Flutter 3.47.8；建议在 Linux 上生成，以减少跨平台渲染差异。先安装截图工具依赖（可在 Python 虚拟环境内执行）：

```bash
python3 -m pip install -r scripts/requirements-screenshots.txt
```

本地截图优先使用自行准备的 `test/screenshots/fonts/MiSansVF.ttf`，取自小米手表 5（M2505W1）的 `/system/fonts/MiSansVF.ttf`，校验固定 SHA-256。该文件仅留本地，由 Git 忽略并从公开源码包排除，仓库不提供字体文件或再分发授权。缺少本地字体时，脚本下载固定版本的 Noto Sans SC 到构建缓存并校验 SHA-256，其许可见 [NotoSansSC-OFL.txt](licenses/NotoSansSC-OFL.txt)。公开仓库和 CI 使用此替代字体，效果与实机有差异；生成清单记录实际使用的字体。脚本通过 fontTools 在构建缓存中生成字重映射版本：将 Flutter 的 100–900 字重映射到手表系统配置的 150–700 轴值，例如 400→330、500→380、700→520。原始字体保持不变，不打包进应用。字体相同仍不代表渲染引擎、系统缩放等与实机完全一致。

截图测试将所选字体注册为 Android 主题使用的 `Roboto`，并显式加载应用的 `MaterialIcons` 图标字体。时间轴刻度和弧形时钟的 `TextPainter` 继承主题字体，避免落入测试引擎内置的 Ahem 方块字体；仅以同名加载字体不能覆盖内置 Ahem。

按钮和通知条的独立文字样式也显式指定 `Roboto`，避免覆盖主题样式时丢失字体。每张截图捕获前会检查渲染文字的有效字体族；出现未加载的字体或未指定字体时，生成失败并保留已有图片，不将文件和尺寸检查通过视为字体正确。

脚本使用实际 `MyApp` 主题和页面组件，在 Flutter 测试引擎中依次打开下列页面和状态，捕获 240×240 逻辑像素、2 倍像素比的圆屏。最终生成 23 张 480×480 PNG，而非真实手表系统截图；系统权限弹窗和系统栏不在捕获范围。

覆盖清单：

- 生活首页、工作首页、空任务、日期日历、任务详情、任务编辑、工作完成记录。
- 关联任务专注设置、自由专注设置、选择关联任务、专注运行/暂停/结束、休息运行/结束。
- 专注分析（工作、生活、休息演示记录）、空分析。
- 工作提醒已关闭/已开启、休息提醒、提醒时段、提醒间隔转盘、自动关闭时间转盘。

这是明确列举的页面与状态集，不自动遍历所有弹窗或滚动位置。长工作设置页额外捕获提醒区和时段区。

截图使用独立的 `test/screenshots/demo_data.dart`，包含整理书桌、阅读、散步和项目进度等日常例子，不使用通用测试中的“街头观察”任务。修改截图演示数据不会修改个人任务或数据库。

数据来自测试替身，日期固定为 2026-11-01，共享时钟固定为北京时间 10:08，专注状态由模拟计时引擎推进。不会读取个人任务、连接 MySQL、调用原生计时/勿扰或安装到设备。已有数据库配置保持原样；源码刚下载、缺少 Flutter 声明的配置资源时，仅临时创建示例资源并在退出时清理。

输出到 `docs/screenshots/`，附带尺寸、时间、字体和图片 SHA-256 清单。全部页面捕获成功并通过文件检查后，才替换图片并更新 README 的 `BEGIN WATCH SCREENSHOTS` / `END WATCH SCREENSHOTS` 标记区块，保留区块之外的文字。图片不会由脚本自动做视觉验收。

GitHub CI 也会运行同一命令，上传包含 README 和图片的 `watch-ui-docs` 产物，保留 14 天；CI 不自动提交文件到仓库。本地运行后，将 README 和 `docs/screenshots/` 一起提交即可。

修改任务样例或捕获状态时，维护 `test/screenshots/watch_screenshots_test.dart`；增加页面时，同时维护 Python 脚本中的页面清单。共享时钟位于 `lib/widgets/app_clock.dart`，实际运行仍默认使用系统时间。

普通 `flutter test` 会跳过截图生成入口，避免日常回归覆盖文档图片。生成命令会显式启用该入口，并检查目标页面和关键状态。
