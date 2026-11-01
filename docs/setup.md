# 从零部署

## 环境与范围

- 本项目验证环境：Flutter 3.47.8 / Dart 3.13.7、JDK 21、Android SDK；Flutter 版本在 CI 中固定。
- Python 3.10+、OpenSSL；MySQL 8.x 是建议部署目标，其他数据库兼容性未作承诺。
- 手表、手机、运行 Hermes 的机器必须能够访问你自己的数据库地址。不要给使用者共用项目作者的数据库。
- 当前只支持 Android；`web/` 是 Flutter 模板遗留文件，不是可运行的 Web 客户端。

## 1. 准备数据库和 TLS

在自己的 MySQL 服务器上启用 TLS，准备服务器叶证书。可以使用自己的 CA，也可以使用 MySQL 生成的服务器证书；连接时始终固定叶证书 SHA-256 指纹。私钥仅存放于数据库服务器，不复制进项目。

用数据库管理账户创建专用库，然后导入表结构。以下 `mysql -p` 会交互询问密码，勿把实际密码写进命令行：

```bash
mysql -u root -p -e 'CREATE DATABASE life_assistant CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;'
mysql -u root -p life_assistant < database/schema.sql
```

创建一个仅供此应用使用的账户。通过数据库管理工具设置自己的强密码，将允许连接的来源限制为实际设备或 VPN 网段，并要求 TLS。运行账户所需权限示意：

```sql
-- 先创建账户；app_source 替换为实际允许的客户端来源。
GRANT SELECT, INSERT, UPDATE ON life_assistant.* TO 'life_assistant'@'app_source';
ALTER USER 'life_assistant'@'app_source' REQUIRE SSL;
```

数据库初始化、迁移另用具有 `CREATE` / `ALTER` 权限的管理账户；数据库集成测试使用独立测试库，另需 `DELETE` 权限。不要给设备上的运行账户授予全局管理权限。

## 2. 创建本地配置

在项目根目录运行：

```bash
python3 scripts/configure.py init
```

该命令从公开模板创建 `config/database.json` 和 `skills/dayflow/connection.json`，不会覆盖已有文件。编辑 `host`、`port`、`user`、`password`、`database` 和 `certificateSha256`。两份配置指向同一个数据库及证书，账户可以不同。

通过可信渠道取得服务器叶证书，保存为 `skills/dayflow/mysql-server.pem`，然后生成指纹：

```bash
openssl x509 -in skills/dayflow/mysql-server.pem -outform DER | openssl dgst -sha256
```

把输出的 64 位小写十六进制写入两份配置的 `certificateSha256`，不要包含前缀、空格或冒号。Flutter 应用直接使用指纹，不需要额外打包 PEM；Hermes 需要证书文件及相同的指纹。

```bash
python3 scripts/configure.py check
# 安装 Hermes 时，还检查 skill 配置与 PEM 指纹是否一致：
python3 scripts/configure.py check --skill
```

检查在本地离线完成，不打印密码、不连接数据库，也不证明服务器可访问或证书仍在有效期内；运行时 TLS 握手继续进行证书校验。CI 的 `--allow-example` 只允许占位符通过离线构建检查，不用于实际部署。

## 3. 构建和安装

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test --exclude-tags=database
flutter build apk --release --target-platform android-arm,android-arm64
```

APK 位于 `build/app/outputs/flutter-apk/app-release.apk`。小米手表 5 需要 `armeabi-v7a`，不要只构建 arm64。该 APK 包含自己的数据库配置，不要公开分发。现有 release 配置仍使用本机 debug 签名，供个人自行构建；构建模式是 release，签名身份仍是 debug。公共 APK 发布需要另行配置长期保管的正式签名。

使用 `adb devices` 查设备地址，再执行：

```bash
adb -s <设备地址> install -r build/app/outputs/flutter-apk/app-release.apk
```

手机使用同一安装包，按设备形状切换为矩形管理界面。手表和手机访问同一库即共享数据。

授予通知及闹钟/提醒权限。小米手表 5 的当前实测系统缺少标准勿扰授权页，需要一次 ADB 授权：

```bash
adb -s <设备地址> shell cmd notification allow_dnd com.example.life_assistant
adb -s <设备地址> shell pm grant com.example.life_assistant android.permission.WRITE_SECURE_SETTINGS
```

第一条授予 App 勿扰规则权限，第二条仅供小米手机勿扰联动；授权本身不打开勿扰。其他 Android 设备按系统提供的权限页面处理，不承诺小米手机联动可用。改变包名后需同步调整授权命令；改变签名可能影响覆盖安装，先安排数据迁移。

## 4. Hermes skill（可选）

无需 Hermes 也能使用手表及手机。要使用 skill，先配置两端指向同库，保留自己的 `connection.json` 和 `mysql-server.pem`。

```bash
python3 -m venv skills/dayflow/.venv
skills/dayflow/.venv/bin/pip install -r skills/dayflow/requirements.txt
skills/dayflow/.venv/bin/python skills/dayflow/scripts/tasks.py list
```

把 `skills/dayflow/` 复制到运行 Hermes 的账户的 `~/.hermes/skills/dayflow/`，包含 `SKILL.md`、`requirements.txt`、`connection.json`、`mysql-server.pem`、`scripts/` 和 `references/`；排除 `.venv` 和 `__pycache__`，在目标机器重新安装依赖。目标应为真实目录，并由运行 Hermes 的账户持有和读取，不使用指向不可访问项目路径的软链接。复制后在新 Hermes 会话使用 `/dayflow`。

数据库管理员也可用 skill 的 `init` 创建缺失表及增量补列，执行前需配置管理账户。初始化后改回运行账户，不把管理凭据打入 APK。应用启动不会建表或写入演示任务。

## 5. 已有数据库升级

先备份自己的数据库，再以具备 `ALTER` 权限的账户配置 skill，执行：

```bash
skills/dayflow/.venv/bin/python scripts/migrate_database.py
```

只添加缺失的 v2/v3 字段，不覆盖历史记录。对应 SQL 位于 `database/migrations/`；结构源为 `database/schema.sql`，skill 的 `references/schema.sql` 应与它一致。

安排日期固定按 `Asia/Shanghai`，数据库时间戳用 UTC；目前没有时区设置。

## 6. 验证

不访问数据库的检查：

```bash
python3 -m unittest discover -s test -p '*test*.py'
flutter analyze
flutter test --exclude-tags=database
cd android
./gradlew :app:testDebugUnitTest
```

上述检查不会连接业务数据库；首次构建和原生测试仍需联网下载依赖，包括 Robolectric 的 Android 测试运行库。

数据库测试必须使用独立测试库：修改两份本地配置指向该库、导入表结构并授予测试账户读写及删除权限后，在项目根目录显式运行：

```bash
flutter test test/mysql_integration_test.dart --dart-define=RUN_DATABASE_TEST=true
RUN_DATABASE_TEST=true skills/dayflow/.venv/bin/python -m unittest discover -s test -p skill_integration_test.py
```

Flutter 测试使用随机 ID 并清理测试记录；Python 测试回滚事务。不过按日期生成快照的查询也可能涉及库内其他任务，因此不要把日常数据所在库作为测试库。
