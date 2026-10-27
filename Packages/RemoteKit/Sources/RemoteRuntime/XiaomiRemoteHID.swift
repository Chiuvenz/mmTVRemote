import Foundation
import IOKit.hid
import RemoteCore

private func remoteDeviceMatched(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    let instance = Unmanaged<XiaomiRemoteHID>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { instance.deviceMatched(result: result) }
}

private func remoteDeviceRemoved(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    let instance = Unmanaged<XiaomiRemoteHID>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { instance.deviceRemoved(result: result) }
}

private func remoteValueReceived(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard let context else { return }
    let instance = Unmanaged<XiaomiRemoteHID>.fromOpaque(context).takeUnretainedValue()
    let transferred = UnsafeTransfer(value: value)
    MainActor.assumeIsolated {
        instance.valueReceived(transferred.value, result: result)
    }
}

private func remoteInputReportReceived(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context else { return }
    let instance = Unmanaged<XiaomiRemoteHID>.fromOpaque(context).takeUnretainedValue()
    let bytes = Array(UnsafeBufferPointer(start: report, count: max(0, reportLength)))
    MainActor.assumeIsolated {
        instance.inputReportReceived(
            result: result,
            type: type,
            reportID: reportID,
            bytes: bytes
        )
    }
}

private struct UnsafeTransfer<Value>: @unchecked Sendable {
    let value: Value
}

@MainActor
public final class XiaomiRemoteHID {
    public var onButton: ((RemoteButton, Bool) -> Void)?
    public var onConnectionChanged: ((Bool) -> Void)?
    public var onUnknownUsage: ((UInt32, Bool) -> Void)?
    public var onVoiceReport: ((RemoteVoiceReport) -> Void)?

    public private(set) var isConnected = false

    private var manager: IOHIDManager?
    private var reportUsages: Set<UInt32> = []
    private var reportFlushScheduled = false
    private var rawReportsObserved = false
    private var stateTracker = RemoteHIDStateTracker()
    private let openOptions = IOOptionBits(kIOHIDOptionsTypeNone)

    public init() {}

    isolated deinit {
        stop()
    }

    public func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, openOptions)
        self.manager = manager
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: XiaomiRemoteProfile.vendorID,
            kIOHIDProductIDKey: XiaomiRemoteProfile.productID,
        ] as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, remoteDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, remoteDeviceRemoved, context)
        IOHIDManagerRegisterInputValueCallback(manager, remoteValueReceived, context)
        IOHIDManagerRegisterInputReportCallback(manager, remoteInputReportReceived, context)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        guard IOHIDManagerOpen(manager, openOptions) == kIOReturnSuccess else {
            stop()
            return
        }

        let count = IOHIDManagerCopyDevices(manager).map(CFSetGetCount) ?? 0
        if count > 0 { setConnected(true) }
    }

    public func stop() {
        process(usages: [])
        reportUsages.removeAll()
        reportFlushScheduled = false
        rawReportsObserved = false
        stateTracker.reset()
        setConnected(false)
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        IOHIDManagerClose(manager, openOptions)
        self.manager = nil
    }

    fileprivate func deviceMatched(result: IOReturn) {
        guard result == kIOReturnSuccess else { return }
        setConnected(true)
    }

    fileprivate func deviceRemoved(result: IOReturn) {
        guard result == kIOReturnSuccess else { return }
        process(usages: [])
        reportUsages.removeAll()
        stateTracker.reset()
        setConnected(false)
    }

    fileprivate func valueReceived(_ value: IOHIDValue, result: IOReturn) {
        guard result == kIOReturnSuccess else { return }
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == 0x07 else { return }

        let usage = IOHIDElementGetUsage(element)
        let integerValue = IOHIDValueGetIntegerValue(value)
        let length = IOHIDValueGetLength(value)
        if usage == UInt32.max,
           length >= RemoteHIDReportParser.keyboardArrayPayloadLength {
            let pointer = IOHIDValueGetBytePtr(value)
            let bytes = Array(UnsafeBufferPointer(start: pointer, count: length))
            reportUsages.formUnion(
                RemoteHIDReportParser.keyboardArrayUsages(bytes: bytes) ?? []
            )
        } else if let resolved = RemoteHIDReportParser.keyboardUsage(
            elementUsage: usage,
            integerValue: integerValue
        ) {
            reportUsages.insert(resolved)
        }

        guard !reportFlushScheduled else { return }
        reportFlushScheduled = true
        DispatchQueue.main.async { [weak self] in self?.flushValueReport() }
    }

    fileprivate func inputReportReceived(
        result: IOReturn,
        type: IOHIDReportType,
        reportID: UInt32,
        bytes: [UInt8]
    ) {
        guard result == kIOReturnSuccess,
              type == kIOHIDReportTypeInput,
              !bytes.isEmpty else { return }

        if (6...8).contains(reportID) {
            onVoiceReport?(RemoteVoiceReport(
                reportID: reportID,
                bytes: bytes,
                timestamp: .now
            ))
            return
        }

        guard let usages = RemoteHIDReportParser.keyboardUsages(
            reportID: reportID,
            bytes: bytes
        ) else { return }
        rawReportsObserved = true
        process(usages: usages)
    }

    private func flushValueReport() {
        reportFlushScheduled = false
        defer { reportUsages.removeAll() }
        guard !rawReportsObserved else { return }
        process(usages: reportUsages)
    }

    private func process(usages: Set<UInt32>) {
        for change in stateTracker.update(with: usages) {
            if let button = XiaomiRemoteProfile.button(
                usagePage: 0x07,
                usage: change.usage
            ) {
                onButton?(button, change.isDown)
            } else {
                onUnknownUsage?(change.usage, change.isDown)
            }
        }
    }

    private func setConnected(_ connected: Bool) {
        guard connected != isConnected else { return }
        isConnected = connected
        onConnectionChanged?(connected)
    }
}
