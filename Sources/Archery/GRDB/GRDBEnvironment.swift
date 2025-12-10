import Foundation
import SwiftUI
import GRDB

// MARK: - Environment Keys

private struct GRDBContainerKey: EnvironmentKey {
    static let defaultValue: GRDBContainer? = nil
}

private struct GRDBWriterKey: EnvironmentKey {
    static let defaultValue: GRDBWriter? = nil
}

// MARK: - Environment Values

public extension EnvironmentValues {
    /// The GRDB container for database access
    var grdbContainer: GRDBContainer? {
        get { self[GRDBContainerKey.self] }
        set { self[GRDBContainerKey.self] = newValue }
    }

    /// The GRDB writer for write operations
    var grdbWriter: GRDBWriter? {
        get { self[GRDBWriterKey.self] }
        set { self[GRDBWriterKey.self] = newValue }
    }
}

// MARK: - View Modifier

public extension View {
    /// Inject a GRDB container into the view hierarchy
    ///
    /// Usage:
    /// ```swift
    /// ContentView()
    ///     .grdbContainer(myContainer)
    /// ```
    func grdbContainer(_ container: GRDBContainer) -> some View {
        self
            .environment(\.grdbContainer, container)
            .environment(\.grdbWriter, GRDBWriter(container: container))
    }

    /// Inject a GRDB container from the shared EnvContainer
    ///
    /// Usage:
    /// ```swift
    /// ContentView()
    ///     .grdbFromEnvContainer()
    /// ```
    func grdbFromEnvContainer() -> some View {
        modifier(GRDBEnvContainerModifier())
    }
}

// MARK: - EnvContainer Integration Modifier

private struct GRDBEnvContainerModifier: ViewModifier {
    @Environment(\.archeryContainer) private var envContainer

    func body(content: Content) -> some View {
        if let container = envContainer?.grdb {
            content
                .environment(\.grdbContainer, container)
                .environment(\.grdbWriter, GRDBWriter(container: container))
        } else {
            content
        }
    }
}

// MARK: - Preview Helpers

public extension GRDBContainer {
    /// Create a container seeded with preview data
    ///
    /// Usage:
    /// ```swift
    /// #Preview {
    ///     PlayerListView()
    ///         .grdbContainer(.preview { db in
    ///             try Player.createTable(db)
    ///             try Player(name: "Test", score: 100).insert(db)
    ///         })
    /// }
    /// ```
    @MainActor
    static func preview(
        seed: @escaping @Sendable (Database) throws -> Void = { _ in }
    ) throws -> GRDBContainer {
        let container = try GRDBContainer.inMemory()
        try container.writer.write { db in
            try seed(db)
        }
        return container
    }
}
