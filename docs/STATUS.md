# 当前状态

更新日期：2026-10-28。

## V0.3 已完成

- 独立原生 macOS 菜单栏应用，Bundle Identifier 为 `com.mmtv.remote`。
- RC003（VID `0x2717` / PID `0x32B8`）连接检测、完整 HID Report 解析、三槽状态差分和全部已知按键映射。
- 输入监控、辅助功能权限检测和系统设置入口。
- 基于前台 Bundle Identifier 的 Profile 自动路由。
- 默认桌面、mmTV、Finder、Safari/Chrome/Edge/Arc、IINA 内置 Profile。
- 设备级 `hidutil` 中转映射、CGEventTap 接管、异常退出恢复，以及兼容模式关联去重。
- 单击、长按、双击与防抖手势引擎；方向与音量支持受控重复。
- CoreAudio 系统音量、媒体控制、TV 键启动 mmTV。
- 可视化 App Profile 编辑器，可分别编辑三种手势并恢复默认。
- 用户 JSON Profile 原子保存、优先级覆盖、损坏恢复和即时重新加载。
- 遥控器电量、固件、连接状态和当前接管模式展示。
- `SMAppService` 登录启动开关。
- 原生菜单栏状态面板，以卡片形式呈现当前应用与适配方案，并能启停服务、管理登录启动、刷新配置和打开控制台。
- 专用遥控器 Template 图标，无文字占位，自动适配浅色、深色与透明菜单栏。
- 产品化控制台：就绪状态、真实 App 图标列表、自动 Profile 切换、权限设置与最近操作。
- 全局语音输入提供商，支持 Typeless、macOS 系统听写和关闭，不随 App Profile 切换。
- Typeless 模式通过遥控器设备级映射产生真实 F20，避免其拒绝软件合成事件；控制台可检查 Typeless 快捷键是否就绪。

## 已验证

- 23 项核心与运行时测试通过。
- Release arm64 构建成功。
- Apple Development 固定身份、Hardened Runtime、Bundle 结构与 ZIP 完整性通过；构建脚本禁止回退到会让系统权限失效的临时签名。
- 当前 MacBook 实机识别 RC003 为已连接。
- 前台应用从 ChatGPT 切换到 Finder 后，Profile 自动切换为 Finder。

## mmTV 所有权切换（代码侧已完成）

- 内置 mmTV Profile 为键盘注入：方向／确认／返回／Home／F2 菜单；音量由 Remote 调整（不再整表 `none`）。
- mmTV 已删除 `XiaomiRemoteHID` 直连、输入监控授权 UI 与相关 Info.plist 说明；静态与进程检查确认 HID 仅由 Remote 持有。
- 若本机存在覆盖 `com.mmtv.mac` 的用户 Profile，实体验收前请在控制台「恢复默认」。
- **仍待人工**：mmTV 前台实体键回归（每键只触发一次）、Typeless F20、HDMI 音量降级。Mac mini 重建 Remote 需 Apple Development 身份（脚本不回退 ad-hoc）。

## 尚需人工验收

- mmTV 前台：方向、确认、返回、菜单开关设置、Home 回主页、音量与 TV 键；确认只触发一次。
- 在 Typeless 中将 Dictation Mode 快捷键设为 F20，再用实体语音键验收录音开始／结束。
- 使用实体遥控器逐项体验 Finder、浏览器、IINA，以及（可选）`com.mmtv.bilitv` 手感。
- Mac mini 安装后的 HDMI 音量降级行为。
