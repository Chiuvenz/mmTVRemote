import Foundation
import RemoteCore

public struct ProfileLoadResult: Sendable {
    public let profiles: [AppProfile]
    public let recoveredFiles: [URL]

    public init(profiles: [AppProfile], recoveredFiles: [URL]) {
        self.profiles = profiles
        self.recoveredFiles = recoveredFiles
    }
}

public struct ProfileStore {
    public let directory: URL
    private let fileManager: FileManager

    public init(
        directory: URL = Self.profilesDirectory,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public func loadUserProfiles() -> [AppProfile] {
        load().profiles
    }

    public func load() -> ProfileLoadResult {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return ProfileLoadResult(profiles: [], recoveredFiles: []) }

        let decoder = JSONDecoder()
        var profiles: [AppProfile] = []
        var recovered: [URL] = []
        for url in urls
            .filter({ $0.pathExtension.lowercased() == "json" })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let data = try Data(contentsOf: url)
                profiles.append(try decoder.decode(AppProfile.self, from: data))
            } catch {
                if let recoveryURL = try? makeRecoveryCopy(of: url) {
                    recovered.append(recoveryURL)
                }
            }
        }
        return ProfileLoadResult(profiles: profiles, recoveredFiles: recovered)
    }

    public func save(_ profile: AppProfile) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(profile)
        try data.write(to: fileURL(for: profile.id), options: .atomic)
    }

    public func remove(profileID: String) throws {
        let url = fileURL(for: profileID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        _ = try makeRecoveryCopy(of: url, suffix: "removed")
        try fileManager.removeItem(at: url)
    }

    public func fileURL(for profileID: String) -> URL {
        let safeName = profileID
            .map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" }
        return directory.appendingPathComponent(String(safeName) + ".json")
    }

    private func makeRecoveryCopy(of source: URL, suffix: String = "unreadable") throws -> URL {
        let recoveryDirectory = directory.appendingPathComponent("Recovery", isDirectory: true)
        try fileManager.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        let destination = recoveryDirectory.appendingPathComponent(
            source.deletingPathExtension().lastPathComponent + ".\(suffix).json"
        )
        if !fileManager.fileExists(atPath: destination.path) {
            try fileManager.copyItem(at: source, to: destination)
        }
        return destination
    }

    public static var profilesDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Profiles", isDirectory: true)
    }

    public static var applicationSupportDirectory: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return support.appendingPathComponent("mmTV Remote", isDirectory: true)
    }
}
