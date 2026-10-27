import Foundation
import Testing
@testable import RemoteCore

@Test("RC003 HID usage 映射")
func xiaomiUsageMapping() {
    let expected: [(UInt32, RemoteButton)] = [
        (0x52, .up), (0x51, .down), (0x50, .left), (0x4F, .right),
        (0x28, .select), (0xF1, .back), (0x4A, .home), (0x35, .tv),
        (0x65, .menu), (0x66, .power), (0x3E, .voice),
        (0x80, .volumeUp), (0x81, .volumeDown),
    ]
    for (usage, button) in expected {
        #expect(XiaomiRemoteProfile.button(usagePage: 0x07, usage: usage) == button)
    }
    #expect(XiaomiRemoteProfile.button(usagePage: 0x0C, usage: 0x65) == nil)
    #expect(XiaomiRemoteProfile.button(usagePage: 0x07, usage: 0xFF) == nil)
}

@Test("用户 Profile 优先于内置 Profile")
func userProfileWins() {
    let user = AppProfile(
        id: "custom-iina",
        name: "我的 IINA",
        bundleIdentifiers: ["com.colliderli.iina"],
        bindings: [.select: .media(.playPause)]
    )
    let resolver = ProfileResolver(userProfiles: [user])
    #expect(resolver.resolve(bundleIdentifier: "com.colliderli.iina").id == "custom-iina")
}

@Test("未知应用回退默认 Profile")
func defaultFallback() {
    let resolver = ProfileResolver()
    #expect(resolver.resolve(bundleIdentifier: "example.unknown").id == "default")
    #expect(resolver.resolve(bundleIdentifier: nil).id == "default")
}

@Test("mmTV Profile 注入标准按键并由 Remote 独占 HID")
func mmTVProfileKeyboardInjection() {
    let profile = BuiltInProfiles.mmTV
    #expect(profile.action(for: .up) == .keyStroke(KeyStroke(MacKeyCode.up)))
    #expect(profile.action(for: .down) == .keyStroke(KeyStroke(MacKeyCode.down)))
    #expect(profile.action(for: .left) == .keyStroke(KeyStroke(MacKeyCode.left)))
    #expect(profile.action(for: .right) == .keyStroke(KeyStroke(MacKeyCode.right)))
    #expect(profile.action(for: .select) == .keyStroke(KeyStroke(MacKeyCode.returnKey)))
    #expect(profile.action(for: .back) == .keyStroke(KeyStroke(MacKeyCode.escape)))
    #expect(profile.action(for: .home) == .keyStroke(KeyStroke(MacKeyCode.home)))
    #expect(profile.action(for: .tv) == .keyStroke(KeyStroke(MacKeyCode.home)))
    #expect(profile.action(for: .menu) == .keyStroke(KeyStroke(MacKeyCode.f2)))
    #expect(profile.action(for: .volumeUp) == .systemVolume(delta: 0.0625))
    #expect(profile.action(for: .volumeDown) == .systemVolume(delta: -0.0625))
    #expect(profile.action(for: .voice) == .none)
    #expect(profile.action(for: .power) == .none)
    #expect(!profile.requiresNativePassThrough)
}

@Test("包含透传动作的 Profile 会声明原始事件需求")
func profileNativePassThroughRequirement() {
    var profile = BuiltInProfiles.defaultProfile
    #expect(!profile.requiresNativePassThrough)
    profile.setAction(.passThrough, for: .menu, trigger: .tap)
    #expect(profile.requiresNativePassThrough)
}

@Test("Profile 可 JSON 往返")
func profileCodableRoundTrip() throws {
    let data = try JSONEncoder().encode(BuiltInProfiles.iina)
    let decoded = try JSONDecoder().decode(AppProfile.self, from: data)
    #expect(decoded == BuiltInProfiles.iina)
}

@Test("运行设置可保存语音输入提供商")
func voiceInputProviderRoundTrip() throws {
    let configuration = RemoteConfiguration(voiceInputProvider: .systemDictation)
    let data = try JSONEncoder().encode(configuration)
    #expect(try JSONDecoder().decode(RemoteConfiguration.self, from: data) == configuration)
}

@Test("旧版运行设置默认迁移到 Typeless")
func legacyConfigurationDefaultsToTypeless() throws {
    let json = """
    {
      "version": 1,
      "gestureSettings": {
        "holdMilliseconds": 350,
        "doubleTapMilliseconds": 250,
        "debounceMilliseconds": 30
      }
    }
    """
    let configuration = try JSONDecoder().decode(
        RemoteConfiguration.self,
        from: Data(json.utf8)
    )
    #expect(configuration.voiceInputProvider == .typeless)
}

@Test("用户 Profile JSON 保持可读")
func readableUserProfileJSON() throws {
    let json = """
    {
      "id": "custom",
      "name": "自定义",
      "bundleIdentifiers": ["example.app"],
      "bindings": {
        "select": { "type": "keyStroke", "keyCode": 49, "modifiers": ["command"] },
        "volumeUp": { "type": "systemVolume", "delta": 0.0625 }
      }
    }
    """
    let profile = try JSONDecoder().decode(AppProfile.self, from: Data(json.utf8))
    #expect(profile.action(for: .select) == .keyStroke(
        KeyStroke(MacKeyCode.space, modifiers: .command)
    ))
    #expect(profile.action(for: .volumeUp) == .systemVolume(delta: 0.0625))
}

@Test("Profile 支持单击、长按和双击配置")
func profileGestureBindingsRoundTrip() throws {
    let profile = AppProfile(
        id: "gestures",
        name: "手势",
        bundleIdentifiers: ["example.app"],
        bindings: [.select: .keyStroke(KeyStroke(MacKeyCode.returnKey))],
        holdBindings: [.select: .media(.playPause)],
        doubleTapBindings: [.select: .mute]
    )
    let data = try JSONEncoder().encode(profile)
    let decoded = try JSONDecoder().decode(AppProfile.self, from: data)
    #expect(decoded == profile)
    #expect(decoded.action(for: .select, trigger: .hold) == .media(.playPause))
    #expect(decoded.action(for: .select, trigger: .doubleTap) == .mute)
}

@Test("完整 HID Report 解析三个按键槽")
func reportParser() {
    let bytes: [UInt8] = [1, 0x52, 0, 0x28, 0, 0xF1, 0]
    #expect(RemoteHIDReportParser.keyboardUsages(reportID: 1, bytes: bytes) == [0x52, 0x28, 0xF1])
    #expect(RemoteHIDReportParser.keyboardUsages(reportID: 6, bytes: bytes) == nil)
    #expect(RemoteHIDReportParser.keyboardUsage(elementUsage: .max, integerValue: 0x65) == 0x65)
}

@Test("HID 状态差分只产生真实按下与松开")
func reportStateDiff() {
    var tracker = RemoteHIDStateTracker()
    #expect(tracker.update(with: [0x52]) == [.init(usage: 0x52, isDown: true)])
    #expect(tracker.update(with: [0x52]).isEmpty)
    #expect(tracker.update(with: [0x28]) == [
        .init(usage: 0x52, isDown: false),
        .init(usage: 0x28, isDown: true),
    ])
}

@MainActor
@Test("无复合手势时单击立即触发")
func immediateTapGesture() {
    let engine = RemoteGestureEngine()
    var resolved: [(RemoteButton, RemoteTrigger)] = []
    engine.hasBinding = { _, trigger in trigger == .tap }
    engine.onResolvedTrigger = { resolved.append(($0, $1)) }
    engine.handle(.select, isPressed: true)
    #expect(resolved.map(\.1) == [.tap])
    engine.handle(.select, isPressed: false)
    #expect(resolved.count == 1)
}

@MainActor
@Test("双击配置会解析为双击而不是两个单击")
func doubleTapGesture() async throws {
    let engine = RemoteGestureEngine()
    engine.doubleTapMilliseconds = 80
    var resolved: [RemoteTrigger] = []
    engine.hasBinding = { _, trigger in trigger == .tap || trigger == .doubleTap }
    engine.onResolvedTrigger = { _, trigger in resolved.append(trigger) }
    let start = Date()
    engine.handle(.menu, isPressed: true, timestamp: start)
    engine.handle(.menu, isPressed: false, timestamp: start.addingTimeInterval(0.01))
    engine.handle(.menu, isPressed: true, timestamp: start.addingTimeInterval(0.05))
    engine.handle(.menu, isPressed: false, timestamp: start.addingTimeInterval(0.06))
    try await Task.sleep(for: .milliseconds(120))
    #expect(resolved == [.doubleTap])
}

@MainActor
@Test("长按只触发长按动作")
func holdGesture() async throws {
    let engine = RemoteGestureEngine()
    engine.holdMilliseconds = 40
    var resolved: [RemoteTrigger] = []
    engine.hasBinding = { _, trigger in trigger == .tap || trigger == .hold }
    engine.onResolvedTrigger = { _, trigger in resolved.append(trigger) }
    engine.handle(.home, isPressed: true)
    try await Task.sleep(for: .milliseconds(70))
    engine.handle(.home, isPressed: false)
    #expect(resolved == [.hold])
}

@MainActor
@Test("重置会取消待触发的手势")
func gestureResetCancelsPendingWork() async throws {
    let engine = RemoteGestureEngine()
    engine.doubleTapMilliseconds = 40
    var resolved: [RemoteTrigger] = []
    engine.hasBinding = { _, trigger in trigger == .tap || trigger == .doubleTap }
    engine.onResolvedTrigger = { _, trigger in resolved.append(trigger) }
    engine.handle(.menu, isPressed: true)
    engine.handle(.menu, isPressed: false)
    engine.reset()
    try await Task.sleep(for: .milliseconds(70))
    #expect(resolved.isEmpty)
}
