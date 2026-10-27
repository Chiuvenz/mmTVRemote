import Foundation
import IOKit
import RemoteCore

public struct RemoteDeviceSnapshot: Equatable, Sendable {
    public let batteryLevel: Int?
    public let firmwareVersion: String?

    public init(batteryLevel: Int?, firmwareVersion: String?) {
        self.batteryLevel = batteryLevel
        self.firmwareVersion = firmwareVersion
    }
}

public enum RemoteDeviceInfoService {
    private static let batteryKeys = [
        "BatteryPercent",
        "BatteryLevel",
        "device_batteryLevelMain",
        "device_batteryLevel",
        "device_batteryPercent",
        "CurrentBatteryPercent",
    ]
    private static let firmwareKeys = [
        "kBTFirmwareRevisionKey",
        "device_firmwareVersion",
        "FirmwareVersion",
        "RadioFW Version",
        "BTFW Version",
        "STFW Version",
    ]

    public static func currentSnapshot() -> RemoteDeviceSnapshot? {
        if let snapshot = snapshotFromIORegistry(
            vendorID: XiaomiRemoteProfile.vendorID,
            productID: XiaomiRemoteProfile.productID,
            productName: XiaomiRemoteProfile.productName
        ) {
            return snapshot
        }
        return nil
    }

    public static func snapshotFromIORegistry(
        vendorID: Int,
        productID: Int,
        productName: String? = nil
    ) -> RemoteDeviceSnapshot? {
        let serviceClasses = [
            "IOHIDUserDevice",
            "IOHIDDevice",
            "AppleDeviceManagementHIDEventService",
            "AppleUserHIDEventService",
        ]
        var batteryLevel: Int?
        var firmwareVersion: String?

        for serviceClass in serviceClasses {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching(serviceClass),
                &iterator
            ) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }

            while case let entry = IOIteratorNext(iterator), entry != 0 {
                defer { IOObjectRelease(entry) }
                let matchesIdentifiers = parseIdentifier(property("VendorID", of: entry)) == vendorID
                    && parseIdentifier(property("ProductID", of: entry)) == productID
                let matchesName = productName != nil
                    && (property("Product", of: entry) as? String) == productName
                guard matchesIdentifiers || matchesName else {
                    continue
                }

                collectDeviceInfo(
                    from: entry,
                    remainingDescendantDepth: 3,
                    batteryLevel: &batteryLevel,
                    firmwareVersion: &firmwareVersion
                )

                if batteryLevel != nil && firmwareVersion != nil {
                    return RemoteDeviceSnapshot(batteryLevel: batteryLevel, firmwareVersion: firmwareVersion)
                }
            }
        }

        if batteryLevel != nil || firmwareVersion != nil {
            return RemoteDeviceSnapshot(batteryLevel: batteryLevel, firmwareVersion: firmwareVersion)
        }
        return nil
    }

    private static func collectDeviceInfo(
        from entry: io_registry_entry_t,
        remainingDescendantDepth: Int,
        batteryLevel: inout Int?,
        firmwareVersion: inout String?
    ) {
        if batteryLevel == nil {
            batteryLevel = batteryKeys.lazy.compactMap {
                parseLevel(property($0, of: entry))
            }.first
        }
        if firmwareVersion == nil {
            firmwareVersion = firmwareKeys.lazy.compactMap {
                parseFirmware(property($0, of: entry))
            }.first
        }
        guard remainingDescendantDepth > 0,
              batteryLevel == nil || firmwareVersion == nil else { return }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }
        while case let child = IOIteratorNext(iterator), child != 0 {
            collectDeviceInfo(
                from: child,
                remainingDescendantDepth: remainingDescendantDepth - 1,
                batteryLevel: &batteryLevel,
                firmwareVersion: &firmwareVersion
            )
            IOObjectRelease(child)
            if batteryLevel != nil && firmwareVersion != nil { return }
        }
    }

    private static func property(_ key: String, of entry: io_registry_entry_t) -> Any? {
        IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
    }

    private static func extractBattery(from dict: [String: Any]) -> Int? {
        batteryKeys.lazy.compactMap { parseLevel(dict[$0]) }.first
    }

    private static func extractFirmware(from dict: [String: Any]) -> String? {
        firmwareKeys.lazy.compactMap { parseFirmware(dict[$0]) }.first
    }

    static func snapshot(
        in data: Data,
        deviceName: String,
        vendorID: Int,
        productID: Int
    ) -> RemoteDeviceSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return snapshot(
            in: root,
            deviceName: deviceName,
            vendorID: vendorID,
            productID: productID
        )
    }

    private static func snapshot(
        in value: Any,
        deviceName: String,
        vendorID: Int,
        productID: Int
    ) -> RemoteDeviceSnapshot? {
        if let dictionary = value as? [String: Any] {
            if let device = dictionary[deviceName] as? [String: Any],
               let result = deviceSnapshot(from: device) {
                return result
            }
            if identifiersMatch(dictionary, vendorID: vendorID, productID: productID),
               let result = deviceSnapshot(from: dictionary) {
                return result
            }
            for child in dictionary.values {
                if let result = snapshot(
                    in: child,
                    deviceName: deviceName,
                    vendorID: vendorID,
                    productID: productID
                ) { return result }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let result = snapshot(
                    in: child,
                    deviceName: deviceName,
                    vendorID: vendorID,
                    productID: productID
                ) { return result }
            }
        }
        return nil
    }

    private static func deviceSnapshot(from device: [String: Any]) -> RemoteDeviceSnapshot? {
        let result = RemoteDeviceSnapshot(
            batteryLevel: extractBattery(from: device),
            firmwareVersion: extractFirmware(from: device)
        )
        return result.batteryLevel != nil || result.firmwareVersion != nil ? result : nil
    }

    private static func identifiersMatch(
        _ device: [String: Any],
        vendorID: Int,
        productID: Int
    ) -> Bool {
        parseIdentifier(device["VendorID"] ?? device["device_vendorID"]) == vendorID
            && parseIdentifier(device["ProductID"] ?? device["device_productID"]) == productID
    }

    private static func parseLevel(_ value: Any?) -> Int? {
        let level: Int?
        if let number = value as? NSNumber {
            level = number.intValue
        } else if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            level = trimmed.lowercased().hasPrefix("0x")
                ? Int(trimmed.dropFirst(2), radix: 16)
                : Int(trimmed.filter(\.isNumber))
        } else {
            level = nil
        }
        guard let level, (0...100).contains(level) else { return nil }
        return level
    }

    private static func parseFirmware(_ value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return (value as? NSNumber)?.stringValue
    }

    private static func parseIdentifier(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("0x") {
            return Int(trimmed.dropFirst(2).prefix(while: { $0.isHexDigit }), radix: 16)
        }
        return Int(trimmed.prefix(while: { $0.isNumber }))
    }
}
