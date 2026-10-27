# 用户 Profile

用户 Profile 放在：

```text
~/Library/Application Support/mmTV Remote/Profiles/
```

每个 `.json` 文件定义一个或多个 Bundle Identifier 的遥控器映射。通常直接点击控制台里的应用图标进行编辑，无需手写 JSON；用户 Profile 的优先级高于内置 Profile。

## 示例

```json
{
  "id": "my-iina",
  "name": "我的 IINA",
  "bundleIdentifiers": ["com.colliderli.iina"],
  "bindings": {
    "up": { "type": "passThrough" },
    "down": { "type": "passThrough" },
    "left": { "type": "passThrough" },
    "right": { "type": "passThrough" },
    "select": { "type": "keyStroke", "keyCode": 49 },
    "back": { "type": "keyStroke", "keyCode": 53 },
    "volumeUp": { "type": "systemVolume", "delta": 0.0625 },
    "volumeDown": { "type": "systemVolume", "delta": -0.0625 },
    "menu": { "type": "none" }
  },
  "holdBindings": {
    "select": { "type": "media", "command": "playPause" }
  },
  "doubleTapBindings": {
    "menu": { "type": "launch", "bundleIdentifier": "com.mmtv.mac" }
  }
}
```

## 动作类型

- `passThrough`：不注入事件，让 macOS 原始按键直接到达应用。
- `keyStroke`：发送 macOS 虚拟键码；可选 `modifiers` 为 `command`、`control`、`option`、`shift`。
- `systemVolume`：按 `delta` 调整系统音量。
- `mute`：切换系统静音。
- `media`：`command` 可为 `playPause`、`next`、`previous`。
- `launch`：使用 `bundleIdentifier` 启动或切换应用。
- `none`：拦截原始按键但不执行动作。

带修饰键示例：

```json
"back": {
  "type": "keyStroke",
  "keyCode": 33,
  "modifiers": ["command"]
}
```

运行设置位于 `~/Library/Application Support/mmTV Remote/config.json`。Profile 和运行设置均采用原子写入；无法读取的文件会复制到 `Recovery` 后回退默认值。
