import AppKit
import Foundation
import RemoteCore

@MainActor
public final class FrontmostApplicationMonitor {
    public var onChange: ((AppIdentity) -> Void)?
    public private(set) var current: AppIdentity?

    private var observer: NSObjectProtocol?
    private let excludedBundleIdentifier: String?

    public init(excludedBundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        self.excludedBundleIdentifier = excludedBundleIdentifier
    }

    public func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            Task { @MainActor in self?.receive(app) }
        }
        if let app = NSWorkspace.shared.frontmostApplication {
            receive(app)
        }
    }

    public func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    private func receive(_ app: NSRunningApplication) {
        guard app.bundleIdentifier != excludedBundleIdentifier else { return }
        let identity = AppIdentity(
            name: app.localizedName ?? app.bundleIdentifier ?? "未知应用",
            bundleIdentifier: app.bundleIdentifier,
            processIdentifier: app.processIdentifier
        )
        guard identity != current else { return }
        current = identity
        onChange?(identity)
    }
}
