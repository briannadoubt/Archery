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
        TokenStorage(
            store: {
                await KeychainHelper.shared.getData(
                    for: account,
                    service: service
                ).flatMap { data in
                    try? JSONDecoder().decode(StandardAuthToken.self, from: data)
                }
            },
            save: { token in
                let data = try JSONEncoder().encode(token)
                try await KeychainHelper.shared.setData(
                    data,
                    for: account,
                    service: service
                )
            },
            delete: {
                try? await KeychainHelper.shared.deleteData(
                    for: account,
                    service: service
                )
            }
        )
    }
    
    public static func inMemory() -> TokenStorage {
        actor Storage {
            var token: (any AuthToken)?
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

private extension TokenStorage.Storage {
    func setToken(_ token: (any AuthToken)?) {
        self.token = token
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