@preconcurrency import CoreGraphics
import Foundation
import RemoteCore

private func remoteRelayEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let remapper = Unmanaged<DeviceKeyRemapper>.fromOpaque(refcon).takeUnretainedValue()
    return MainActor.assumeIsolated {
        remapper.handleEventTap(type: type, event: event)
    }
}

@MainActor
public final class DeviceKeyRemapper {
    typealias Mapping = (source: UInt64, destination: UInt64)
    typealias HidutilRunner = (
        _ arguments: [String],
        _ captureOutput: Bool
    ) -> (succeeded: Bool, output: String)

    struct Relay: Equatable {
        let sourceUsage: UInt32
        let destinationUsage: UInt32
        let keyCode: Int64
        let button: RemoteButton
    }

    static let relayTable: [Relay] = [
        Relay(sourceUsage: 0x4A, destinationUsage: 0x69, keyCode: 107, button: .home),
        Relay(sourceUsage: 0x65, destinationUsage: 0x6A, keyCode: 113, button: .menu),
        Relay(sourceUsage: 0x35, destinationUsage: 0x6B, keyCode: 106, button: .tv),
        Relay(sourceUsage: 0x66, destinationUsage: 0x6C, keyCode: 64, button: .power),
        Relay(sourceUsage: 0x28, destinationUsage: 0x6D, keyCode: 79, button: .select),
        Relay(sourceUsage: 0x52, destinationUsage: 0x6E, keyCode: 80, button: .up),
        Relay(sourceUsage: 0x51, destinationUsage: 0x67, keyCode: 81, button: .down),
        Relay(sourceUsage: 0x50, destinationUsage: 0x68, keyCode: 105, button: .left),
        Relay(sourceUsage: 0x4F, destinationUsage: 0x53, keyCode: 71, button: .right),
        Relay(sourceUsage: 0x80, destinationUsage: 0x54, keyCode: 75, button: .volumeUp),
        Relay(sourceUsage: 0x81, destinationUsage: 0x55, keyCode: 67, button: .volumeDown),
        Relay(sourceUsage: 0x3E, destinationUsage: 0x6F, keyCode: 90, button: .voice),
    ]

    private static let relayByKeyCode = Dictionary(
        uniqueKeysWithValues: relayTable.map { ($0.keyCode, $0.button) }
    )
    private static let remappedButtons = Set(relayTable.map(\.button))

    public var onButton: ((RemoteButton, Bool) -> Void)?
    public var onLog: ((String) -> Void)?
    /// Keeps a relayed hardware event in the HID stream for integrations such as Typeless.
    public var shouldPassThrough: ((RemoteButton) -> Bool)?
    public private(set) var isInstalled = false
    public var activeRemappedButtons: Set<RemoteButton> {
        isInstalled ? Self.remappedButtons : []
    }

    private var isInstalling = false
    private var savedForeignMappings: [Mapping]?
    private var cleanupMonitor: Process?
    private var cleanupLifetime: FileHandle?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private let hidutilRunner: HidutilRunner?
    private let startsCleanupMonitor: Bool
    private let requiresEventTap: Bool
    nonisolated private static let hidutilLock = NSLock()

    public init() {
        hidutilRunner = nil
        startsCleanupMonitor = true
        requiresEventTap = true
    }

    init(
        hidutilRunner: HidutilRunner?,
        startsCleanupMonitor: Bool = false,
        requiresEventTap: Bool = false
    ) {
        self.hidutilRunner = hidutilRunner
        self.startsCleanupMonitor = startsCleanupMonitor
        self.requiresEventTap = requiresEventTap
    }

    isolated deinit {
        uninstall()
    }

    @discardableResult
    public func install() -> Bool {
        guard !isInstalling else { return false }
        isInstalling = true
        defer { isInstalling = false }

        guard !requiresEventTap || startEventTapIfNeeded() else {
            rollbackFailedInstall(restoring: savedForeignMappings)
            onLog?("无法创建按键接管监听，已保留系统原始按键")
            return false
        }

        let current = runHidutil(
            ["property", "--matching", Self.matching, "--get", "UserKeyMapping"],
            captureOutput: true
        )
        guard current.succeeded,
              let existing = Self.parseUserKeyMapping(current.output) else {
            rollbackFailedInstall(restoring: savedForeignMappings)
            onLog?("无法读取设备按键映射，已保留系统原始按键")
            return false
        }

        let ownSources = Set(Self.ownMappings.map(\.source))
        let foreign = existing.filter { !ownSources.contains($0.source) }
        if savedForeignMappings == nil { savedForeignMappings = foreign }

        let result = runHidutil(
            ["property", "--matching", Self.matching, "--set", Self.mappingJSON(Self.ownMappings + foreign)],
            captureOutput: false
        )
        guard result.succeeded else {
            rollbackFailedInstall(restoring: savedForeignMappings ?? foreign)
            onLog?("遥控器原始按键接管失败")
            return false
        }

        isInstalled = true
        if startsCleanupMonitor {
            startCleanupMonitorIfNeeded(restoring: savedForeignMappings ?? foreign)
        }
        onLog?("已接管遥控器原始按键")
        return true
    }

    @discardableResult
    public func installAsync() async -> Bool {
        guard !isInstalling else { return false }
        isInstalling = true
        defer { isInstalling = false }

        guard !requiresEventTap || startEventTapIfNeeded() else {
            await rollbackFailedInstallAsync(restoring: savedForeignMappings)
            onLog?("无法创建按键接管监听，已保留系统原始按键")
            return false
        }

        let current = await runHidutilAsync(
            ["property", "--matching", Self.matching, "--get", "UserKeyMapping"],
            captureOutput: true
        )
        guard !Task.isCancelled else {
            stopEventTap()
            return false
        }
        guard current.succeeded,
              let existing = Self.parseUserKeyMapping(current.output) else {
            await rollbackFailedInstallAsync(restoring: savedForeignMappings)
            onLog?("无法读取设备按键映射，已保留系统原始按键")
            return false
        }

        let ownSources = Set(Self.ownMappings.map(\.source))
        let foreign = existing.filter { !ownSources.contains($0.source) }
        if savedForeignMappings == nil { savedForeignMappings = foreign }

        let result = await runHidutilAsync(
            ["property", "--matching", Self.matching, "--set", Self.mappingJSON(Self.ownMappings + foreign)],
            captureOutput: false
        )
        guard !Task.isCancelled else { return false }
        guard result.succeeded else {
            await rollbackFailedInstallAsync(restoring: savedForeignMappings ?? foreign)
            onLog?("遥控器原始按键接管失败")
            return false
        }

        isInstalled = true
        if startsCleanupMonitor {
            startCleanupMonitorIfNeeded(restoring: savedForeignMappings ?? foreign)
        }
        onLog?("已接管遥控器原始按键")
        return true
    }

    public func uninstall() {
        let shouldRestore = isInstalled || savedForeignMappings != nil
        let mappings = savedForeignMappings ?? []
        stopEventTap()
        stopCleanupMonitor()
        isInstalled = false
        guard shouldRestore else { return }

        let result = runHidutil(
            ["property", "--matching", Self.matching, "--set", Self.mappingJSON(mappings)],
            captureOutput: false
        )
        if result.succeeded {
            savedForeignMappings = nil
        } else {
            savedForeignMappings = mappings
            if startsCleanupMonitor { startCleanupMonitorIfNeeded(restoring: mappings) }
            onLog?("恢复遥控器原始按键映射失败")
        }
    }

    public func uninstallAsync() async {
        let shouldRestore = isInstalled || savedForeignMappings != nil
        let mappings = savedForeignMappings ?? []
        stopEventTap()
        stopCleanupMonitor()
        isInstalled = false
        guard shouldRestore else { return }

        let result = await runHidutilAsync(
            ["property", "--matching", Self.matching, "--set", Self.mappingJSON(mappings)],
            captureOutput: false
        )
        guard !Task.isCancelled else { return }
        if result.succeeded {
            savedForeignMappings = nil
        } else {
            savedForeignMappings = mappings
            if startsCleanupMonitor { startCleanupMonitorIfNeeded(restoring: mappings) }
            onLog?("恢复遥控器原始按键映射失败")
        }
    }

    static var ownMappings: [Mapping] {
        relayTable.map {
            (
                source: 0x700000000 + UInt64($0.sourceUsage),
                destination: 0x700000000 + UInt64($0.destinationUsage)
            )
        }
    }

    static func parseUserKeyMapping(_ text: String) -> [Mapping]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("(null)") { return [] }
        if !trimmed.contains("{") {
            if let open = trimmed.firstIndex(of: "("),
               let close = trimmed.lastIndex(of: ")"),
               open < close,
               trimmed[trimmed.index(after: open)..<close]
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return []
            }
            return nil
        }

        var mappings: [Mapping] = []
        var remaining = Substring(trimmed)
        while let open = remaining.firstIndex(of: "{") {
            guard let close = remaining[open...].firstIndex(of: "}") else { return nil }
            let block = remaining[open...close]
            guard let source = number(after: "HIDKeyboardModifierMappingSrc", in: block),
                  let destination = number(after: "HIDKeyboardModifierMappingDst", in: block) else {
                return nil
            }
            mappings.append((source, destination))
            remaining = remaining[remaining.index(after: close)...]
        }
        return mappings
    }

    private static var matching: String {
        #"{"VendorID":10007,"ProductID":12984}"#
    }

    private static func number(after key: String, in block: Substring) -> UInt64? {
        guard let range = block.range(of: key) else { return nil }
        let afterKey = block[range.upperBound...]
        guard let valueStart = afterKey.firstIndex(where: { $0.isNumber }) else { return nil }
        let value = afterKey[valueStart...]
        if value.lowercased().hasPrefix("0x") {
            let hexDigits = value.dropFirst(2).prefix(while: { $0.isHexDigit })
            return UInt64(hexDigits, radix: 16)
        }
        let digits = value.prefix(while: { $0.isNumber })
        return UInt64(digits)
    }

    private static func mappingJSON(_ mappings: [Mapping]) -> String {
        let entries = mappings.map {
            "{\"HIDKeyboardModifierMappingSrc\":\($0.source),\"HIDKeyboardModifierMappingDst\":\($0.destination)}"
        }
        return "{\"UserKeyMapping\":[\(entries.joined(separator: ","))]}"
    }

    nonisolated static func executeHidutil(
        _ arguments: [String],
        captureOutput: Bool
    ) -> (succeeded: Bool, output: String) {
        hidutilLock.lock()
        defer { hidutilLock.unlock() }
        guard !Task.isCancelled else { return (false, "") }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        process.standardOutput = captureOutput ? pipe : FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (false, "")
        }
        let data = captureOutput ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        process.waitUntilExit()
        return (
            process.terminationStatus == 0,
            String(data: data, encoding: .utf8) ?? ""
        )
    }

    private func runHidutil(
        _ arguments: [String],
        captureOutput: Bool
    ) -> (succeeded: Bool, output: String) {
        if let hidutilRunner { return hidutilRunner(arguments, captureOutput) }
        let result = Self.executeHidutil(arguments, captureOutput: captureOutput)
        if !result.succeeded && !captureOutput {
            onLog?("hidutil 执行失败")
        }
        return result
    }

    private func runHidutilAsync(
        _ arguments: [String],
        captureOutput: Bool
    ) async -> (succeeded: Bool, output: String) {
        if let hidutilRunner { return hidutilRunner(arguments, captureOutput) }
        let operation = Task.detached(priority: .userInitiated) {
            Self.executeHidutil(arguments, captureOutput: captureOutput)
        }
        return await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
        }
    }

    private func rollbackFailedInstall(restoring mappings: [Mapping]?) {
        stopEventTap()
        stopCleanupMonitor()
        isInstalled = false
        guard let mappings else {
            savedForeignMappings = nil
            return
        }
        savedForeignMappings = mappings
        let result = runHidutil(
            ["property", "--matching", Self.matching, "--set", Self.mappingJSON(mappings)],
            captureOutput: false
        )
        if result.succeeded {
            savedForeignMappings = nil
        } else if startsCleanupMonitor {
            startCleanupMonitorIfNeeded(restoring: mappings)
        }
    }

    private func rollbackFailedInstallAsync(restoring mappings: [Mapping]?) async {
        stopEventTap()
        stopCleanupMonitor()
        isInstalled = false
        guard let mappings else {
            savedForeignMappings = nil
            return
        }
        savedForeignMappings = mappings
        let result = await runHidutilAsync(
            ["property", "--matching", Self.matching, "--set", Self.mappingJSON(mappings)],
            captureOutput: false
        )
        guard !Task.isCancelled else { return }
        if result.succeeded {
            savedForeignMappings = nil
        } else if startsCleanupMonitor {
            startCleanupMonitorIfNeeded(restoring: mappings)
        }
    }

    private func startCleanupMonitorIfNeeded(restoring mappings: [Mapping]) {
        guard cleanupMonitor == nil else { return }
        let lifetime = Pipe()
        let monitor = Process()
        let command = "while IFS= read -r line; do :; done; "
            + "/usr/bin/hidutil property --matching '\(Self.matching)' "
            + "--set '\(Self.mappingJSON(mappings))' >/dev/null 2>&1"
        monitor.executableURL = URL(fileURLWithPath: "/bin/sh")
        monitor.arguments = ["-c", command]
        monitor.standardInput = lifetime
        monitor.standardOutput = FileHandle.nullDevice
        monitor.standardError = FileHandle.nullDevice
        do {
            try monitor.run()
            try? lifetime.fileHandleForReading.close()
            cleanupMonitor = monitor
            cleanupLifetime = lifetime.fileHandleForWriting
        } catch {
            try? lifetime.fileHandleForReading.close()
            try? lifetime.fileHandleForWriting.close()
            onLog?("无法启动按键映射恢复守护：\(error.localizedDescription)")
        }
    }

    private func stopCleanupMonitor() {
        cleanupMonitor?.terminate()
        try? cleanupLifetime?.close()
        cleanupMonitor = nil
        cleanupLifetime = nil
    }

    private func startEventTapIfNeeded() -> Bool {
        if let eventTap, CGEvent.tapIsEnabled(tap: eventTap) { return true }
        stopEventTap()
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.tapDisabledByTimeout.rawValue)
            | (CGEventMask(1) << CGEventType.tapDisabledByUserInput.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: remoteRelayEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        eventTapSource = source
        return CGEvent.tapIsEnabled(tap: tap)
    }

    private func stopEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        eventTap = nil
        eventTapSource = nil
    }

    func handleEventTap(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard let button = Self.relayByKeyCode[keyCode] else {
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
        onButton?(button, type == .keyDown)
        return shouldPassThrough?(button) == true
            ? Unmanaged.passUnretained(event)
            : nil
    }
}
