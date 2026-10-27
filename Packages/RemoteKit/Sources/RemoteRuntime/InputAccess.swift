import ApplicationServices
import Foundation
import IOKit.hid

public enum InputMonitoringStatus: String, Sendable {
    case granted, denied, unknown

    public var title: String {
        switch self {
        case .granted: "已授权"
        case .denied: "未授权"
        case .unknown: "待授权"
        }
    }
}

public enum InputAccess {
    public static var inputMonitoringStatus: InputMonitoringStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeDenied: .denied
        default: .unknown
        }
    }

    @discardableResult
    public static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    public static var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public static func requestAccessibility() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}
