import Foundation
import RemoteCore

public enum ConfigurationStoreError: LocalizedError, Equatable {
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "当前版本无法读取配置版本 \(version)"
        }
    }
}

public struct ConfigurationStore {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(
        fileURL: URL = ProfileStore.applicationSupportDirectory
            .appendingPathComponent("config.json"),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> RemoteConfiguration {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return RemoteConfiguration()
        }
        let data = try Data(contentsOf: fileURL)
        let configuration = try JSONDecoder().decode(RemoteConfiguration.self, from: data)
        guard configuration.version == RemoteConfiguration.currentVersion else {
            throw ConfigurationStoreError.unsupportedVersion(configuration.version)
        }
        return configuration
    }

    public func save(_ configuration: RemoteConfiguration) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: fileURL, options: .atomic)
    }

    public func makeRecoveryCopy() throws -> URL? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let directory = fileURL.deletingLastPathComponent()
            .appendingPathComponent("Recovery", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("config-unreadable.json")
        if !fileManager.fileExists(atPath: destination.path) {
            try fileManager.copyItem(at: fileURL, to: destination)
        }
        return destination
    }
}
