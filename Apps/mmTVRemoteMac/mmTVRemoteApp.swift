import AppKit
import SwiftUI

@main
struct mmTVRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        AppDelegate.model = model
    }

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView(model: model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .opacity(model.serviceEnabled ? 1 : 0.55)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.serviceEnabled ? "mmTV Remote 运行中" : "mmTV Remote 已暂停")
        }
        .menuBarExtraStyle(.window)

        Window("mmTV Remote", id: "dashboard") {
            DashboardView(model: model)
                .frame(minWidth: 720, minHeight: 560)
        }
        .defaultSize(width: 940, height: 780)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.model?.shutdown()
    }
}
