import Foundation
import SwiftUI
import GRDB

// MARK: - Environment Keys

private struct PersistenceContainerKey: EnvironmentKey {
    static let defaultValue: PersistenceContainer? = nil
}

private struct PersistenceWriterKey: EnvironmentKey {
    static let defaultValue: PersistenceWriter? = nil
}

// MARK: - Environment Values

public extension EnvironmentValues {
    /// The GRDB container for database access
    var databaseContainer: PersistenceContainer? {
        get { self[PersistenceContainerKey.self] }
        set { self[PersistenceContainerKey.self] = newValue }
    }

    /// The GRDB writer for write operations
    var databaseWriter: PersistenceWriter? {
        get { self[PersistenceWriterKey.self] }
        set { self[PersistenceWriterKey.self] = newValue }
    }
}

// MARK: - View Modifier

public extension View {
    /// Inject a GRDB container into the view hierarchy
    ///
    /// Usage:
    /// ```swift
    /// ContentView()
    ///     .databaseContainer(myContainer)
    /// ```
    func databaseContainer(_ container: PersistenceContainer) -> some View {
        self
            .environment(\.databaseContainer, container)
            .environment(\.databaseWriter, PersistenceWriter(container: container))
    }

    /// Inject a database container from the shared EnvContainer
    ///
    /// Usage:
    /// ```swift
    /// ContentView()
    ///     .databaseFromEnvContainer()
    /// ```
    func databaseFromEnvContainer() -> some View {
        modifier(DatabaseEnvContainerModifier())
    }
}

// MARK: - EnvContainer Integration Modifier

private struct DatabaseEnvContainerModifier: ViewModifier {
    @Environment(\.archeryContainer) private var envContainer

    func body(content: Content) -> some View {
        if let container = envContainer?.grdb {
            content
                .environment(\.databaseContainer, container)
                .environment(\.databaseWriter, PersistenceWriter(container: container))
        } else {
            content
        }
    }
}

// MARK: - Preview Helpers

public extension PersistenceContainer {
    /// Create a container seeded with preview data
    ///
    /// Usage:
    /// ```swift
    /// #Preview {
    ///     PlayerListView()
    ///         .databaseContainer(.preview { db in
    ///             try Player.createTable(db)
    ///             try Player(name: "Test", score: 100).insert(db)
    ///         })
    /// }
    /// ```
    @MainActor
    static func preview(
        seed: @escaping @Sendable (Database) throws -> Void = { _ in }
    ) throws -> PersistenceContainer {
        let container = try PersistenceContainer.inMemory()
        try container.writer.write { db in
            try seed(db)
        }
        return container
    }
}
