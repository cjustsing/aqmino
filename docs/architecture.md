# 目录与架构规划

日期：2026-10-10。范围：空项目的目录骨架、macOS 编码位置及后续平台扩展方式。

## 依据与范围

用户提供了本地水序项目目录和命名讨论，希望先规划目录，包含 Mac 客户端代码及未来平台。目录最初为空，没有适用的上级 `AGENTS.md`，也没有 Git HEAD 或已有代码约定。

已确认的产品方向：中文名「水序」、Mac 喝水提醒软件、极简精致的 Apple 原生风格、中英文品牌。本项目使用与目录一致的工程名 `Aqmino`。提醒与记录的具体功能、支持版本和发布渠道将在相应编码阶段细化。

本次交付为 Markdown 文档和 `.gitkeep` 目录占位。后续编码以此为布局起点。

## 当前目录树

```text
aqmino/
├── README.md
├── apps/
│   ├── README.md
│   └── macos/
│       ├── README.md
│       ├── Sources/
│       │   ├── App/
│       │   ├── Features/
│       │   │   ├── MenuBar/
│       │   │   ├── Hydration/
│       │   │   ├── Reminders/
│       │   │   └── Settings/
│       │   ├── Platform/
│       │   └── UI/
│       ├── Resources/
│       ├── Configuration/
│       └── Tests/
│           ├── Unit/
│           └── UI/
├── packages/
│   └── AqminoCore/
│       ├── README.md
│       ├── Sources/AqminoCore/
│       │   ├── Models/
│       │   ├── Policies/
│       │   └── Ports/
│       └── Tests/AqminoCoreTests/
├── shared/
│   ├── README.md
│   ├── contracts/
│   └── fixtures/
├── design/
│   ├── README.md
│   ├── brand/
│   └── macos/
├── docs/
│   ├── architecture.md
│   └── roadmap.md
└── scripts/
    └── README.md
```

树中省略了 `.gitkeep`。未来客户端路径见[平台规划](../apps/README.md)，尚未创建。

## 架构选择

采用单仓库管理，各平台保有独立应用工程。macOS 首期使用 SwiftUI 主界面，本地 `AqminoCore` Swift 包集中业务规则，系统能力由客户端实现。

Apple 的 [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)提供菜单栏入口与窗口式面板；[本地 Swift 包](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages)适合在同仓库组织可复用模块。具体 SDK 与最低支持版本在创建工程时固定。

当前只设置一个核心包，便于维护业务边界；UI 保留在各平台内，可随各平台交互方式演进。非 Apple 平台可沿用 `shared/` 中的数据语义与验证样例，语言和框架在立项时选择。

## 依赖与职责

应用 target 引用本地 `AqminoCore` library，核心包不反向引用应用。

| 部分 | 职责 | 依赖方向 |
| --- | --- | --- |
| `App/` | 创建并连接功能状态、核心业务和系统适配器 | 可以组装 `Features`、`Platform`、`AqminoCore` |
| `Features/` | 菜单栏、饮水记录、提醒设置、通用设置 | 使用核心类型与注入的接口，界面共用代码可进入 `UI/` |
| `Platform/` | 通知、持久化、系统事件与登录启动 | 实现所需接口，依赖核心类型和对应系统框架 |
| `AqminoCore/` | 业务模型、汇总、提醒时间与状态规则 | 仅使用标准库、必要的 Foundation 和注入的输入 |
| `shared/` | 可移植的数据契约、输入输出样例 | 不承担运行时依赖组装 |

这些边界初期主要由代码评审维护；`Features`、`Platform` 和 `UI` 是应用 target 内的目录。核心包作为独立模块，由编译依赖确保不会引用客户端源码。

## 关键实现位置

1. 菜单栏入口、设置场景与启动组装放在 `apps/macos/Sources/App/`。
2. 面板和业务操作按功能进入 `Features/`，涉及业务时间或饮水量的判断进入 `AqminoCore/Policies/`。
3. 通知授权与交付、存储、睡眠/唤醒及时区事件处理进入 `Platform/`。系统事件到来后，用新的时间和状态重新计算提醒。
4. 记录和偏好通过核心模型表达；具体持久化格式由适配层管理。
5. 稳定的数据交换格式与跨平台验证样例分别进入 `shared/contracts/` 与 `shared/fixtures/`。

时区、睡眠后提醒、重复通知及权限拒绝需要在提醒功能编码前定义明确行为。规则层便于固定输入验证，系统能力层需在实际 macOS 环境验证。详细实施顺序见[编码路线](roadmap.md)。

## 扩展方式

- iOS / iPadOS：新增 `apps/ios/`，复用适用的核心模型和规则，分别实现通知、存储与生命周期。
- Apple Watch：新增 `apps/watchos/`，先评估独立使用还是伴随使用及后台执行限制。
- Android / Windows / Web：新增各自客户端，沿用数据契约和行为样例，评估技术栈及可用的代码复用方式。
- 云同步：需求确定后再设计身份、数据冲突与服务端协议，并按需要新增 `services/`。

新增平台以首个真实功能需求为触发条件。跨端同步与非 Apple 平台技术栈暂不作为 macOS 开发的前置条件。

## 目录规划验收

| 编号 | 验收标准 | 验证方法 |
| --- | --- | --- |
| AC-01 | 根入口能定位客户端、核心包、共用数据、设计、文档和脚本 | 检查根 README 与目录是否一致，检查本地链接 |
| AC-02 | macOS 代码有应用入口、功能、系统能力、共用 UI、资源、配置和测试位置 | 检查目录及 macOS README 的职责表 |
| AC-03 | 核心包的职责、接口方向和客户端依赖边界明确 | 检查核心包说明与本设计；源码建立后再验证 imports |
| AC-04 | 未来平台有命名与创建规则，区分当前骨架和规划路径 | 检查平台表、实际目录及新增平台步骤 |
| AC-05 | 用户能判断当前尚未进入可构建应用阶段 | 检查 README 状态及工程 / 包清单的标记 |

当前验收覆盖目录和文档。业务功能与构建结果在相应代码阶段提供证据。

本轮检查通过：9 个 Markdown 文件、19 个目录占位、12 个本地文档链接与 21 个预期目录均符合规划；未来平台目录尚未创建，交付文件均处于规划范围。

## 后续关注点

| 编号 | 影响与发现方式 | 处理方式 | 关联 |
| --- | --- | --- | --- |
| RISK-01 | 不同平台的通知与后台限制可能导致提醒行为不同；平台验证时发现 | 客户端各自适配，在新增平台首个功能前验证能力 | AC-02、AC-04 |
| RISK-02 | 核心业务引入 macOS API 会影响 Apple 平台复用；imports 和编译可发现 | 把系统 API 留在 `Platform/`，核心规则接收输入 | AC-03 |
| RISK-03 | 只有目录会被误认作完整工程；启动或构建时暴露 | 各入口标明当前阶段，M1 建工程后再写运行命令 | AC-05 |

这些是后续实现需要验证的事项，不构成目录规划的阻塞。

## 设计交付记录

```yaml
phase: design
mode: standalone
mutation_policy: report_only
artifact_policy: persist
outcome: ready
next_transition: handoff
comparison_base: filesystem:empty
revision_fingerprint: sha256:c54fda493ea908fb04e5e3d7f63f9266aecd63bcb2cd753afedf889b39a6f133
baseline:
  git_repository: false
  head: null
  staging_status: not_applicable
  effective_behavior_files: []
initial_dirty_paths: []
planned_owned_paths:
  - README.md
  - apps/**/README.md
  - apps/macos/**/.gitkeep
  - packages/AqminoCore/README.md
  - packages/AqminoCore/**/.gitkeep
  - shared/**/README.md
  - shared/**/.gitkeep
  - design/**/README.md
  - design/**/.gitkeep
  - docs/architecture.md
  - docs/roadmap.md
  - scripts/README.md
acceptance_criteria: [AC-01, AC-02, AC-03, AC-04, AC-05]
red_evidence:
  applicability: not_required
  reason: 本次为目录与文档规划，无既有缺陷或行为变更
  alternative: 目录结构、本地链接与交付范围检查
risks: [RISK-01, RISK-02, RISK-03]
evidence:
  - 本地目录初始为空，无 Git 仓库或适用的 AGENTS.md
  - 已读取用户引用的命名讨论
  - 已查阅 Apple 菜单栏与本地 Swift 包官方文档
  - 已检查当前 Xcode 选择目录与 Swift 版本
  - 目录、交付范围和本地 Markdown 链接检查通过
user_decisions:
  - 本地项目先做目录规划，覆盖 macOS 与后续平台扩展
open_questions:
  - 创建应用工程时确定最低 macOS 版本与 Bundle ID
  - 发布前确定签名团队与分发渠道
  - 新平台立项时确定技术栈与同步需求
artifact: docs/architecture.md
```

指纹是以下基线输入以 UTF-8 编码后的 SHA-256：`{"comparison_base":"filesystem:empty","deletions":[],"files":[]}`。输入固定键序、无额外空白。初始有效源码树为空；本次 Markdown 与目录占位属于规划产物，不纳入行为文件。未来文件记录应包括路径、模式和内容摘要，并记录删除项及 staged / unstaged 的有效内容。
