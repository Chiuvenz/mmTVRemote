import AppKit
import SwiftUI

struct AdaptedApplication: Identifiable {
    let name: String
    let bundleIdentifier: String
    let fallbackSymbol: String

    var id: String { bundleIdentifier }

    static let all: [AdaptedApplication] = [
        .init(name: "mmTV", bundleIdentifier: "com.mmtv.mac", fallbackSymbol: "tv.fill"),
        .init(name: "Finder", bundleIdentifier: "com.apple.finder", fallbackSymbol: "face.smiling"),
        .init(name: "Safari", bundleIdentifier: "com.apple.Safari", fallbackSymbol: "safari.fill"),
        .init(name: "Chrome", bundleIdentifier: "com.google.Chrome", fallbackSymbol: "globe"),
        .init(name: "Edge", bundleIdentifier: "com.microsoft.edgemac", fallbackSymbol: "globe"),
        .init(name: "Arc", bundleIdentifier: "company.thebrowser.Browser", fallbackSymbol: "globe"),
        .init(name: "IINA", bundleIdentifier: "com.colliderli.iina", fallbackSymbol: "play.rectangle.fill"),
    ]
}

struct ApplicationIconView: View {
    let bundleIdentifier: String?
    let fallbackSymbol: String
    let size: CGFloat

    private var applicationIcon: NSImage? {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
              ) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    var body: some View {
        Group {
            if let applicationIcon {
                Image(nsImage: applicationIcon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: size * 0.22))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
