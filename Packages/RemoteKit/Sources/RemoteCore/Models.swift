import Foundation

public enum RemoteButton: String, Codable, CaseIterable, Hashable, Sendable {
    case up, down, left, right
    case select, back, home, tv, menu
    case volumeUp, volumeDown, power, voice

    public var title: String {
        switch self {
        case .up: "上"
        case .down: "下"
        case .left: "左"
        case .right: "右"
        case .select: "确认"
        case .back: "返回"
        case .home: "主页"
        case .tv: "TV"
        case .menu: "菜单"
        case .volumeUp: "音量加"
        case .volumeDown: "音量减"
        case .power: "电源"
        case .voice: "语音"
        }
    }

    public var isRepeatable: Bool {
        switch self {
        case .up, .down, .left, .right, .volumeUp, .volumeDown: true
        case .select, .back, .home, .tv, .menu, .power, .voice: false
        }
    }
}

public enum RemoteTrigger: String, Codable, CaseIterable, Hashable, Sendable {
    case tap
    case hold
    case doubleTap

    public var title: String {
        switch self {
        case .tap: "单击"
        case .hold: "长按"
        case .doubleTap: "双击"
        }
    }
}

public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let control = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let shift = KeyModifiers(rawValue: 1 << 3)

    fileprivate var names: [String] {
        var result: [String] = []
        if contains(.command) { result.append("command") }
        if contains(.control) { result.append("control") }
        if contains(.option) { result.append("option") }
        if contains(.shift) { result.append("shift") }
        return result
    }

    fileprivate init(names: [String]) {
        var value: KeyModifiers = []
        for name in names {
            switch name {
            case "command": value.insert(.command)
            case "control": value.insert(.control)
            case "option": value.insert(.option)
            case "shift": value.insert(.shift)
            default: break
            }
        }
        self = value
    }
}

public struct KeyStroke: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: KeyModifiers

    public init(_ keyCode: UInt16, modifiers: KeyModifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum MediaCommand: String, Codable, Equatable, Sendable {
    case playPause, next, previous
}

public enum RemoteAction: Codable, Equatable, Sendable {
    case passThrough
    case keyStroke(KeyStroke)
    case systemDictation
    case systemVolume(delta: Float)
    case mute
    case media(MediaCommand)
    case launch(bundleIdentifier: String)
    case none

    public var title: String {
        switch self {
        case .passThrough: "透传"
        case .keyStroke(let key): "按键 \(key.keyCode)"
        case .systemDictation: "系统听写"
        case .systemVolume(let delta): delta > 0 ? "系统音量加" : "系统音量减"
        case .mute: "静音"
        case .media(.playPause): "播放／暂停"
        case .media(.next): "下一首"
        case .media(.previous): "上一首"
        case .launch: "启动应用"
        case .none: "不执行"
        }
    }

    public var shouldSuppressNativeEvent: Bool {
        if case .passThrough = self { return false }
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case type, keyCode, modifiers, delta, command, bundleIdentifier
    }

    private enum Kind: String, Codable {
        case passThrough, keyStroke, systemDictation, systemVolume, mute, media, launch, none
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .passThrough:
            self = .passThrough
        case .keyStroke:
            let keyCode = try container.decode(UInt16.self, forKey: .keyCode)
            let names = try container.decodeIfPresent([String].self, forKey: .modifiers) ?? []
            self = .keyStroke(KeyStroke(keyCode, modifiers: KeyModifiers(names: names)))
        case .systemDictation:
            self = .systemDictation
        case .systemVolume:
            self = .systemVolume(delta: try container.decode(Float.self, forKey: .delta))
        case .mute:
            self = .mute
        case .media:
            self = .media(try container.decode(MediaCommand.self, forKey: .command))
        case .launch:
            self = .launch(
                bundleIdentifier: try container.decode(String.self, forKey: .bundleIdentifier)
            )
        case .none:
            self = .none
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .passThrough:
            try container.encode(Kind.passThrough, forKey: .type)
        case .keyStroke(let stroke):
            try container.encode(Kind.keyStroke, forKey: .type)
            try container.encode(stroke.keyCode, forKey: .keyCode)
            if !stroke.modifiers.isEmpty {
                try container.encode(stroke.modifiers.names, forKey: .modifiers)
            }
        case .systemDictation:
            try container.encode(Kind.systemDictation, forKey: .type)
        case .systemVolume(let delta):
            try container.encode(Kind.systemVolume, forKey: .type)
            try container.encode(delta, forKey: .delta)
        case .mute:
            try container.encode(Kind.mute, forKey: .type)
        case .media(let command):
            try container.encode(Kind.media, forKey: .type)
            try container.encode(command, forKey: .command)
        case .launch(let bundleIdentifier):
            try container.encode(Kind.launch, forKey: .type)
            try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        case .none:
            try container.encode(Kind.none, forKey: .type)
        }
    }
}

public struct AppProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var bundleIdentifiers: [String]
    public var bindings: [RemoteButton: RemoteAction]
    public var holdBindings: [RemoteButton: RemoteAction]
    public var doubleTapBindings: [RemoteButton: RemoteAction]

    public init(
        id: String,
        name: String,
        bundleIdentifiers: [String],
        bindings: [RemoteButton: RemoteAction],
        holdBindings: [RemoteButton: RemoteAction] = [:],
        doubleTapBindings: [RemoteButton: RemoteAction] = [:]
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifiers = bundleIdentifiers
        self.bindings = bindings
        self.holdBindings = holdBindings
        self.doubleTapBindings = doubleTapBindings
    }

    public func action(for button: RemoteButton) -> RemoteAction {
        bindings[button] ?? .none
    }

    public func action(for button: RemoteButton, trigger: RemoteTrigger) -> RemoteAction {
        switch trigger {
        case .tap: bindings[button] ?? .none
        case .hold: holdBindings[button] ?? .none
        case .doubleTap: doubleTapBindings[button] ?? .none
        }
    }

    public func hasAction(for button: RemoteButton, trigger: RemoteTrigger) -> Bool {
        action(for: button, trigger: trigger) != .none
    }

    public var requiresNativePassThrough: Bool {
        [bindings, holdBindings, doubleTapBindings]
            .flatMap(\.values)
            .contains { action in
                if case .passThrough = action { return true }
                return false
            }
    }

    public mutating func setAction(
        _ action: RemoteAction,
        for button: RemoteButton,
        trigger: RemoteTrigger
    ) {
        var table = switch trigger {
        case .tap: bindings
        case .hold: holdBindings
        case .doubleTap: doubleTapBindings
        }
        if action == .none {
            table[button] = nil
        } else {
            table[button] = action
        }
        switch trigger {
        case .tap: bindings = table
        case .hold: holdBindings = table
        case .doubleTap: doubleTapBindings = table
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, bundleIdentifiers, bindings, holdBindings, doubleTapBindings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bundleIdentifiers = try container.decode([String].self, forKey: .bundleIdentifiers)
        bindings = Self.decodeBindings(from: container, forKey: .bindings)
        holdBindings = Self.decodeBindings(from: container, forKey: .holdBindings)
        doubleTapBindings = Self.decodeBindings(from: container, forKey: .doubleTapBindings)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(bundleIdentifiers, forKey: .bundleIdentifiers)
        try container.encode(Self.encodeBindings(bindings), forKey: .bindings)
        if !holdBindings.isEmpty {
            try container.encode(Self.encodeBindings(holdBindings), forKey: .holdBindings)
        }
        if !doubleTapBindings.isEmpty {
            try container.encode(Self.encodeBindings(doubleTapBindings), forKey: .doubleTapBindings)
        }
    }

    private static func decodeBindings(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> [RemoteButton: RemoteAction] {
        let values = (try? container.decodeIfPresent([String: RemoteAction].self, forKey: key)) ?? [:]
        return Dictionary(uniqueKeysWithValues: values.compactMap { name, action in
            RemoteButton(rawValue: name).map { ($0, action) }
        })
    }

    private static func encodeBindings(
        _ bindings: [RemoteButton: RemoteAction]
    ) -> [String: RemoteAction] {
        Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
    }
}

public struct AppIdentity: Equatable, Sendable {
    public var name: String
    public var bundleIdentifier: String?
    public var processIdentifier: Int32

    public init(name: String, bundleIdentifier: String?, processIdentifier: Int32) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }
}

public enum MacKeyCode {
    public static let returnKey: UInt16 = 36
    public static let space: UInt16 = 49
    public static let escape: UInt16 = 53
    public static let leftBracket: UInt16 = 33
    public static let comma: UInt16 = 43
    public static let h: UInt16 = 4
    public static let l: UInt16 = 37
    public static let o: UInt16 = 31
    public static let home: UInt16 = 115
    public static let up: UInt16 = 126
    public static let down: UInt16 = 125
    public static let left: UInt16 = 123
    public static let right: UInt16 = 124
}
