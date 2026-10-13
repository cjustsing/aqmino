# 开发与发布脚本

从仓库根目录运行，无需第三方 Python 库：

| 命令 | 用途 |
| --- | --- |
| `python3 scripts/build-macos.py --open` | Swift 构建、打包、临时签名并打开 macOS 客户端 |
| `python3 scripts/check.py` | 有 Xcode 时用 XCTest；CLT 下直接运行同一测试方法 |
| `python3 scripts/check-app-model.py` | 直接运行 AppModel 冷启动、动作队列、保存重试及退出回归；系统适配器使用测试替身 |
| `python3 scripts/check-schedule-recovery.py` | 使用真实系统事件观察器与计时器，验证重启、唤醒、校时和恢复期间的旧回调；通知与登录项使用测试替身 |
| `python3 scripts/check-login-item.py` | 用系统 API 替身验证实际登录启动控制器的首次注册、重复操作、系统批准与失败状态，不更改本机登录项 |
| `python3 scripts/check-settings-view.py` | 在隐藏窗口中验证真实 SwiftUI 设置草稿在首次读取和备份恢复后同步，保留加载后的用户编辑 |
| `python3 scripts/check-window-commands.py` | 用实际应用菜单和隐藏窗口验证 Cmd+W 的键绑定、标准关闭委托与关闭后继续运行；通知等系统能力使用替身 |
| `python3 scripts/check-menu-panel.py` | 在隐藏窗口中测量开启目标及撤销反馈的真实主面板，验证常规状态不超过原面板高度 |
| `python3 scripts/generate-xcode-project.py` | 将源码、资源、测试和本地包绑定到 Xcode 工程 |
| `python3 scripts/export-macos-icon.py` | 用 macOS 自带的 sips / iconutil 从方形源稿导出含 1× / 2× 尺寸的应用图标 |
| `python3 scripts/package-macos-release.py` | 将已构建并验证的应用打包为 ZIP，核对解压内容和签名，生成 SHA-256 与构建信息 |

构建输出位于根目录 `build/`，SwiftPM 缓存位于各包 `.build/`，均被 Git 忽略。`StandaloneTestSupport.swift` 只用于缺少 XCTest 时的验证，不加入应用 target。

本机更新规则见 [AGENTS.md](../AGENTS.md)：新版本通过本轮验收后，先准备签名验证通过的完整 `build/macos/Aqmino.app`，正常退出旧进程，再覆盖安装到 `/Applications/Aqmino.app` 并从安装路径重启。替换失败时恢复旧包；重启后核对运行路径和程序一致性。用户数据目录与登录启动配置保持原样。`--open` 只打开构建产物，不能替代验收后的安装和重启。

AppModel 检查使用临时数据目录，不读写正常使用的饮水记录、不提交系统通知，也不更改通知或登录启动权限。它单独编译实际 AppModel 与文件协调器；测试替身和独立运行入口不加入应用或 XCTest target。当前场景用执行时刻检查十分钟稍后提醒及四十五分钟完整间隔，运行时应避开本地 23:00 至午夜；跨日、DST 和时段边界由核心固定输入测试覆盖。这些检查不能替代真实通知动作、睡眠唤醒和登录启动验收。

提醒恢复检查同样使用临时数据。它向本进程的 Foundation / NSWorkspace 通知中心投递事件，检查真实观察器与计时器的接线、启动时能力查询竞争，以及刚错过的提醒不补发；不调整本机时钟或让 Mac 进入睡眠。测试入口不加入应用 target，设备实际睡眠恢复仍属于发布时的系统实测。

设置界面检查使用实际 SwiftUI View、AppModel 和文件存储，创建但不显示窗口，运行期间应用不能激活。通知、登录项、计时器与系统事件使用相同测试替身；全部数据位于临时目录，完成后清理。它是直接断言检查，不能替代 XCTest 或真实前台交互验收。

菜单栏面板检查同样使用隔离数据与系统能力替身。优化前开启目标时内容为 543 pt，带撤销反馈时为 576 pt，均超出原 528 pt 容器；同一检查在优化后分别测得 435 pt 和 465 pt。AppModel 检查同时覆盖提醒标记、通知动作、横幅关闭、保存失败与迟到回调；核心检查覆盖历史范围、零记录日、时区、DST 以及历史删除和撤销。

开发预览发布先运行 `python3 scripts/build-macos.py --configuration release`，再运行 `python3 scripts/package-macos-release.py`。输出在 `build/releases/v<版本>/`，按实际可执行文件架构命名；当前使用本机临时签名，未公证。发布步骤见 [发布指南](../docs/releasing.md)。正式 Developer ID 签名、公证和归档流程在确定签名身份后补充。

脚本应能从仓库根目录运行，明确依赖、参数、输出和失败状态。构建产物进入忽略目录，签名凭据由本地安全存储或 CI 提供。代码阶段创建 `.gitignore` 时同时登记生成目录。
