import Foundation

public enum VoiceInputProvider: String, Codable, CaseIterable, Equatable, Sendable {
    case typeless
    case systemDictation
    case disabled

    public var title: String {
        switch self {
        case .typeless: "Typeless"
        case .systemDictation: "macOS 系统听写"
        case .disabled: "关闭"
        }
    }
}

public struct RemoteGestureSettings: Codable, Equatable, Sendable {
    public var holdMilliseconds: Int
    public var doubleTapMilliseconds: Int
    public var debounceMilliseconds: Int

    public init(
        holdMilliseconds: Int = 350,
        doubleTapMilliseconds: Int = 250,
        debounceMilliseconds: Int = 30
    ) {
        self.holdMilliseconds = min(max(holdMilliseconds, 250), 800)
        self.doubleTapMilliseconds = min(max(doubleTapMilliseconds, 150), 500)
        self.debounceMilliseconds = min(max(debounceMilliseconds, 10), 100)
    }
}

public struct RemoteConfiguration: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var gestureSettings: RemoteGestureSettings
    public var voiceInputProvider: VoiceInputProvider

    public init(
        version: Int = Self.currentVersion,
        gestureSettings: RemoteGestureSettings = RemoteGestureSettings(),
        voiceInputProvider: VoiceInputProvider = .typeless
    ) {
        self.version = version
        self.gestureSettings = gestureSettings
        self.voiceInputProvider = voiceInputProvider
    }

    private enum CodingKeys: String, CodingKey {
        case version, gestureSettings, voiceInputProvider
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        gestureSettings = try container.decodeIfPresent(
            RemoteGestureSettings.self,
            forKey: .gestureSettings
        ) ?? RemoteGestureSettings()
        voiceInputProvider = try container.decodeIfPresent(
            VoiceInputProvider.self,
            forKey: .voiceInputProvider
        ) ?? .typeless
    }
}
