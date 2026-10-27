# mmTV Remote

一款可独立运行的 macOS 遥控器适配应用。它把蓝牙／USB 遥控器的原始 HID 输入转换成当前前台应用能够理解的按键、媒体操作和系统动作。

mmTV Remote 不要求启动 mmTV。它可以安装在 MacBook 或 Mac mini 上，以菜单栏应用形式常驻；mmTV 只是它支持的一个应用 Profile。

## 产品边界

- 直接识别目标遥控器，不依赖 Karabiner-Elements、Hammerspoon 或第三方驱动。
- 根据前台应用的 Bundle Identifier 自动选择 Profile。
- 支持方向、确认、返回、Home、菜单、音量和媒体操作。
- 提供默认 Profile，并允许用户覆盖单个应用的映射。
- 所有配置和按键处理都在本机完成。

首个设备为小米蓝牙遥控器2 Pro / RC003（VID `0x2717` / PID `0x32B8`）。

## 第一阶段不做

- 通用手柄、MIDI 和鼠标映射。
- JavaScript、Shell 脚本或任意宏执行。
- 云端 Profile 市场与账户系统。
- 系统扩展、虚拟 HID 驱动或内核级方案。
- 为每个应用写复杂的 UI 自动化流程。

这些功能会显著扩大权限和故障面，但不是“用电视遥控器可靠控制 Mac 应用”的必要条件。

## 文档

- [架构设计](ARCHITECTURE.md)
- [开源方案调研](docs/RESEARCH.md)
- [版本计划](docs/ROADMAP.md)
- [用户 Profile](docs/PROFILES.md)

## 当前状态

V0.3 在 V0.2 的设备级按键接管、可视化 Profile 和菜单栏服务上，新增了全局语音输入通道。语音键可切换为 Typeless、macOS 系统听写或关闭；Typeless 模式会保留遥控器中继后的真实硬件 F20 事件。Release 构建位于 `dist/mmTVRemote.app`。

Typeless 还需在其设置中将 Dictation Mode 快捷键设为 `F20`。mmTV Remote 会在控制台检查并显示该状态，但不会直接改写 Typeless 的私有配置文件。

## 本机构建

运行 `Scripts/build.sh` 会使用钥匙串中的固定 Apple Development 身份签名。脚本不会回退到临时签名，因为签名身份改变会导致 macOS 重新要求输入监控和辅助功能授权。也可以通过 `MMTV_REMOTE_CODE_SIGN_IDENTITY` 显式指定签名。

运行 `Scripts/install.sh` 会验证固定签名，把唯一运行副本安装到 `/Applications/mmTV Remote.app` 并启动。开发目录中的构建不会再注册成另一个可运行副本，系统权限始终绑定 `/Applications` 中的应用。
