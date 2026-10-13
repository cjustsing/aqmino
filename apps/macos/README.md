# macOS 客户端

首个原生开发预览采用 SwiftUI + AppKit，部署基线 macOS 13。界面遵循用户选定的第 3 套「紧凑秩序」。提醒、记录和目标规则来自本地 `AqminoCore` 包；没有第三方运行时依赖。

首版范围已确认是提醒、快捷记录和今日进度。编码依据为[产品方案](../../docs/product-design.md)、[提醒规则](../../docs/reminder-rules.md)、[交互设计](../../design/macos/interaction-design.md)与[技术设计](../../docs/technical-design.md)。系统通知与登录启动等完整链路仍保留为 M1 验证关口。

## 本机运行

在仓库根目录执行：

```sh
python3 scripts/build-macos.py --open
python3 scripts/check.py
```

构建脚本使用当前 Swift 工具链，输出 `build/macos/Aqmino.app` 并验证本机临时签名；不修改全局开发工具设置。默认 Debug，可用 `--configuration release` 构建优化版本。Bundle ID `local.aqmino.macos` 用于本地开发，分发前填写正式标识和签名身份。

开发预览图标采用用户选定的候选 03。图标源稿与导出命令见[图标说明](../../design/brand/app-icon/README.md)；本地构建与 Xcode 均打包 `Resources/Aqmino.icns`，系统通知使用应用图标。

`check.py` 在完整 Xcode 下执行两个包的标准 XCTest。仅有 Command Line Tools 时使用最小断言桥直接运行同一批测试方法，保留失败退出码；这不表示 XCTest 运行库或 `xcodebuild test` 已通过。

## 已接入的流程

- 菜单栏打开 / 关闭面板，今日累计、三个容量和自定义记录。
- 饮水记录与设置共用窗口；今日、昨日、近 7 / 30 日趋势、日均和按日明细，单条删除与最近一次操作 10 秒撤销。
- 四组设置共用草稿，切换记录和设置保留未保存的编辑，保存统一提交、取消放弃；目标默认关闭。
- 后台提醒到期时菜单栏改为实心水滴加标记；打开应用、记录或稍后提醒后恢复，关闭横幅仍保留标记。标记变化不修改饮水记录或提醒计时。
- 普通本地通知、明确容量的记录动作、10 分钟稍后、暂停、工作时段和达标停止。
- 写入成功后发布 UI；失败保留已确认状态，损坏时由用户明确恢复有效备份。
- 清空记录使用删除意图事务，启动时只继续未完成删除；旧提醒无法重新创建已清空数据。
- 睡眠、会话、时区、日期和系统时间事件接入重新计时，退出前等待当前提交并清理本应用提醒。
- 中英文文案和系统外观；关键控件提供辅助功能名称。
- 主面板右上角「… → 捐赠支持…」和设置侧栏「捐赠支持」打开同一页面，可切换微信 / 支付宝收款码。支持完全自愿，不解锁功能，也不影响使用或后续更新；二维码资源复用 CPaste 的收款码。

通知授权只在开启按钮上请求；首次引导可以跳过。关闭面板不会退出，退出后停止产生新提醒。没有预置目标或演示数据。

面板打开时不默认聚焦「更多」，可用 Tab 进入控件。测试通知的提交 / 失败 / 重试反馈固定显示在设置页底部，使用当前页面的声音选项；每次测试生成独立通知，连续点击会提示剩余等待时间，失败后可立即重试。提交成功表示系统已接受请求，界面不会据此宣称横幅已显示。测试不会改动饮水记录、已保存偏好或正常提醒周期。macOS 在专注模式或屏幕共享时可能把通知静默到通知中心，可在「系统设置 → 通知」检查显示策略。

采用技术设计预留的 `NSStatusItem + NSPopover` 承载 SwiftUI，以公开接口观察前台可见状态和路由窗口。饮水记录与设置的入口定位到同一窗口的相应页面，重复打开聚焦已有窗口。应用活动时可以使用 `⌘⇧D` 打开面板、`⌘⇧R` 打开饮水记录、`⌘,` 打开设置、`⌘W` 关闭当前窗口。记录、设置和捐赠支持页的关闭遵循系统窗口流程，后台提醒继续运行。

菜单栏面板高度随内容变化；常规状态不使用滚动容器，仅内容超出显示空间时滚动。自定义记录与标题同排，暂停、历史和设置共用底部操作区。历史汇总按查看时的本地日历和时区计算，与今日汇总保持一致；近 7 / 30 日包含今日及无记录日，日均按完整范围计算并四舍五入为整数毫升。历史记录未保存当时目标，趋势不展示历史达标率。

## 数据与隔离预览

普通运行通过系统 Application Support API 获取 `Aqmino/` 目录。主文件 `state-v1.json`，备份 `state-backup-v1.json`，未完成清空的意图文件 `delete-intent-v1.json`。时间使用带毫秒的 UTC ISO 8601，另存记录创建时区。未知快照版本停止写入并保留文件。

Debug 可以隔离 UI 检查数据并预览外观：

```sh
open -n build/macos/Aqmino.app --args --data-directory /tmp/aqmino-local-preview --show-panel --preview-appearance light
```

`--preview-appearance` 可取 `light` 或 `dark`；正常运行跟随系统。这两个数据 / 外观选项只用于 Debug，不更改系统设置。隔离目录首次仍为空并显示引导。英文检查可追加 Foundation 启动参数 `-AppleLanguages '(en)'`，不更改系统语言。

## 已建立的目录

```text
macos/
├── README.md
├── Sources/
│   ├── App/                   # 应用入口、场景、依赖组装
│   ├── Features/
│   │   ├── MenuBar/           # 菜单栏入口与轻量面板
│   │   ├── Hydration/         # 饮水记录与今日进度
│   │   ├── Reminders/         # 提醒设置、暂停与稍后提醒的交互
│   │   └── Settings/          # 通用偏好与权限引导
│   ├── Platform/             # macOS 系统能力适配
│   └── UI/                   # 客户端内共用的小组件与样式
├── Resources/                # 应用实际打包的图标、本地化等资源
├── Configuration/            # 后续 xcconfig、entitlements 等
└── Tests/
    ├── Unit/                 # 客户端状态与适配器的单元测试
    └── UI/                   # 菜单栏、记录、设置等关键交互验证
```

未使用目录仍保留 `.gitkeep`。`Aqmino.xcodeproj` 的应用 target 显式绑定 `Sources/`、两种语言的 `InfoPlist.strings`、配置和本地核心包，单元测试 target 绑定 `Tests/Unit/`。

## 编码归属

| 位置 | 放什么 | 边界 |
| --- | --- | --- |
| `Sources/App/` | `AqminoApp.swift`、场景、启动流程、依赖组装 | 负责连接各层，规则进入核心包 |
| `Features/MenuBar/` | 菜单栏图标、面板、下一次提醒与快捷操作 | 从业务状态读取数据 |
| `Features/Hydration/` | 记录入口、今日汇总、记录列表及其状态 | 记录模型和汇总规则来自核心包 |
| `Features/Reminders/` | 工作时段、间隔、暂停、稍后提醒等交互状态 | 下一次提醒的计算来自核心包 |
| `Features/Settings/` | 通用偏好、通知权限引导、登录启动开关 | 通过系统适配器执行系统操作 |
| `Platform/` | 通知、持久化、睡眠/唤醒与时区事件、登录启动 | 实现核心包接口并封装系统 API |
| `UI/` | 多个功能实际共用的组件和样式 | 只提取已经重复的界面元素 |
| `Resources/` | Asset Catalog、本地化、打包所需素材 | 从 `design/` 导出可用资源 |
| `Configuration/` | 各配置的构建设置、权限与签名相关配置 | 不保存私钥、证书或凭据 |

`Platform/` 初期保持一个目录，有实际代码后再按 `Notifications/`、`Persistence/`、`SystemEvents/`、`LaunchAtLogin/` 拆分。每个功能目录内将 View 与状态类型放在一起，复杂后再增加内部层次。

## 工程和核心包

- 应用工程位置：`apps/macos/Aqmino.xcodeproj`，共享 scheme 为 `Aqmino`。
- 核心包位置：`packages/AqminoCore/Package.swift`。
- 从 `apps/macos/` 引用核心包的相对路径为 `../../packages/AqminoCore`。
- 不增加根级 workspace 或第三方工程生成依赖；`scripts/generate-xcode-project.py` 确定性绑定当前文件，新增源文件 / 测试文件后重新执行。
- UI 与应用装配由应用 target 编译，客户端单元测试使用独立 target；原生 UI 测试 target 尚未建立。

## 环境与验证边界

2026-10-10 本机：macOS 26.5.1 / Apple Silicon，Swift 6.2.3，当前开发工具目录 `/Library/Developer/CommandLineTools`。本机没有完整 Xcode。Swift 编译、打包和临时签名已通过，固定输入规则、草稿、存储故障和并发验证通过；原生界面已检查首次跳过通知、快捷 / 自定义记录、容量校验、今日列表、重启保留和四组设置入口。

仍需验证完整 Xcode 工程构建、实际通知授权与拒绝、系统通知动作冷启动、前台横幅抑制、睡眠唤醒、登录启动注册与批准，以及 macOS 13、Intel、VoiceOver 和不同显示缩放。开发目录下登录服务可能尚未被系统识别，界面不会虚报启用。正式签名与公证在后续发布阶段落实。

## 公开开发预览

2026-10-13 首次公开发布 `v0.1.0`（构建 14）。当前下载包为 Apple Silicon（arm64）Release 构建，使用现有本地 Bundle ID 和临时签名，未公证。ZIP、校验文件及构建信息通过 `scripts/package-macos-release.py` 生成，发布方式见 [发布指南](../../docs/releasing.md)。GitHub CI 中的 Swift 包测试不能替代 Xcode 应用工程与真实系统能力验收。

## 官方依据

Apple 的 [MenuBarExtra 文档](https://developer.apple.com/documentation/swiftui/menubarextra)支持菜单栏入口及窗口式面板；[本地 Swift 包组织方式](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages)支持把独立业务模块放在同仓库并由应用工程引用。
