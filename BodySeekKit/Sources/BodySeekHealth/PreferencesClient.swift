import BodySeekCore
import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct PreferencesClient: Sendable {
    public var load: @Sendable () throws -> AppPreferencesState = { AppPreferencesState() }
    public var save: @Sendable (_ state: AppPreferencesState) throws -> Void
    public var reset: @Sendable () throws -> Void
}

extension PreferencesClient: DependencyKey {
    private static var storageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("BodySeek", isDirectory: true)
            .appendingPathComponent("preferences_v3.json")
    }

    public static let liveValue = PreferencesClient(
        load: {
            let url = storageURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                return AppPreferencesState()
            }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(AppPreferencesState.self, from: data)
        },
        save: { state in
            let url = storageURL
            let dir = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: .atomic)
        },
        reset: {
            let url = storageURL
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    )

    public static let previewValue = PreferencesClient(
        load: { AppPreferencesState() },
        save: { _ in },
        reset: {}
    )
}

public extension DependencyValues {
    var preferencesClient: PreferencesClient {
        get { self[PreferencesClient.self] }
        set { self[PreferencesClient.self] = newValue }
    }
}
