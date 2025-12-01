import Foundation
import CryptoKit
import Security

// MARK: - Secrets Manager

@MainActor
public final class SecretsManager {
    public static let shared = SecretsManager()
    
    private let keychain: KeychainStore
    private let secureLogger: SecureLogger
    private var encryptionKey: SymmetricKey?
    private var cachedSecrets: [String: Secret] = [:]
    private let cacheDuration: TimeInterval = 300 // 5 minutes
    
    private init() {
        self.keychain = KeychainStore()
        self.secureLogger = SecureLogger.shared
        self.encryptionKey = loadOrCreateEncryptionKey()
    }
    
    // MARK: - Encryption Key Management
    
    private func loadOrCreateEncryptionKey() -> SymmetricKey {
        let keyIdentifier = "com.archery.secrets.encryption.key"
        
        if let keyData = try? keychain.retrieve(keyIdentifier),
           !keyData.isEmpty {
            return SymmetricKey(data: keyData)
        }
        
        // Generate new key
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        
        do {
            try keychain.store(keyData, for: keyIdentifier)
        } catch {
            secureLogger.error("Failed to store encryption key: \(error)")
        }
        
        return key
    }
    
    // MARK: - Secret Storage
    
    public func store(_ secret: Secret) throws {
        // Validate secret
        guard try secret.validate() else {
            throw SecretsError.validationFailed("Secret validation failed")
        }
        
        // Encrypt value if needed
        let finalValue: String
        if secret.encrypted, let key = encryptionKey {
            finalValue = try encrypt(secret.value, with: key)
        } else {
            finalValue = secret.value
        }
        
        // Store in keychain
        let keychainKey = secretKey(for: secret.key, environment: secret.environment)
        let data = finalValue.data(using: .utf8) ?? Data()
        try keychain.store(data, for: keychainKey)
        
        // Update cache
        var cachedSecret = secret
        cachedSecret.lastAccessed = Date()
        cachedSecrets[keychainKey] = cachedSecret
        
        // Log (without value)
        secureLogger.info("Secret stored: \(secret.key) [REDACTED]")
    }
    
    public func retrieve(_ key: String, environment: ConfigurationEnvironment? = nil) throws -> Secret? {
        let env = environment ?? ConfigurationEnvironment.current
        let keychainKey = secretKey(for: key, environment: env)
        
        // Check cache
        if let cached = cachedSecrets[keychainKey],
           Date().timeIntervalSince(cached.lastAccessed) < cacheDuration {
            return cached
        }
        
        // Retrieve from keychain
        guard let data = try keychain.retrieve(keychainKey),
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        // Create secret
        var secret = Secret(
            key: key,
            value: value,
            environment: env,
            encrypted: false // Already decrypted
        )
        
        // Cache it
        secret.lastAccessed = Date()
        cachedSecrets[keychainKey] = secret
        
        return secret
    }
    
    public func delete(_ key: String, environment: ConfigurationEnvironment? = nil) throws {
        let env = environment ?? ConfigurationEnvironment.current
        let keychainKey = secretKey(for: key, environment: env)
        
        try keychain.delete(keychainKey)
        cachedSecrets.removeValue(forKey: keychainKey)
        
        secureLogger.info("Secret deleted: \(key)")
    }
    
    public func exists(_ key: String, environment: ConfigurationEnvironment? = nil) -> Bool {
        let env = environment ?? ConfigurationEnvironment.current
        let keychainKey = secretKey(for: key, environment: env)
        
        return (try? keychain.retrieve(keychainKey)) != nil
    }
    
    // MARK: - Batch Operations
    
    public func storeMultiple(_ secrets: [Secret]) throws {
        for secret in secrets {
            try store(secret)
        }
    }
    
    public func retrieveAll(for environment: ConfigurationEnvironment? = nil) throws -> [Secret] {
        let env = environment ?? ConfigurationEnvironment.current
        var secrets: [Secret] = []
        
        // This would need keychain enumeration support
        // For now, return cached secrets for the environment
        for (key, secret) in cachedSecrets {
            if key.contains(".\(env.rawValue).") {
                secrets.append(secret)
            }
        }
        
        return secrets
    }
    
    public func deleteAll(for environment: ConfigurationEnvironment? = nil) throws {
        let env = environment ?? ConfigurationEnvironment.current
        
        // Delete from cache
        let keysToDelete = cachedSecrets.keys.filter { $0.contains(".\(env.rawValue).") }
        for key in keysToDelete {
            cachedSecrets.removeValue(forKey: key)
            try keychain.delete(key)
        }
    }
    
    // MARK: - Validation
    
    public func validateAll() throws -> [String: Bool] {
        var results: [String: Bool] = [:]
        
        for (_, secret) in cachedSecrets {
            results[secret.key] = try secret.validate()
        }
        
        return results
    }
    
    // MARK: - Rotation
    
    public func rotate(_ key: String, newValue: String, environment: ConfigurationEnvironment? = nil) throws {
        guard var secret = try retrieve(key, environment: environment) else {
            throw SecretsError.secretNotFound(key)
        }
        
        // Store old value for rollback
        let oldValue = secret.value
        secret.previousValue = oldValue
        secret.rotatedAt = Date()
        secret.value = newValue
        
        try store(secret)
        
        secureLogger.info("Secret rotated: \(key)")
    }
    
    // MARK: - Import/Export
    
    public func export(encrypted: Bool = true) throws -> Data {
        var exportData: [String: Any] = [:]
        
        for (key, secret) in cachedSecrets {
            var secretDict: [String: Any] = [
                "key": secret.key,
                "environment": secret.environment.rawValue,
                "encrypted": encrypted,
                "createdAt": secret.createdAt.timeIntervalSince1970
            ]
            
            if encrypted, let encKey = encryptionKey {
                secretDict["value"] = try encrypt(secret.value, with: encKey)
            } else {
                // Only export unencrypted in development
                guard ConfigurationEnvironment.current.isDevelopment else {
                    throw SecretsError.exportNotAllowed
                }
                secretDict["value"] = secret.value
            }
            
            exportData[key] = secretDict
        }
        
        return try JSONSerialization.data(withJSONObject: exportData)
    }
    
    public func importSecrets(from data: Data) throws {
        guard let importData = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            throw SecretsError.invalidFormat
        }
        
        for (_, secretDict) in importData {
            guard let key = secretDict["key"] as? String,
                  let value = secretDict["value"] as? String,
                  let envString = secretDict["environment"] as? String,
                  let environment = Environment(rawValue: envString) else {
                continue
            }
            
            let encrypted = secretDict["encrypted"] as? Bool ?? false
            
            let secret = Secret(
                key: key,
                value: value,
                environment: environment,
                encrypted: encrypted
            )
            
            try store(secret)
        }
    }
    
    // MARK: - Helpers
    
    private func secretKey(for key: String, environment: ConfigurationEnvironment) -> String {
        "com.archery.secret.\(environment.rawValue).\(key)"
    }
    
    private func encrypt(_ value: String, with key: SymmetricKey) throws -> String {
        guard let data = value.data(using: .utf8) else {
            throw SecretsError.encodingFailed
        }
        
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined?.base64EncodedString() ?? ""
    }
    
    private func decrypt(_ value: String, with key: SymmetricKey) throws -> String {
        guard let data = Data(base64Encoded: value) else {
            throw SecretsError.decodingFailed
        }
        
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let decrypted = try AES.GCM.open(sealedBox, using: key)
        
        guard let string = String(data: decrypted, encoding: .utf8) else {
            throw SecretsError.decodingFailed
        }
        
        return string
    }
}

// MARK: - Secret Model

public struct Secret: Codable, Sendable {
    public let key: String
    public var value: String
    public let environment: ConfigurationEnvironment
    public var encrypted: Bool
    public var tags: [String]
    public let createdAt: Date
    public var lastAccessed: Date
    public var rotatedAt: Date?
    public var previousValue: String?
    public var expiresAt: Date?
    
    public init(
        key: String,
        value: String,
        environment: ConfigurationEnvironment = .current,
        encrypted: Bool = true,
        tags: [String] = [],
        expiresAt: Date? = nil
    ) {
        self.key = key
        self.value = value
        self.environment = environment
        self.encrypted = encrypted
        self.tags = tags
        self.createdAt = Date()
        self.lastAccessed = Date()
        self.rotatedAt = nil
        self.previousValue = nil
        self.expiresAt = expiresAt
    }
    
    public func validate() throws -> Bool {
        // Check if expired
        if let expiresAt = expiresAt, Date() > expiresAt {
            throw SecretsError.secretExpired(key)
        }
        
        // Check key format
        guard !key.isEmpty, key.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw SecretsError.invalidKey(key)
        }
        
        // Check value
        guard !value.isEmpty else {
            throw SecretsError.emptyValue(key)
        }
        
        return true
    }
}

// MARK: - Secrets Provider Protocol

public protocol SecretsProvider {
    func getSecret(_ key: String) async throws -> String?
    func setSecret(_ key: String, value: String) async throws
    func deleteSecret(_ key: String) async throws
    func listSecrets() async throws -> [String]
}

// MARK: - Environment Variable Provider

public struct EnvironmentSecretsProvider: SecretsProvider {
    private let prefix: String
    
    public init(prefix: String = "SECRET") {
        self.prefix = prefix
    }
    
    public func getSecret(_ key: String) async throws -> String? {
        let envKey = "\(prefix)_\(key.uppercased().replacingOccurrences(of: ".", with: "_"))"
        return ProcessInfo.processInfo.environment[envKey]
    }
    
    public func setSecret(_ key: String, value: String) async throws {
        // Environment variables can't be set at runtime
        throw SecretsError.notSupported("Environment variables are read-only")
    }
    
    public func deleteSecret(_ key: String) async throws {
        throw SecretsError.notSupported("Environment variables are read-only")
    }
    
    public func listSecrets() async throws -> [String] {
        ProcessInfo.processInfo.environment.keys
            .filter { $0.hasPrefix("\(prefix)_") }
            .map { String($0.dropFirst(prefix.count + 1)) }
    }
}

// MARK: - HashiCorp Vault Provider

public struct VaultSecretsProvider: SecretsProvider {
    private let vaultURL: URL
    private let token: String
    private let mountPath: String
    
    public init(url: URL, token: String, mountPath: String = "secret") {
        self.vaultURL = url
        self.token = token
        self.mountPath = mountPath
    }
    
    public func getSecret(_ key: String) async throws -> String? {
        let url = vaultURL
            .appendingPathComponent("v1")
            .appendingPathComponent(mountPath)
            .appendingPathComponent("data")
            .appendingPathComponent(key)
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(token, forHTTPHeaderField: "X-Vault-Token")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let secretData = dataDict["data"] as? [String: Any],
              let value = secretData["value"] as? String else {
            return nil
        }
        
        return value
    }
    
    public func setSecret(_ key: String, value: String) async throws {
        let url = vaultURL
            .appendingPathComponent("v1")
            .appendingPathComponent(mountPath)
            .appendingPathComponent("data")
            .appendingPathComponent(key)
        
        let payload: [String: Any] = [
            "data": ["value": value]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(token, forHTTPHeaderField: "X-Vault-Token")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SecretsError.providerError("Failed to set secret in Vault")
        }
    }
    
    public func deleteSecret(_ key: String) async throws {
        let url = vaultURL
            .appendingPathComponent("v1")
            .appendingPathComponent(mountPath)
            .appendingPathComponent("metadata")
            .appendingPathComponent(key)
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue(token, forHTTPHeaderField: "X-Vault-Token")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 204 else {
            throw SecretsError.providerError("Failed to delete secret from Vault")
        }
    }
    
    public func listSecrets() async throws -> [String] {
        let url = vaultURL
            .appendingPathComponent("v1")
            .appendingPathComponent(mountPath)
            .appendingPathComponent("metadata")
        
        var request = URLRequest(url: url)
        request.httpMethod = "LIST"
        request.addValue(token, forHTTPHeaderField: "X-Vault-Token")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let keys = dataDict["keys"] as? [String] else {
            return []
        }
        
        return keys
    }
}

// MARK: - Errors

public enum SecretsError: LocalizedError {
    case secretNotFound(String)
    case validationFailed(String)
    case invalidKey(String)
    case emptyValue(String)
    case secretExpired(String)
    case encodingFailed
    case decodingFailed
    case invalidFormat
    case exportNotAllowed
    case notSupported(String)
    case providerError(String)
    
    public var errorDescription: String? {
        switch self {
        case .secretNotFound(let key):
            return "Secret not found: \(key)"
        case .validationFailed(let message):
            return "Secret validation failed: \(message)"
        case .invalidKey(let key):
            return "Invalid secret key: \(key)"
        case .emptyValue(let key):
            return "Empty value for secret: \(key)"
        case .secretExpired(let key):
            return "Secret expired: \(key)"
        case .encodingFailed:
            return "Failed to encode secret"
        case .decodingFailed:
            return "Failed to decode secret"
        case .invalidFormat:
            return "Invalid secret format"
        case .exportNotAllowed:
            return "Secret export not allowed in production"
        case .notSupported(let operation):
            return "Operation not supported: \(operation)"
        case .providerError(let message):
            return "Provider error: \(message)"
        }
    }
}