# 发布指南

## 当前分发范围

公开仓库为 [cjustsing/aqmino](https://github.com/cjustsing/aqmino)，默认分支为 `main`。首个版本为 `v0.1.0`，按开发预览发布。本次提供 Apple Silicon 的 Release ZIP、本机临时签名和 SHA-256；正式 Developer ID 签名、公证、Intel / Universal 包及完整系统能力验收尚未完成。

版本号来自 `apps/macos/Configuration/Info.plist`：`CFBundleShortVersionString` 为版本，`CFBundleVersion` 为构建号。发布新版本时同时更新版本、构建号和 `CHANGELOG.md`；本机构建与 Xcode 应用工程读取同一份 Info.plist。

## 验证与打包

在干净的源码目录执行根 [README](../README.md) 中的验证命令。现有检查采用临时数据和系统能力替身；真实通知、登录启动和睡眠唤醒仍需实机验收。AppModel 的实时检查避开本地 23:00 至午夜；CI 在该时段临时使用 UTC 避免跨日。

```sh
python3 scripts/build-macos.py --configuration release
python3 scripts/package-macos-release.py
```

构建脚本将许可证与版权声明放入应用资源目录。打包脚本检查 bundle 元数据与源码配置一致，验证签名，识别二进制架构，生成 ZIP 并解压检查全部文件和签名。输出位置：

```text
build/releases/v0.1.0/
├── Aqmino-0.1.0-macos-arm64.zip
├── SHA256SUMS.txt
└── release-info.json
```

生成目录已忽略；发布包作为 GitHub Release 附件上传，不进入源码提交。`release-info.json` 保存版本、构建号、架构、最低系统、Bundle ID、签名方式和安装包校验值。包内容只包含应用及其资源，用户饮水记录和设置保留在系统 Application Support 目录。

## 标签与 GitHub Release

测试通过、源码提交并推送后，在对应提交上创建带说明的标签；同一版本的已公开标签和附件保持不变。Release 说明应包含功能、安装方式、验证结果、架构、签名方式和已知限制。

以下为 `v0.1.0` 的命令示例；后续发布需替换版本和附件路径，发布说明先保存为真实 Markdown 文件。

```sh
git tag -a v0.1.0 -m 'Aqmino 0.1.0 development preview'
git push origin main
git push origin v0.1.0
gh release create v0.1.0 \
  build/releases/v0.1.0/Aqmino-0.1.0-macos-arm64.zip \
  build/releases/v0.1.0/SHA256SUMS.txt \
  build/releases/v0.1.0/release-info.json \
  --repo cjustsing/aqmino \
  --verify-tag \
  --prerelease \
  --title 'Aqmino 0.1.0 · 开发预览' \
  --notes-file build/releases/v0.1.0/release-notes.md
```

上传后核对远端标签、Release 状态、附件名称与 SHA-256。`.github/workflows/ci.yml` 在推送和 Pull Request 时运行 macOS 检查与预览包验证；CI 不自动发布。

## 本机启动版本

本机验收通过后的安装与重启遵循 [AGENTS.md](../AGENTS.md)。正常退出旧进程，备份原安装包，替换 `/Applications/Aqmino.app`，从安装路径启动后核对运行路径、签名和文件一致性；失败时恢复旧包。正常启动不传测试参数，保留现有数据、设置和登录启动配置。
