import Foundation

// MARK: - Navigation Serialization

public protocol NavigationSerializable {
    static func decodeNavigationIdentifier(_ value: String) -> Self?
    var navigationIdentifier: String { get }
}

public extension NavigationSerializable where Self: RawRepresentable, Self.RawValue == String {
    static func decodeNavigationIdentifier(_ value: String) -> Self? { Self(rawValue: value) }
    var navigationIdentifier: String { rawValue }
}

public extension NavigationSerializable where Self: RawRepresentable, Self.RawValue == Int {
    static func decodeNavigationIdentifier(_ value: String) -> Self? {
        guard let intValue = Int(value) else { return nil }
        return Self(rawValue: intValue)
    }
    var navigationIdentifier: String { String(rawValue) }
}

public extension NavigationSerializable where Self: Codable {
    static func decodeNavigationIdentifier(_ value: String) -> Self? {
        guard let data = Data(base64Encoded: value) ?? value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    var navigationIdentifier: String {
        guard let data = try? JSONEncoder().encode(self) else { return String(describing: self) }
        return data.base64EncodedString()
    }
}

// MARK: - Deep Link Router

public enum DeepLinkInput {
    case url(URL)
    case notification(userInfo: [AnyHashable: Any])
    case shortcut(id: String, userInfo: [AnyHashable: Any] = [:])
}

public struct DeepLinkMatch<Route: NavigationRoute> {
    public let route: Route
    public let source: DeepLinkInput
    public init(route: Route, source: DeepLinkInput) {
        self.route = route
        self.source = source
    }
}

public struct DeepLinkRouter<Route: NavigationRoute> {
    public typealias URLHandler = @Sendable (_ components: [String], _ params: [String: String], _ query: [String: String]) -> Route?
    public typealias NotificationHandler = @Sendable (_ userInfo: [AnyHashable: Any]) -> Route?
    public typealias ShortcutHandler = @Sendable (_ id: String, _ userInfo: [AnyHashable: Any]) -> Route?

    private var urlMatchers: [URLMatcher] = []
    private var notificationMatchers: [NotificationHandler] = []
    private var shortcutMatchers: [ShortcutHandler] = []

    public init() {}

    public mutating func registerURL(
        scheme: String? = nil,
        host: String? = nil,
        path: String,
        handler: @escaping URLHandler
    ) {
        urlMatchers.append(URLMatcher(scheme: scheme, host: host, path: path, handler: handler))
    }

    public mutating func registerNotification(_ handler: @escaping NotificationHandler) {
        notificationMatchers.append(handler)
    }

    public mutating func registerShortcut(_ handler: @escaping ShortcutHandler) {
        shortcutMatchers.append(handler)
    }

    public func route(from input: DeepLinkInput) -> DeepLinkMatch<Route>? {
        switch input {
        case .url(let url):
            if let route = match(url: url) { return DeepLinkMatch(route: route, source: input) }
        case .notification(let userInfo):
            if let route = match(notification: userInfo) { return DeepLinkMatch(route: route, source: input) }
            if let urlString = userInfo["url"] as? String, let url = URL(string: urlString), let route = match(url: url) {
                return DeepLinkMatch(route: route, source: input)
            }
        case .shortcut(let id, let userInfo):
            if let route = match(shortcut: id, userInfo: userInfo) { return DeepLinkMatch(route: route, source: input) }
            if let urlString = userInfo["url"] as? String, let url = URL(string: urlString), let route = match(url: url) {
                return DeepLinkMatch(route: route, source: input)
            }
        }
        return nil
    }

    // MARK: - Private

    private func match(notification: [AnyHashable: Any]) -> Route? {
        for handler in notificationMatchers {
            if let route = handler(notification) { return route }
        }
        return nil
    }

    private func match(shortcut id: String, userInfo: [AnyHashable: Any]) -> Route? {
        for handler in shortcutMatchers {
            if let route = handler(id, userInfo) { return route }
        }
        return nil
    }

    private func match(url: URL) -> Route? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let pathParts = components.path.split(separator: "/").map(String.init)
        let queryItems = components.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

        for matcher in urlMatchers {
            if let params = matcher.match(url: url, components: pathParts) {
                return matcher.handler(pathParts, params, query)
            }
        }
        return nil
    }

    private struct URLMatcher {
        let scheme: String?
        let host: String?
        let pathParts: [String]
        let handler: URLHandler

        init(scheme: String?, host: String?, path: String, handler: @escaping URLHandler) {
            self.scheme = scheme
            self.host = host
            self.pathParts = path.split(separator: "/").map(String.init)
            self.handler = handler
        }

        func match(url: URL, components: [String]) -> [String: String]? {
            if let scheme, url.scheme?.lowercased() != scheme.lowercased() { return nil }
            if let host, url.host?.lowercased() != host.lowercased() { return nil }
            guard components.count == pathParts.count else { return nil }

            var params: [String: String] = [:]
            for (pattern, value) in zip(pathParts, components) {
                if pattern.hasPrefix(":") {
                    let key = String(pattern.dropFirst())
                    params[key] = value
                } else if pattern != value {
                    return nil
                }
            }
            return params
        }
    }
}

// MARK: - Route Guards

public enum RouteGuardResult: Equatable {
    case allowed
    case blocked(AppError)
}

public struct RouteGuard<Route: NavigationRoute> {
    private let checker: @Sendable (Route) async -> RouteGuardResult
    public init(check: @escaping @Sendable (Route) async -> RouteGuardResult) { self.checker = check }
    public func evaluate(_ route: Route) async -> RouteGuardResult { await checker(route) }
}

public extension DeepLinkRouter {
    func resolve(
        _ input: DeepLinkInput,
        gate: RouteGuard<Route>? = nil
    ) async -> Result<DeepLinkMatch<Route>, AppError> {
        guard let match = route(from: input) else {
            return .failure(AppError(title: "Route Not Found", message: "No handler matched the deep link."))
        }
        if let gate {
            switch await gate.evaluate(match.route) {
            case .allowed:
                return .success(match)
            case .blocked(let error):
                return .failure(error)
            }
        }
        return .success(match)
    }
}

// MARK: - Navigation Persistence

public struct NavigationSnapshot: Codable, Equatable {
    public struct Stack: Codable, Equatable {
        public let tab: String
        public let path: [String]
        public init(tab: String, path: [String]) {
            self.tab = tab
            self.path = path
        }
    }

    public let selectedTab: String
    public let stacks: [Stack]

    public init(selectedTab: String, stacks: [Stack]) {
        self.selectedTab = selectedTab
        self.stacks = stacks
    }
}

public protocol NavigationStateStore {
    func load(key: String) -> NavigationSnapshot?
    func save(_ snapshot: NavigationSnapshot, key: String)
    func clear(key: String)
}

public struct NavigationUserDefaultsStore: NavigationStateStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load(key: String) -> NavigationSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(NavigationSnapshot.self, from: data)
    }

    public func save(_ snapshot: NavigationSnapshot, key: String) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    public func clear(key: String) { defaults.removeObject(forKey: key) }
}

public final class NavigationMemoryStore: NavigationStateStore {
    private var storage: [String: NavigationSnapshot] = [:]
    public init() {}
    public func load(key: String) -> NavigationSnapshot? { storage[key] }
    public func save(_ snapshot: NavigationSnapshot, key: String) { storage[key] = snapshot }
    public func clear(key: String) { storage[key] = nil }
}

public struct NavigationPersistence {
    public enum Mode { case disabled, enabled }
    public let mode: Mode
    public let key: String
    public let store: NavigationStateStore

    public init(mode: Mode = .enabled, key: String, store: NavigationStateStore = NavigationUserDefaultsStore()) {
        self.mode = mode
        self.key = key
        self.store = store
    }

    public static func enabled(key: String) -> NavigationPersistence {
        NavigationPersistence(mode: .enabled, key: key)
    }

    public static func disabled() -> NavigationPersistence {
        NavigationPersistence(mode: .disabled, key: "")
    }
}

public struct NavigationRestorer<Tab: Hashable> {
    private let persistence: NavigationPersistence

    public init(persistence: NavigationPersistence) {
        self.persistence = persistence
    }

    public typealias Decoder = @Sendable (_ tab: Tab, _ identifier: String) -> AnyHashable?
    public typealias Encoder = @Sendable (_ tab: Tab, _ element: AnyHashable) -> String?
    public typealias TabDecoder = @Sendable (_ identifier: String) -> Tab?
    public typealias TabEncoder = @Sendable (_ tab: Tab) -> String?

    public func restore(tabDecoder: TabDecoder, decoder: Decoder) -> (selection: Tab?, paths: [Tab: [AnyHashable]]) {
        guard persistence.mode == .enabled, let snapshot = persistence.store.load(key: persistence.key) else { return (nil, [:]) }
        let selection = tabDecoder(snapshot.selectedTab)
        var paths: [Tab: [AnyHashable]] = [:]
        for stack in snapshot.stacks {
            guard let tab = tabDecoder(stack.tab) else { continue }
            let decoded = stack.path.compactMap { decoder(tab, $0) }
            paths[tab] = decoded
        }
        return (selection, paths)
    }

    public func persist(selection: Tab, paths: [Tab: [AnyHashable]], tabEncoder: TabEncoder, encoder: Encoder) {
        guard persistence.mode == .enabled else { return }
        guard let selectionId = tabEncoder(selection) else { return }
        let stacks: [NavigationSnapshot.Stack] = paths.compactMap { tab, routes in
            let encoded = routes.compactMap { encoder(tab, $0) }
            guard let tabId = tabEncoder(tab) else { return nil }
            return NavigationSnapshot.Stack(tab: tabId, path: encoded)
        }
        let snapshot = NavigationSnapshot(selectedTab: selectionId, stacks: stacks)
        persistence.store.save(snapshot, key: persistence.key)
    }
}
