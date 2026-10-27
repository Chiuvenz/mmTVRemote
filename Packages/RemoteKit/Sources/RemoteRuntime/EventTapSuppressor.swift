import CoreGraphics
import Foundation

private let remoteSyntheticMarker: Int64 = 0x4D4D545652454D

private func remoteEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let suppressor = Unmanaged<EventTapSuppressor>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        suppressor.reenable()
        return Unmanaged.passUnretained(event)
    }
    if event.getIntegerValueField(.eventSourceUserData) == remoteSyntheticMarker {
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown || type == .keyUp else {
        return Unmanaged.passUnretained(event)
    }
    let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let shouldSuppress = suppressor.consumeIfPending(keyCode: code, isPressed: type == .keyDown)
    return shouldSuppress ? nil : Unmanaged.passUnretained(event)
}

public final class EventTapSuppressor: @unchecked Sendable {
    private struct Pending {
        let keyCode: UInt16
        let isPressed: Bool
        let time: TimeInterval
    }

    private let lock = NSLock()
    private var pending: [Pending] = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    public init() {}

    public var isRunning: Bool {
        lock.withLock { tap != nil }
    }

    public func start() -> Bool {
        if isRunning { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: remoteEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        lock.withLock {
            self.tap = tap
            self.source = source
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stop() {
        let old: (CFMachPort?, CFRunLoopSource?) = lock.withLock {
            let value = (tap, source)
            tap = nil
            source = nil
            pending.removeAll()
            return value
        }
        if let source = old.1 {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = old.0 { CFMachPortInvalidate(tap) }
    }

    public func expectNativeEvent(keyCode: UInt16, isPressed: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.withLock {
            pending.removeAll { now - $0.time > 0.2 }
            pending.append(Pending(keyCode: keyCode, isPressed: isPressed, time: now))
            if pending.count > 24 { pending.removeFirst(pending.count - 24) }
        }
    }

    fileprivate func consumeIfPending(keyCode: UInt16, isPressed: Bool) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        return lock.withLock {
            pending.removeAll { now - $0.time > 0.2 }
            guard let index = pending.firstIndex(where: {
                $0.keyCode == keyCode && $0.isPressed == isPressed && now - $0.time < 0.12
            }) else { return false }
            pending.remove(at: index)
            return true
        }
    }

    fileprivate func reenable() {
        guard let tap = lock.withLock({ tap }) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

extension CGEvent {
    static func remoteKeyboardEvent(keyCode: UInt16, keyDown: Bool) -> CGEvent? {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(keyCode),
                keyDown: keyDown
              ) else { return nil }
        event.setIntegerValueField(.eventSourceUserData, value: remoteSyntheticMarker)
        return event
    }
}
