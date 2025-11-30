import Foundation

public struct TokenStorage: Sendable {
    private let store: @Sendable () async throws -> (any AuthToken)?
    private let save: @Sendable (any AuthToken) async throws -> Void
    private let delete: @Sendable () async -> Void
    
    public init(
        store: @escaping @Sendable () async throws -> (any AuthToken)?,
        save: @escaping @Sendable (any AuthToken) async throws -> Void,
        delete: @escaping @Sendable () async -> Void
    ) {
        self.store = store
        self.save = save
        self.delete = delete
    }
    
    public func retrieve() async -> (any AuthToken)? {
        try? await store()
    }
    
    public func store(_ token: any AuthToken) async throws {
        try await save(token)
    }
    
    public func clear() async {
        await delete()
    }
}

extension TokenStorage {
    public static func keychain(
        service: String = Bundle.main.bundleIdentifier ?? "com.app.archery",
        account: String = "auth-token"
    ) -> TokenStorage {
        let store = KeychainStore()
        let key = "\(service).\(account)"
        
        return TokenStorage(
            store: {
                guard let data = try? store.data(for: key) else { return nil }
                return try? JSONDecoder().decode(StandardAuthToken.self, from: data)
            },
            save: { token in
                let data = try JSONEncoder().encode(token)
                try store.set(data, for: key)
            },
            delete: {
                try? store.remove(key)
            }
        )
    }
    
    public static func inMemory() -> TokenStorage {
        actor Storage {
            var token: (any AuthToken)?
            
            func setToken(_ token: (any AuthToken)?) {
                self.token = token
            }
        }
        
        let storage = Storage()
        
        return TokenStorage(
            store: {
                await storage.token
            },
            save: { token in
                await storage.setToken(token)
            },
            delete: {
                await storage.setToken(nil)
            }
        )
    }
}

public extension TokenStorage {
    static func userDefaults(
        key: String = "archery.auth.token"
    ) -> TokenStorage {
        TokenStorage(
            store: {
                guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
                return try? JSONDecoder().decode(StandardAuthToken.self, from: data)
            },
            save: { token in
                let data = try JSONEncoder().encode(token)
                UserDefaults.standard.set(data, forKey: key)
            },
            delete: {
                UserDefaults.standard.removeObject(forKey: key)
            }
        )
    }
}