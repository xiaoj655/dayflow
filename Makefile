# Dayflow 常用快捷指令。直接运行 `make` 或 `make help` 查看说明。
# 变量可在命令行覆盖，例如：make deploy DEVICE=<adb 序列号>

SHELL := /bin/bash
.DEFAULT_GOAL := help

PYTHON ?= python3
FLUTTER ?= flutter
DART ?= dart
ADB ?= adb
DEVICE ?=
PACKAGE ?= com.example.life_assistant
TARGETS ?= android-arm,android-arm64
APK ?= build/app/outputs/flutter-apk/app-release.apk

ADB_FLAGS := $(if $(DEVICE), -s $(DEVICE))

# 共享服务器安装 dayflow-build.slice 后自动套用内存限制；其他环境直接构建。
# 需要临时绕过时使用 `make build BUILD_WRAPPER=`。
BUILD_WRAPPER :=
ifneq ($(wildcard /etc/systemd/system/dayflow-build.slice),)
BUILD_WRAPPER := bash scripts/run_build.sh
endif

# 多条指令共用构建目录，禁用 -j 并发。
.NOTPARALLEL:

.PHONY: help init config config-skill deps analyze test test-py test-native \
	check build build-debug install deploy devices grant migrate icons \
	screenshots screenshots-deps export export-check clean

help: ## 显示可用指令
	@echo 'Dayflow 常用指令（make <目标>）：'
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_.-]+:.*## / {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo '变量示例：make deploy DEVICE=<adb 序列号>；make migrate PYTHON=.venv/bin/python'

init: ## 创建本地配置（已存在则保留）
	$(PYTHON) scripts/configure.py init

config: ## 离线检查应用配置
	$(PYTHON) scripts/configure.py check

config-skill: ## 离线检查应用与 Hermes skill 配置
	$(PYTHON) scripts/configure.py check --skill

deps: ## 按锁文件安装 Flutter 依赖
	$(FLUTTER) pub get --enforce-lockfile

analyze: deps ## 静态检查
	$(FLUTTER) analyze

test: deps ## Flutter 单元测试（跳过数据库）
	$(FLUTTER) test --exclude-tags=database

test-py: ## Python 离线测试（跳过数据库）
	$(PYTHON) -m unittest discover -s test -p '*test*.py'

test-native: ## Android 原生计时与勿扰测试
	cd android && ./gradlew :app:testDebugUnitTest

check: deps analyze test test-py ## 常规离线回归

build: ## 构建 release APK（arm + arm64）
	$(BUILD_WRAPPER) $(FLUTTER) build apk --release --target-platform $(TARGETS)

build-debug: ## 构建 debug APK（arm + arm64）
	$(BUILD_WRAPPER) $(FLUTTER) build apk --debug --target-platform $(TARGETS)

install: ## 安装已构建的 APK，不重新构建
	@test -f $(APK) || { echo '未找到 $(APK)，先执行 make build。' >&2; exit 1; }
	$(ADB)$(ADB_FLAGS) install -r $(APK)

deploy: build install ## 构建并安装 release APK

devices: ## 列出 adb 设备
	$(ADB) devices -l

grant: ## 一次性授予勿扰规则与安全设置权限
	$(ADB)$(ADB_FLAGS) shell cmd notification allow_dnd $(PACKAGE)
	$(ADB)$(ADB_FLAGS) shell pm grant $(PACKAGE) android.permission.WRITE_SECURE_SETTINGS

migrate: ## 增量升级已有数据库（需 PyMySQL）
	$(PYTHON) scripts/migrate_database.py

icons: ## 由 dayflow-icon.png 重新生成应用图标
	$(DART) run flutter_launcher_icons

screenshots: ## 渲染手表截图并更新 README
	$(PYTHON) scripts/capture_watch_ui.py --flutter $(FLUTTER)

screenshots-deps: ## 安装截图所需的 Python 依赖
	$(PYTHON) -m pip install -r scripts/requirements-screenshots.txt

export-check: ## 检查公开源码清单，不写压缩包
	$(PYTHON) scripts/export_source.py --check

export: export-check ## 导出公开源码到 build/dayflow-source.zip
	$(PYTHON) scripts/export_source.py

clean: ## 清理 Flutter 构建产物
	$(FLUTTER) clean
