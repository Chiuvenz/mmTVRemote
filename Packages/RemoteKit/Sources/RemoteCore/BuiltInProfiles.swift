import Foundation

public enum BuiltInProfiles {
    public static let all: [AppProfile] = [mmTV, iina, finder, browser, defaultProfile]

    public static let defaultProfile = AppProfile(
        id: "default",
        name: "默认桌面",
        bundleIdentifiers: [],
        bindings: standardBindings()
    )

    /// mmTV owns the raw HID device itself. The global service must stay silent to avoid duplicates.
    public static let mmTV = AppProfile(
        id: "mmtv",
        name: "mmTV",
        bundleIdentifiers: ["com.mmtv.mac"],
        bindings: Dictionary(uniqueKeysWithValues: RemoteButton.allCases.map { ($0, .none) })
    )

    public static let iina = AppProfile(
        id: "iina",
        name: "IINA",
        bundleIdentifiers: ["com.colliderli.iina"],
        bindings: merging(standardBindings(), with: [
            .select: .keyStroke(KeyStroke(MacKeyCode.space)),
            .back: .keyStroke(KeyStroke(MacKeyCode.escape)),
        ])
    )

    public static let finder = AppProfile(
        id: "finder",
        name: "Finder",
        bundleIdentifiers: ["com.apple.finder"],
        bindings: merging(standardBindings(), with: [
            .select: .keyStroke(KeyStroke(MacKeyCode.o, modifiers: .command)),
            .back: .keyStroke(KeyStroke(MacKeyCode.up, modifiers: .command)),
            .home: .keyStroke(KeyStroke(MacKeyCode.h, modifiers: [.command, .shift])),
        ])
    )

    public static let browser = AppProfile(
        id: "browser",
        name: "浏览器",
        bundleIdentifiers: [
            "com.apple.Safari",
            "com.google.Chrome",
            "com.microsoft.edgemac",
            "company.thebrowser.Browser",
        ],
        bindings: merging(standardBindings(), with: [
            .back: .keyStroke(KeyStroke(MacKeyCode.leftBracket, modifiers: .command)),
        ])
    )

    private static func standardBindings() -> [RemoteButton: RemoteAction] {
        [
            .up: .keyStroke(KeyStroke(MacKeyCode.up)),
            .down: .keyStroke(KeyStroke(MacKeyCode.down)),
            .left: .keyStroke(KeyStroke(MacKeyCode.left)),
            .right: .keyStroke(KeyStroke(MacKeyCode.right)),
            .select: .keyStroke(KeyStroke(MacKeyCode.returnKey)),
            .back: .keyStroke(KeyStroke(MacKeyCode.escape)),
            .home: .keyStroke(KeyStroke(MacKeyCode.home)),
            .tv: .launch(bundleIdentifier: "com.mmtv.mac"),
            .menu: .none,
            .volumeUp: .systemVolume(delta: 0.0625),
            .volumeDown: .systemVolume(delta: -0.0625),
            .power: .none,
            .voice: .none,
        ]
    }

    private static func merging(
        _ base: [RemoteButton: RemoteAction],
        with overrides: [RemoteButton: RemoteAction]
    ) -> [RemoteButton: RemoteAction] {
        base.merging(overrides) { _, new in new }
    }
}

public struct ProfileResolver: Sendable {
    public var builtInProfiles: [AppProfile]
    public var userProfiles: [AppProfile]

    public init(
        builtInProfiles: [AppProfile] = BuiltInProfiles.all,
        userProfiles: [AppProfile] = []
    ) {
        self.builtInProfiles = builtInProfiles
        self.userProfiles = userProfiles
    }

    public func resolve(bundleIdentifier: String?) -> AppProfile {
        if let bundleIdentifier {
            if let user = userProfiles.first(where: { $0.bundleIdentifiers.contains(bundleIdentifier) }) {
                return user
            }
            if let builtIn = builtInProfiles.first(where: { $0.bundleIdentifiers.contains(bundleIdentifier) }) {
                return builtIn
            }
        }
        return userProfiles.first(where: { $0.bundleIdentifiers.isEmpty })
            ?? builtInProfiles.first(where: { $0.bundleIdentifiers.isEmpty })
            ?? BuiltInProfiles.defaultProfile
    }
}
