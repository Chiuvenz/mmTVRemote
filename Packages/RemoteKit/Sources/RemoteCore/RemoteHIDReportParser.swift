import Foundation

public struct RemoteVoiceReport: Equatable, Sendable {
    public let reportID: UInt32
    public let bytes: [UInt8]
    public let timestamp: Date

    public init(reportID: UInt32, bytes: [UInt8], timestamp: Date) {
        self.reportID = reportID
        self.bytes = bytes
        self.timestamp = timestamp
    }
}

public enum RemoteHIDReportParser {
    public static let keyboardArraySlotCount = 3
    public static let keyboardArrayPayloadLength = keyboardArraySlotCount * 2

    public static func keyboardUsage(elementUsage: UInt32, integerValue: Int) -> UInt32? {
        if elementUsage == UInt32.max {
            guard integerValue > 0, integerValue <= 0xFE else { return nil }
            return UInt32(integerValue)
        }
        guard elementUsage > 0,
              elementUsage <= 0xFE,
              integerValue != 0 else { return nil }
        return elementUsage
    }

    public static func keyboardUsages(reportID: UInt32, bytes: [UInt8]) -> Set<UInt32>? {
        let includesReportID: Bool
        switch reportID {
        case 1:
            includesReportID = bytes.first == 1
        case 0:
            guard bytes.first == 1 else { return nil }
            includesReportID = true
        default:
            return nil
        }

        let payloadStart = includesReportID ? 1 : 0
        guard bytes.count >= payloadStart + keyboardArrayPayloadLength else { return nil }
        return keyboardArrayUsages(bytes: Array(bytes.dropFirst(payloadStart)))
    }

    public static func keyboardArrayUsages(bytes: [UInt8]) -> Set<UInt32>? {
        guard bytes.count >= keyboardArrayPayloadLength else { return nil }
        var usages: Set<UInt32> = []
        for slot in 0..<keyboardArraySlotCount {
            let index = slot * 2
            let usage = UInt32(bytes[index]) | (UInt32(bytes[index + 1]) << 8)
            guard usage != 0, usage != 0xFFFF, usage <= 0xFE else { continue }
            usages.insert(usage)
        }
        return usages
    }
}

public struct RemoteHIDStateChange: Equatable, Sendable {
    public let usage: UInt32
    public let isDown: Bool

    public init(usage: UInt32, isDown: Bool) {
        self.usage = usage
        self.isDown = isDown
    }
}

public struct RemoteHIDStateTracker: Sendable {
    public private(set) var pressedUsages: Set<UInt32> = []

    public init() {}

    public mutating func update(with usages: Set<UInt32>) -> [RemoteHIDStateChange] {
        let released = pressedUsages.subtracting(usages).sorted()
        let pressed = usages.subtracting(pressedUsages).sorted()
        pressedUsages = usages
        return released.map { RemoteHIDStateChange(usage: $0, isDown: false) }
            + pressed.map { RemoteHIDStateChange(usage: $0, isDown: true) }
    }

    public mutating func reset() {
        pressedUsages.removeAll()
    }
}
