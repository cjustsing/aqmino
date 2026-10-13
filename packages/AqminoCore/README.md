# AqminoCore

本地 Swift library package，现已供 macOS 客户端使用，后续可供 iOS / iPadOS 等 Apple 客户端复用。仅依赖 Foundation，包含记录、偏好、快照、今日汇总、提醒计划和业务命令。

从仓库根目录执行 `swift build --package-path packages/AqminoCore`。完整 Xcode 环境执行 `swift test --package-path packages/AqminoCore`；仅有 Command Line Tools 时使用 `python3 scripts/check.py` 运行同一批规则与存储测试。

## 目录与职责

```text
AqminoCore/
├── README.md
├── Sources/AqminoCore/
│   ├── Models/                # 饮水记录、偏好、提醒状态等业务类型
│   ├── Policies/              # 汇总、提醒计算、暂停与稍后提醒规则
│   └── Ports/                 # 规则所需的时间与存储等接口
└── Tests/AqminoCoreTests/      # 业务规则测试
```

从一个 library target 开始。`Models`、`Policies`、`Ports` 是同一个模块内的目录，不是三个包或三个 target。

## 依赖边界

- 初期仅依赖 Swift 标准库与必要的 Foundation 类型，保持平台无关的业务逻辑。
- 不导入 SwiftUI、AppKit、UIKit、UserNotifications、SwiftData 或其他系统 UI / 存储框架。
- 不读取全局系统时间、不直接申请权限、不注册系统定时器。规则接收明确的时间、时区与状态输入，返回计算结果。
- 只为已有调用需要定义接口。系统通知的交付与平台事件由客户端负责；存储等真正需要替换的能力通过 `Ports/` 接入。
- 核心包不依赖任何 `apps/` 下的文件，也不持有 View 或客户端状态类型。

## 预期验证重点

已经提供固定时间验证：饮水量累加、工作时段边界、暂停与稍后提醒、跨日及日光节约时间、睡眠后重新计算提醒、动作去重与撤销。测试时钟与时区由输入指定，不依赖运行机器当前时刻。

模型或规则稳定后再评估进一步拆包。若未来增加非 Apple 客户端，先按 `shared/` 约定对齐行为；是否复用 Swift 实现需要单独验证各平台工具链与维护成本。

Swift 包采用标准 `Sources/<Target>` 和 `Tests/<TestTarget>` 布局，参见 Apple 的[独立 Swift 包说明](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode)。
