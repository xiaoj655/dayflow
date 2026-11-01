# Third-party notices

Dayflow 的代码、文档及项目原创图标采用 [MIT License](LICENSE)。图标由项目作者自行制作或通过 AI 生成，未引入第三方图标素材。

第三方依赖保留各自的版权及许可证，不因本项目采用 MIT 而改变。直接依赖的许可原文保存在 `docs/licenses/`：

| 依赖 | 许可 | 原文 |
| --- | --- | --- |
| mysql_client_plus 0.1.3 | BSD-3-Clause | [LICENSE](docs/licenses/mysql_client_plus.txt) |
| shared_preferences 2.5.6 | BSD-3-Clause | [LICENSE](docs/licenses/shared_preferences.txt) |
| crypto 3.0.7 | BSD-3-Clause | [LICENSE](docs/licenses/crypto.txt) |
| flutter_launcher_icons 0.14.4（开发工具） | MIT | [LICENSE](docs/licenses/flutter_launcher_icons.txt) |
| PyMySQL（Hermes skill） | MIT | [LICENSE](docs/licenses/PyMySQL.txt) |
| Gradle wrapper 9.3.1（仓库内构建工具） | Apache-2.0 | [LICENSE](docs/licenses/gradle-wrapper-LICENSE.txt)、[NOTICE](docs/licenses/gradle-wrapper-NOTICE.txt) |
| Noto Sans SC（文档截图字体，仅下载到本地构建缓存） | SIL OFL 1.1 | [LICENSE](docs/licenses/NotoSansSC-OFL.txt) |

Flutter SDK、Material Icons、Gradle wrapper、Android 库及 Dart 间接依赖遵循各自的许可。上述表格是直接依赖清单，并非所有二进制组成部分的完整清单。Dart 依赖版本见 `pubspec.lock`；Python 依赖范围见 `skills/dayflow/requirements.txt`。升级依赖时需同步复核许可。

Flutter 构建会收集 Dart 包的 LICENSE 文件到应用的许可资源中。若将来发布 APK，还需核对实际 APK 中的许可资源，并补齐 Android 原生依赖和 SDK 的再分发声明；本次源码发布不提供公共 APK。
