# Rhythm

macOS 菜单栏 + 桌面挂件循环计时器：工作/休息循环，支持生效时段、系统通知、全局快捷键跳过休息。

- 部署目标：macOS 27
- 语言：Swift 5（SwiftUI + AppKit + WidgetKit + UserNotifications）
- 唯一第三方依赖：`KeyboardShortcuts`

## 工程结构

```
Rhythm.xcodeproj          单一 Xcode 工程（3 个 target）
Rhythm/                   主 App（菜单栏常驻，LSUIElement=true）
  Engine/                 ScheduleEngine（时段判定）、TimerEngine（状态机）
  UI/                     菜单栏、设置窗口、快捷键录制
  Services/               通知、时钟/唤醒监听、开机自启
RhythmWidget/             WidgetKit 挂件（small / medium）
Shared/                   App 与挂件共用的 Codable 模型 + App Group 存储
RhythmTests/              纯逻辑单元测试（注入 Calendar，无需宿主 App）
```

## 构建与测试

```sh
xcodebuild build -project Rhythm.xcodeproj -scheme Rhythm -destination 'platform=macOS'
xcodebuild build -project Rhythm.xcodeproj -scheme RhythmWidget -destination 'platform=macOS'
xcodebuild test  -project Rhythm.xcodeproj -scheme Rhythm -destination 'platform=macOS'
```

## 签名与 App Group（重要）

- 默认采用**临时签名（ad-hoc，`CODE_SIGN_IDENTITY = "-"`）**，无需开发者账号即可开箱构建、运行，菜单栏倒计时与**系统通知均正常工作**。
  > 注意：系统通知要求 App Bundle 被完整签名并密封。若用 `CODE_SIGNING_ALLOWED = NO` 构建，二进制只有链接器签名、Bundle 未密封，`UNUserNotificationCenter` 授权会静默失败、不会弹通知。
- App 与挂件通过 App Group `group.com.rhythm.app` 共享设置与实时快照（`Shared/SharedStore.swift`）。**App Group 能力默认未启用**，因为受限 entitlement 会强制要求配置签名描述文件（Provisioning Profile），而本机/个人团队通常不具备。未启用时挂件降级（只显示最后状态），主 App 全功能不受影响。
- 两份 entitlements 文件已保留：`Rhythm/Rhythm.entitlements`、`RhythmWidget/RhythmWidget.entitlements`。**启用挂件实时数据的步骤：**
  1. 在 Xcode 为 `Rhythm`、`RhythmWidget` 两个 target 选择你的 Team，并改为 “Automatically manage signing”。
  2. 在 Build Settings 里把两个 target 的 `Code Signing Entitlements` 分别指向上面的两个文件。
  3. 确认两个 target 都声明了 App Group `group.com.rhythm.app`，重新运行 App。
- 若个人团队仍无法使用 App Group，则按计划 §8 降级。

## 行为说明

- 计时以绝对时间戳（`phaseEnd`）计算，休眠/唤醒/系统时钟跳变后依然正确。
- 处于时段内启动或跨越时段起点进入新时段时，**从当前时刻重启完整工作循环**（不做网格锚定）。
- 时段外显示“未启用”，并自动等待下一个时段；可在菜单栏“临时启动”一次不受时段约束的循环。
- 调休 / 节假日逻辑本期不实现，仅按“每周哪几天”判断。
- App 退出后快照不再更新，挂件显示最后一次状态。
