import Foundation
import os
import Security

public enum KeychainError: LocalizedError, Equatable, Sendable {
    case unhandled(OSStatus)
    case invalidUTF8

    public var errorDescription: String? {
        switch self {
        case let .unhandled(status):
            "Keychain 操作失败 (OSStatus: \(status))"
        case .invalidUTF8:
            "Keychain 数据无法解码为 UTF-8 字符串"
        }
    }
}

public protocol KeychainStorage: Sendable {
    func save(_ value: String, account: String) throws
    func read(account: String) throws -> String?
    func delete(account: String) throws
}

public struct SystemKeychainStorage: KeychainStorage, Sendable {
    public let service: String

    public init(service: String = "com.sunweizhou.Vela4") {
        self.service = service
    }

    public func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            throw KeychainError.unhandled(deleteStatus)
        }

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unhandled(addStatus)
        }
    }

    public func read(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
        guard let data = item as? Data, let decoded = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidUTF8
        }
        return decoded
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unhandled(status)
        }
    }
}

public final class InMemoryKeychainStorage: KeychainStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: String] = [:]

    public init(initialEntries: [String: String] = [:]) {
        self.entries = initialEntries
    }

    public func save(_ value: String, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        entries[account] = value
    }

    public func read(account: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return entries[account]
    }

    public func delete(account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: account)
    }
}

/// Manages Coach API credentials exclusively in Keychain and performs a one-time purge-migration from UserDefaults.
public final class KeychainCredentialStore: @unchecked Sendable {
    public static let apiKeyAccount = "bodyseek.coach.apiKey"
    public static let legacyUserDefaultsAPIKey = "bodyseek.coach.apiKey"

    public static let live = KeychainCredentialStore(
        storage: SystemKeychainStorage(service: "com.sunweizhou.Vela4"),
        userDefaults: .standard
    )

    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "Keychain")

    private let storage: any KeychainStorage
    private let userDefaults: UserDefaults
    private let account: String
    private let legacyKey: String

    public init(
        storage: any KeychainStorage,
        userDefaults: UserDefaults = .standard,
        account: String = KeychainCredentialStore.apiKeyAccount,
        legacyKey: String = KeychainCredentialStore.legacyUserDefaultsAPIKey
    ) {
        self.storage = storage
        self.userDefaults = userDefaults
        self.account = account
        self.legacyKey = legacyKey
    }

    public func loadAPIKey() throws -> String {
        if let stored = try storage.read(account: account)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !stored.isEmpty {
            if userDefaults.string(forKey: legacyKey) != nil {
                userDefaults.removeObject(forKey: legacyKey)
            }
            return stored
        }

        if let legacy = userDefaults.string(forKey: legacyKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !legacy.isEmpty {
            try storage.save(legacy, account: account)
            userDefaults.removeObject(forKey: legacyKey)
            Self.logger.notice("Migrated legacy Coach API key from UserDefaults into Keychain and purged legacy key.")
            return legacy
        }

        return ""
    }

    public func saveAPIKey(_ rawKey: String) throws {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try storage.delete(account: account)
        } else {
            try storage.save(trimmed, account: account)
        }
        if userDefaults.object(forKey: legacyKey) != nil {
            userDefaults.removeObject(forKey: legacyKey)
        }
    }
}
