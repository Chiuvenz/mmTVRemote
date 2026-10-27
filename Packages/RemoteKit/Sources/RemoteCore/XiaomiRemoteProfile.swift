import Foundation

public enum XiaomiRemoteProfile {
    public static let vendorID = 0x2717
    public static let productID = 0x32B8
    public static let productName = "小米蓝牙语音遥控器"

    public static func button(usagePage: UInt32, usage: UInt32) -> RemoteButton? {
        guard usagePage == 0x07 else { return nil }
        return switch usage {
        case 0x52: .up
        case 0x51: .down
        case 0x50: .left
        case 0x4F: .right
        case 0x28: .select
        case 0xF1: .back
        case 0x4A: .home
        case 0x35: .tv
        case 0x65: .menu
        case 0x66: .power
        case 0x3E: .voice
        case 0x80: .volumeUp
        case 0x81: .volumeDown
        default: nil
        }
    }

    /// Quartz key code emitted by macOS in addition to the raw HID value.
    /// Special consumer usages intentionally return nil.
    public static func nativeKeyCode(for button: RemoteButton) -> UInt16? {
        switch button {
        case .up: MacKeyCode.up
        case .down: MacKeyCode.down
        case .left: MacKeyCode.left
        case .right: MacKeyCode.right
        case .select: MacKeyCode.returnKey
        case .home: 115
        case .tv: 50
        case .voice: 96
        case .back, .menu, .volumeUp, .volumeDown, .power: nil
        }
    }
}
