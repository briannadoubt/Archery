import Foundation
#if canImport(Security)
import Security
#endif

public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}

public protocol KeychainStoring: Sendable {
    func set(_ data: Data, for key: String) throws
    func data(for key: String) throws -> Data?
    func remove(_ key: String) throws
}

public struct KeychainStore: KeychainStoring {
    public init() {}

    public func set(_ data: Data, for key: String) throws {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
        #else
        throw KeychainError.unexpectedStatus(-1)
        #endif
    }

    public func data(for key: String) throws -> Data? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        return item as? Data
        #else
        throw KeychainError.unexpectedStatus(-1)
        #endif
    }

    public func remove(_ key: String) throws {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
        #else
        throw KeychainError.unexpectedStatus(-1)
        #endif
    }
}

public final class MockKeychainStore: KeychainStoring, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let queue = DispatchQueue(label: "archery.mock-keychain")

    public init() {}

    public func set(_ data: Data, for key: String) throws {
        queue.sync { storage[key] = data }
    }

    public func data(for key: String) throws -> Data? {
        queue.sync { storage[key] }
    }

    public func remove(_ key: String) throws {
        _ = queue.sync { storage.removeValue(forKey: key) }
    }
}

public struct KeychainHelper {
    private let store: KeychainStoring
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(store: KeychainStoring = KeychainStore(), encoder: JSONEncoder = JSONEncoder(), decoder: JSONDecoder = JSONDecoder()) {
        self.store = store
        self.encoder = encoder
        self.decoder = decoder
    }

    public func set<T: Codable>(_ value: T, for key: String) throws {
        let data = try encoder.encode(value)
        try store.set(data, for: key)
    }

    public func value<T: Codable>(for key: String, as type: T.Type = T.self) throws -> T? {
        guard let data = try store.data(for: key) else { return nil }
        return try decoder.decode(T.self, from: data)
    }

    public func remove(_ key: String) throws {
        try store.remove(key)
    }
}
