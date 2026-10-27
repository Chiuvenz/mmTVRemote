# 开源方案调研

调研日期：2026-10-27。

## 结论

没有必要直接 fork 一个通用映射器。最合适的路线是复用这些项目验证过的设计思想，并用原生 Swift 实现针对电视遥控器的精简产品。这样无需安装大型依赖或系统驱动，也能保留 per-app Profile、设备诊断和后续 mmTV 集成能力。

## 值得借鉴

### MiCoding

仓库：[zhangtuansia/MiCoding](https://github.com/zhangtuansia/MiCoding)

它针对同一款 RC003 遥控器，验证了完整 HID Report、`hidutil` 设备映射、按键手势以及蓝牙设备信息读取这条路线。V0.2 吸收了这些设计思路，并按照 mmTV Remote 的单 App、Bundle Identifier Profile 和结构化动作架构重新实现。V0.3 进一步吸收了其 Typeless 集成的关键结论：Typeless 会拒绝软件合成按键，因此语音键必须映射成 F20 并在事件接管层原样放行。

落地改进：映射只作用于目标 VID/PID；安装时保留第三方已有映射；正常退出与异常终止均恢复；失败自动降级；Profile 与运行配置使用原子写入和损坏恢复；提供原生可视化编辑器和自动测试。

### InputConfig

仓库：[ryleighnewman/InputConfig](https://github.com/ryleighnewman/InputConfig)

这是产品形态最接近的参考：无驱动、菜单栏常驻、输入扫描、结构化动作、按前台 App 自动切换 Preset，并明确使用辅助功能权限完成键鼠输出。MIT 许可证允许参考和复用，但它面向手柄、MIDI、鼠标及大量高级映射，范围远大于本项目。

借鉴：

- 输入扫描／Live Monitor，而不是让用户手填 usage。
- 前台应用自动切换 Profile。
- 默认 Preset 与用户 Preset 分离。
- 权限状态、设备状态和当前 Profile 都应可见。

不照搬：

- 通用手柄绘制、陀螺仪、MIDI、宏、语音输出和数百个游戏模板。

### Enjoyable

仓库：[romainguerif/enjoyable](https://github.com/romainguerif/enjoyable)

Enjoyable 是经典的 HID 到键盘／鼠标映射器，现代 fork 已恢复新 macOS 支持，采用 MIT 许可证。源码展示了一条简单、可验证的链路：`IOHIDManager` 获取输入，`NSWorkspaceDidActivateApplicationNotification` 触发映射切换，`CGEvent` 输出事件。

借鉴：

- 监听工作区前台应用变化，而非轮询。
- 菜单栏常驻与启停状态。
- 配置出错时保留手动／默认映射。

改进：

- Profile 使用 Bundle Identifier 精确匹配，不使用应用名称猜测。
- 使用 Swift Codable 和版本化 Schema，不延续 Objective-C／NSUserDefaults 的整体序列化模型。
- 登录启动采用现代 `SMAppService`。

### Karabiner-Elements

仓库：[pqrs-org/Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements)

它证明了 `frontmost_application_if` 这种按 Bundle Identifier 条件化映射的可靠性，也提供成熟的设备条件、事件查看器和复杂修改模型。

借鉴：Profile 条件、设备过滤、事件诊断和明确的规则优先级。

不采用为依赖：它是通用键盘重映射平台，包含后台服务、虚拟 HID 与更复杂的安装权限；对单款电视遥控器过重。

### Hammerspoon

仓库：[Hammerspoon/hammerspoon](https://github.com/Hammerspoon/hammerspoon)

它的应用监听、事件注入和菜单栏自动化能力适合快速原型，也证明 macOS 用户态自动化的可行性。

借鉴：能力模块化、运行时状态可观察。

不采用为依赖：需要用户安装运行时并维护 Lua 配置，无法提供开箱即用的遥控器产品体验。

### kymorph

仓库：[zingerone/kymorph](https://github.com/zingerone/kymorph)

这个很小的实现演示了同时使用 `IOHIDManager` 识别物理设备、再用 `CGEventTap` 拦截和注入事件的机制，恰好对应遥控器方向键可能产生双事件的问题。

仅借鉴机制，不复制代码：该仓库当前没有明确许可证；而且它用 HID 回调和事件 Tap 共享单个 pending usage，面对快速连按和多设备时需要更严格的时间戳队列与同步。

## Apple API 核验

- [`IOHIDManagerRegisterInputValueCallback`](https://developer.apple.com/documentation/iokit/1438367-iohidmanagerregisterinputvalueca)：接收已枚举 HID 设备的输入值。
- [`NSWorkspace.frontmostApplication`](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication)：获取当前接收键盘事件的前台应用。
- [`NSWorkspace.didActivateApplicationNotification`](https://developer.apple.com/documentation/AppKit/NSWorkspace/didActivateApplicationNotification)：在前台应用切换时收到通知。
- [`SMAppService.mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)：让主应用作为登录项启动。

## 决策记录

1. 原生 Swift + SwiftUI/AppKit，而不是 fork Objective-C 或引入 Lua 运行时。
2. 单 App 菜单栏架构起步，不预先拆 helper daemon。
3. IOHIDManager 是设备输入源；CGEvent/CGEventTap 是兼容输出与去重层。
4. Bundle Identifier 是 Profile 匹配主键。
5. 首版动作白名单化，不支持任意脚本。
6. mmTV 先走键盘 Profile；确有需要后再引入 IPC。
