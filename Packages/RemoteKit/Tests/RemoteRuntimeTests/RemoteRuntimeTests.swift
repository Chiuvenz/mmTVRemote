import Foundation
import CoreGraphics
import RemoteCore
import Testing
@testable import RemoteRuntime

@MainActor
@Test("hidutil 映射覆盖除返回键外的十二个按键")
func remapperCoverage() {
    #expect(DeviceKeyRemapper.relayTable.count == 12)
    #expect(DeviceKeyRemapper.relayTable.allSatisfy { $0.sourceUsage != 0xF1 })
    #expect(Set(DeviceKeyRemapper.relayTable.map(\.sourceUsage)).count == 12)
}

@MainActor
@Test("hidutil 输出可保留既有第三方映射")
func remapperParsing() {
    let output = """
    UserKeyMapping:(
      { HIDKeyboardModifierMappingSrc = 30064771146; HIDKeyboardModifierMappingDst = 30064771177; }
    )
    """
    let mappings = DeviceKeyRemapper.parseUserKeyMapping(output)
    #expect(mappings?.count == 1)
    #expect(mappings?.first?.source == 30_064_771_146)
    #expect(mappings?.first?.destination == 30_064_771_177)
}

@MainActor
@Test("hidutil 输出支持十六进制映射")
func remapperHexParsing() {
    let output = """
    UserKeyMapping:(
      { "HIDKeyboardModifierMappingSrc" = 0x700000004; "HIDKeyboardModifierMappingDst" = 0x700000005; }
    )
    """
    let mappings = DeviceKeyRemapper.parseUserKeyMapping(output)
    #expect(mappings?.count == 1)
    #expect(mappings?.first?.source == 0x7_0000_0004)
    #expect(mappings?.first?.destination == 0x7_0000_0005)
}

@MainActor
@Test("设备映射安装和卸载会保留第三方映射")
func remapperPreservesForeignMappings() {
    let foreignSource: UInt64 = 0x7_0000_0004
    let foreignDestination: UInt64 = 0x7_0000_0005
    var sets: [String] = []
    let remapper = DeviceKeyRemapper(hidutilRunner: { arguments, captureOutput in
        if captureOutput {
            return (true, "{ HIDKeyboardModifierMappingSrc = \(foreignSource); HIDKeyboardModifierMappingDst = \(foreignDestination); }")
        }
        if let value = arguments.last { sets.append(value) }
        return (true, "")
    })

    #expect(remapper.install())
    #expect(remapper.isInstalled)
    #expect(sets.last?.contains("\(foreignSource)") == true)
    remapper.uninstall()
    #expect(!remapper.isInstalled)
    #expect(sets.last?.contains("\(foreignSource)") == true)
    #expect(sets.last?.contains("\(foreignDestination)") == true)
}

@MainActor
@Test("异步设备映射安装和卸载会保留第三方映射")
func asyncRemapperPreservesForeignMappings() async {
    let foreignSource: UInt64 = 0x7_0000_0004
    let foreignDestination: UInt64 = 0x7_0000_0005
    var sets: [String] = []
    let remapper = DeviceKeyRemapper(hidutilRunner: { arguments, captureOutput in
        if captureOutput {
            return (true, "{ HIDKeyboardModifierMappingSrc = 0x700000004; HIDKeyboardModifierMappingDst = 0x700000005; }")
        }
        if let value = arguments.last { sets.append(value) }
        return (true, "")
    })

    #expect(await remapper.installAsync())
    #expect(remapper.isInstalled)
    await remapper.uninstallAsync()
    #expect(!remapper.isInstalled)
    #expect(sets.last?.contains("\(foreignSource)") == true)
    #expect(sets.last?.contains("\(foreignDestination)") == true)
}

@MainActor
@Test("设备映射析构时恢复第三方映射")
func remapperRestoresMappingsOnDeinit() {
    let foreignSource: UInt64 = 0x7_0000_0004
    var sets: [String] = []
    var remapper: DeviceKeyRemapper? = DeviceKeyRemapper(hidutilRunner: { arguments, captureOutput in
        if captureOutput {
            return (true, "{ HIDKeyboardModifierMappingSrc = \(foreignSource); HIDKeyboardModifierMappingDst = 30064771077; }")
        }
        if let value = arguments.last { sets.append(value) }
        return (true, "")
    })

    #expect(remapper?.install() == true)
    remapper = nil
    #expect(sets.count == 2)
    #expect(sets.last?.contains("\(foreignSource)") == true)
}

@MainActor
@Test("Typeless 可接收遥控器中继后的真实 F20 事件")
func remapperCanPassThroughVoiceRelay() throws {
    let remapper = DeviceKeyRemapper(hidutilRunner: nil)
    var received: (RemoteButton, Bool)?
    remapper.onButton = { received = ($0, $1) }
    remapper.shouldPassThrough = { $0 == .voice }
    let event = try #require(CGEvent(
        keyboardEventSource: nil,
        virtualKey: 90,
        keyDown: true
    ))

    let result = remapper.handleEventTap(type: .keyDown, event: event)

    #expect(result != nil)
    #expect(received?.0 == .voice)
    #expect(received?.1 == true)
}

@Test("ProfileStore 原子保存并恢复损坏文件")
func profileStoreRecovery() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mmTVRemoteTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ProfileStore(directory: directory)
    let profile = AppProfile(
        id: "example.app",
        name: "示例",
        bundleIdentifiers: ["example.app"],
        bindings: [.select: .media(.playPause)]
    )
    try store.save(profile)
    try Data("not json".utf8).write(
        to: directory.appendingPathComponent("broken.json"),
        options: .atomic
    )
    let result = store.load()
    #expect(result.profiles == [profile])
    #expect(result.recoveredFiles.count == 1)
    #expect(FileManager.default.fileExists(atPath: result.recoveredFiles[0].path))
}

@Test("运行设置可原子保存")
func configurationStoreRoundTrip() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mmTVRemoteConfigTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConfigurationStore(fileURL: directory.appendingPathComponent("config.json"))
    let configuration = RemoteConfiguration(
        gestureSettings: RemoteGestureSettings(
            holdMilliseconds: 420,
            doubleTapMilliseconds: 280,
            debounceMilliseconds: 35
        )
    )
    try store.save(configuration)
    #expect(try store.load() == configuration)
}

@Test("蓝牙状态解析电量和固件")
func bluetoothSnapshotParsing() {
    let json = """
    {
      "SPBluetoothDataType": [{
        "device_connected": [{
          "遥控器": {
            "device_vendorID": "0x2717",
            "device_productID": "0x32B8",
            "device_batteryLevelMain": "87%",
            "device_firmwareVersion": "1.2.3"
          }
        }]
      }]
    }
    """
    let result = RemoteDeviceInfoService.snapshot(
        in: Data(json.utf8),
        deviceName: "其他名称",
        vendorID: 0x2717,
        productID: 0x32B8
    )
    #expect(result == RemoteDeviceSnapshot(batteryLevel: 87, firmwareVersion: "1.2.3"))
}
