import Foundation
#if canImport(SwiftUI)
import SwiftUI

/// JSON-backed AppStorage wrapper for lightweight, Codable settings.
@available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, visionOS 1.0, *)
@propertyWrapper
public struct ArcheryAppStorage<Value: Codable>: DynamicProperty {
    @AppStorage private var storage: String
    private let defaultValue: Value
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        wrappedValue: Value,
        _ key: String,
        store: UserDefaults? = nil,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.defaultValue = wrappedValue
        self.encoder = encoder
        self.decoder = decoder
        self._storage = AppStorage(wrappedValue: "", key, store: store)

        if storage.isEmpty, let encoded = try? encoder.encode(wrappedValue) {
            storage = encoded.base64EncodedString()
        }
    }

    public var wrappedValue: Value {
        get {
            guard let data = Data(base64Encoded: storage), let decoded = try? decoder.decode(Value.self, from: data) else {
                return defaultValue
            }
            return decoded
        }
        mutating set {
            guard let data = try? encoder.encode(newValue) else { return }
            storage = data.base64EncodedString()
        }
    }
}

/// JSON-backed SceneStorage wrapper for per-scene ephemeral state.
@available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, visionOS 1.0, *)
@propertyWrapper
public struct ArcherySceneStorage<Value: Codable>: DynamicProperty {
    @SceneStorage private var storage: String
    private let defaultValue: Value
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        wrappedValue: Value,
        _ key: String,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.defaultValue = wrappedValue
        self.encoder = encoder
        self.decoder = decoder
        self._storage = SceneStorage(wrappedValue: "", key)
        if storage.isEmpty, let encoded = try? encoder.encode(wrappedValue) {
            storage = encoded.base64EncodedString()
        }
    }

    public var wrappedValue: Value {
        get {
            guard let data = Data(base64Encoded: storage), let decoded = try? decoder.decode(Value.self, from: data) else {
                return defaultValue
            }
            return decoded
        }
        mutating set {
            guard let data = try? encoder.encode(newValue) else { return }
            storage = data.base64EncodedString()
        }
    }
}
#endif
