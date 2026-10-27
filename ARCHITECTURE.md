# mmTV Remote 架构设计

## 设计目标

应用应当足够小、可靠，并能独立于 mmTV 运行。第一版采用单一原生 macOS 菜单栏 App，而不是“配置 App + 后台守护进程 + 驱动”三层结构。窗口关闭后 App 继续驻留；登录启动由系统 `SMAppService.mainApp` 管理。

## 运行链路

```text
RC003 / 其他遥控器
        │ 原始 HID usage
        ▼
Device Adapter ── 完整 Report 解析与按键状态差分
        │ 标准 RemoteEvent
        ▼
Device Key Remapper ── 设备级 hidutil 映射与 CGEventTap 中转
        │
        ▼
Gesture Engine ── 去抖、单击、长按、双击与重复策略
        ├─ 语音键 → Voice Input Provider → Typeless / macOS 系统听写 / 关闭
        │
        ▼
Frontmost App Monitor ── Bundle Identifier
        │
        ▼
Profile Resolver ── 用户覆盖 > 内置应用 Profile > 默认 Profile
        │ RemoteAction
        ▼
Action Executor
  ├─ CGEvent 键盘／快捷键
  ├─ CoreAudio 音量
  ├─ 媒体键／系统动作
  └─ App Adapter（仅在普通按键不足时使用）
```

## 模块

### `DeviceKit`

- 使用 `IOHIDManager` 按 VID/PID 精确匹配设备。
- 把设备专属 usage 转换为稳定的 `RemoteEvent`。
- 首个 `RC003Adapter` 复用 mmTV 已验证映射；例如三横线菜单键是 Keyboard usage `0x65`。
- 每个设备适配器独立声明重复键、长按和组合键策略。

### `EventPipeline`

- 统一事件：方向、确认、返回、Home、菜单、音量加减、静音、播放控制和语音触发。
- 优先使用只匹配 RC003 VID/PID 的 `hidutil` 映射，将系统键中转为专用 relay key，再由事件 Tap 消费；不会改写 MacBook 内置键盘。
- 无法启用设备映射时，降级为 HID 与普通键盘事件的短时关联去重。
- Profile 包含“原样交给应用”时也自动使用关联模式，确保应用收到真正的原始按键，而不是内部 relay key。
- 对方向键允许受控重复，对返回、菜单和 Home 禁止意外连发。

部分遥控器会同时被 macOS 当成键盘。只监听 HID 而不处理原始键盘事件，会造成“原按键 + 注入按键”双触发。第一版通过设备 HID 回调与 `CGEventTap` 的短时间关联，只吞掉来自目标遥控器的对应原始事件；不得影响 MacBook 内置键盘或其他键盘。

### `AppContext`

- 使用 `NSWorkspace.frontmostApplication` 读取当前接收键盘事件的应用。
- 订阅 `didActivateApplicationNotification`，仅在前台 App 改变时重算 Profile。
- Profile 主键使用 Bundle Identifier，不依赖本地化应用名或窗口标题。

### `ProfileKit`

```swift
struct AppProfile: Codable, Identifiable {
    var id: String
    var name: String
    var bundleIdentifiers: [String]
    var bindings: [RemoteButton: RemoteAction]
    var holdBindings: [RemoteButton: RemoteAction]
    var doubleTapBindings: [RemoteButton: RemoteAction]
}
```

解析优先级：

1. 用户为具体 Bundle Identifier 保存的覆盖配置。
2. App 内置 Profile。
3. 全局默认 Profile。

配置保存在 `Application Support/mmTV Remote/Profiles`。写入采用原子替换；损坏和被删除的配置会保留到 `Recovery`，再安全回退到内置 Profile。

### `ActionKit`

第一版只允许结构化动作：

- `keyStroke(key, modifiers)`
- `systemDictation`
- `systemVolume(delta)` / `mute`
- `media(playPause | next | previous)`
- `launch(bundleIdentifier)`
- `none`

按键通过 `CGEvent` 注入，需要辅助功能权限。原始设备读取需要输入监控权限。任意 Shell 和脚本动作不进入第一版，避免扩大安全边界。

### `VoiceInputProvider`

- 语音键是全局能力，不随前台应用 Profile 变化。
- Typeless 模式将 RC003 语音 usage 映射到 F20，在 `CGEventTap` 中记录但不消费该真实硬件事件。Typeless 对软件合成事件的拒绝策略因此不会被触发。
- macOS 系统听写先通过辅助功能执行当前应用的听写菜单项，失败时降级为系统双 Fn 手势。
- 提供商保存在运行配置中；新增其他服务只需扩展类型、执行策略和界面元数据，无需改动 HID 与 Profile 主链路。

### `MenuBarApp`

- 启用／暂停遥控服务。
- 显示设备连接、当前前台 App 和生效 Profile。
- 权限状态与跳转系统设置。
- 登录时启动。
- 打开 Profile 管理窗口和输入诊断面板。

## Profile 与专用适配器的边界

优先使用按键 Profile。只有目标应用无法通过稳定快捷键控制时，才增加专用 `AppAdapter`。专用适配器必须有明确 Bundle Identifier、能力声明和失败降级，不把基于屏幕坐标点击作为默认方案。

建议首批 Profile：

- Default Desktop：方向、确认、返回、音量和媒体键。
- mmTV：完整导航、Home 和菜单。
- Finder：浏览、打开和返回上级。
- Chromium / Safari：浏览、播放、全屏和返回。
- IINA：播放、进度、音量、字幕和全屏。
- 游戏／模拟器：默认透传或显式关闭映射，避免与原生手柄输入冲突。

## 与 mmTV 的关系

- 两个仓库、两个应用、独立安装和发布。
- mmTV Remote 是唯一全局 HID 入口，防止两个进程重复消费按键。
- 第一版通过 mmTV 的键盘快捷键 Profile 工作，不引入 XPC。
- 将来若键盘快捷键无法表达某些语义，再定义版本化的本机 IPC；IPC 不是首版前提。

## 权限与发布

- Input Monitoring：读取目标遥控器的原始 HID 输入。
- Accessibility：向其他应用发送合成键盘事件并拦截必要的重复事件。
- App Sandbox：第一版不开启；相关系统 API、权限和发行方式先做实机验证。
- 签名：保持固定 Bundle Identifier 和 Apple Development / Developer ID 签名，避免每次构建丢失 TCC 授权。
- 登录启动：macOS 13+ 使用 `SMAppService.mainApp`，不自行写 LaunchAgent。

## 可靠性原则

- 配置损坏时回退到只读默认 Profile。
- 设备映射保留原有第三方映射；正常退出、设备断开或进程异常结束时恢复。
- 注入的事件带自身来源标记，避免再次被事件管线接收形成循环。
- 设备断开或睡眠唤醒后自动重新枚举。
- 配置窗口不在前台时不显示 Dock 图标；服务状态始终可从菜单栏判断。
- 提供“暂停映射”和紧急退出快捷方式，防止错误 Profile 锁死输入。
