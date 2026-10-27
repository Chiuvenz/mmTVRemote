import AppKit
import ApplicationServices
import CoreGraphics
import RemoteCore

public enum ActionExecutionResult: Equatable, Sendable {
    case completed(String)
    case skipped(String)
    case failed(String)
}

@MainActor
public final class ActionExecutor {
    public init() {}

    public func execute(_ action: RemoteAction) -> ActionExecutionResult {
        switch action {
        case .passThrough:
            return .skipped("由目标应用直接处理")
        case .none:
            return .skipped("当前 Profile 未分配动作")
        case .keyStroke(let stroke):
            guard InputAccess.accessibilityTrusted else {
                return .failed("需要辅助功能权限")
            }
            return post(stroke)
                ? .completed("已发送 \(action.title)")
                : .failed("按键发送失败")
        case .systemDictation:
            guard InputAccess.accessibilityTrusted else {
                return .failed("需要辅助功能权限")
            }
            return startSystemDictation()
                ? .completed("已开始 macOS 系统听写")
                : .failed("无法启动系统听写")
        case .systemVolume(let delta):
            guard let value = SystemVolumeController.adjust(by: delta) else {
                return .failed("当前输出设备不支持软件音量")
            }
            return .completed("系统音量 \(Int((value * 100).rounded()))%")
        case .mute:
            guard let muted = SystemVolumeController.toggleMute() else {
                return .failed("当前输出设备不支持软件静音")
            }
            return .completed(muted ? "已静音" : "已取消静音")
        case .media(let command):
            postMedia(command)
            return .completed(action.title)
        case .launch(let bundleIdentifier):
            guard let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ) else {
                return .failed("找不到应用 \(bundleIdentifier)")
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return .completed("正在启动 \(url.deletingPathExtension().lastPathComponent)")
        }
    }

    private func post(_ stroke: KeyStroke) -> Bool {
        guard let down = CGEvent.remoteKeyboardEvent(keyCode: stroke.keyCode, keyDown: true),
              let up = CGEvent.remoteKeyboardEvent(keyCode: stroke.keyCode, keyDown: false) else {
            return false
        }
        let flags = cgFlags(from: stroke.modifiers)
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private func startSystemDictation() -> Bool {
        if let application = NSWorkspace.shared.frontmostApplication,
           application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           pressMenuItem(withCommandGlyph: 150, in: application.processIdentifier) {
            return true
        }

        guard postFunctionKey() else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
            _ = self?.postFunctionKey()
        }
        return true
    }

    private func postFunctionKey() -> Bool {
        guard let down = CGEvent.remoteKeyboardEvent(keyCode: 63, keyDown: true),
              let up = CGEvent.remoteKeyboardEvent(keyCode: 63, keyDown: false) else {
            return false
        }
        down.flags = .maskSecondaryFn
        up.flags = .maskSecondaryFn
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private func pressMenuItem(withCommandGlyph glyph: Int, in processIdentifier: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let menuBarValue = accessibilityValue(
            of: application,
            attribute: kAXMenuBarAttribute as CFString
        ), CFGetTypeID(menuBarValue) == AXUIElementGetTypeID() else {
            return false
        }
        let menuBar = unsafeDowncast(menuBarValue, to: AXUIElement.self)
        guard let item = descendantMenuItem(in: menuBar, commandGlyph: glyph, depth: 6) else {
            return false
        }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    private func descendantMenuItem(
        in element: AXUIElement,
        commandGlyph: Int,
        depth: Int
    ) -> AXUIElement? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXMenuItemCmdGlyphAttribute as CFString,
            &value
        ) == .success,
           let number = value as? NSNumber,
           number.intValue == commandGlyph {
            return element
        }
        guard depth > 0 else { return nil }
        value = nil
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success,
        let children = value as? [AXUIElement] else { return nil }
        for child in children {
            if let result = descendantMenuItem(
                in: child,
                commandGlyph: commandGlyph,
                depth: depth - 1
            ) {
                return result
            }
        }
        return nil
    }

    private func accessibilityValue(
        of element: AXUIElement,
        attribute: CFString
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private func cgFlags(from modifiers: KeyModifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        return flags
    }

    private func postMedia(_ command: MediaCommand) {
        let keyType: Int32 = switch command {
        case .playPause: 16
        case .next: 17
        case .previous: 18
        }
        for (isDown, state) in [(true, 0xA00), (false, 0xB00)] {
            let data1 = Int((keyType << 16) | Int32(state))
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: isDown ? .init(rawValue: 0xA00) : .init(rawValue: 0xB00),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
