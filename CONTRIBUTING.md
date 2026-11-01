# 参与开发

先按 [部署说明](docs/setup.md)准备本地配置。常规验证：

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test --exclude-tags=database
python3 -m unittest discover -s test -p '*test*.py'
flutter build apk --release --target-platform android-arm,android-arm64
cd android
./gradlew :app:testDebugUnitTest
```

Python 数据库测试默认跳过；需要显式启用，并使用独立测试库，见部署说明。不要为测试连接他人的数据库。

新功能先通过 issue 讨论设计。修复请说明触发条件、最终行为和必要验证；涉及圆屏视觉时由实机反馈确认，不要求维护者执行长验收流程。当前主要实测设备为小米手表 5，其他设备的反馈请附系统版本和屏幕形状。

表结构源为 `database/schema.sql`，同步维护 skill 的 `references/schema.sql`，通过增量迁移保留数据。不要在应用启动时建表或插入演示任务。修改专注计时、勿扰所有权或表冠触感时，遵守 [AGENTS.md](AGENTS.md) 中的适配约定。

请勿提交数据库连接配置、证书、密钥、任务数据、日志或安装包。源码导出与检查见 [README](README.md)。提交代码和素材时，请确认有权按本项目 MIT 许可证贡献，并保留第三方许可声明。
