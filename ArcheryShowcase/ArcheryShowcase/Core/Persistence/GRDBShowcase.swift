import Foundation
import SwiftUI
import Archery
import GRDB

// MARK: - @Persistable Demo
//
// The @Persistable macro generates GRDB conformances for your Codable types:
// - FetchableRecord: For reading from database
// - PersistableRecord: For writing to database
// - TableRecord: Table name and column definitions
// - Columns enum: Type-safe column references for queries

// Define a model with @Persistable to generate Columns and databaseTableName
// User must add FetchableRecord, PersistableRecord conformances manually
@Persistable(table: "players")
struct Player: Codable, Identifiable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?  // Auto-incremented by SQLite
    var name: String
    var team: String
    var score: Int
    var joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, team, score, joinedAt = "joined_at"
    }

    // Required for MutablePersistableRecord to update id after insert
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - @GRDBRepository Demo
//
// The @GRDBRepository macro generates:
// - Protocol with CRUD methods
// - Live implementation using GRDB
// - Mock implementation for testing
// - DI helper methods

@GRDBRepository(record: Player.self)
class PlayerStore {
    // Custom queries can be added here
    func topScorers(limit: Int) async throws -> [Player] {
        // This will be delegated to the Live implementation
        fatalError("Implemented by generated Live class")
    }

    func playersByTeam(_ team: String) async throws -> [Player] {
        fatalError("Implemented by generated Live class")
    }
}

// MARK: - Database Setup

/// Migrations for the Player database
private let playerMigrations = GRDBMigrationRunner {
    GRDBMigration(id: "v1_create_players") { db in
        try db.create(table: "players") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("team", .text).notNull()
            t.column("score", .integer).notNull().defaults(to: 0)
            t.column("joined_at", .datetime).notNull()
        }

        // Add index for team lookups
        try db.create(index: "players_team_idx", on: "players", columns: ["team"])
    }
}

/// Demo database container
@MainActor
class GRDBDemoDatabase: ObservableObject {
    static let shared = GRDBDemoDatabase()

    private(set) var container: GRDBContainer?
    @Published var isReady = false
    @Published var error: Error?

    func setup() async {
        do {
            // Create in-memory database for demo
            container = try GRDBContainer.inMemory()

            // Run migrations
            try playerMigrations.run(on: container!)

            // Seed with some demo data
            try await seedDemoData()

            isReady = true
        } catch {
            self.error = error
        }
    }

    private func seedDemoData() async throws {
        guard let container else { return }
        let writer = GRDBWriter(container: container)

        // Add some initial players if empty
        let count = try await container.read { db in
            try Player.fetchCount(db)
        }

        guard count == 0 else { return }

        let demoPlayers = [
            Player(name: "Alice", team: "Blue", score: 95, joinedAt: Date()),
            Player(name: "Bob", team: "Red", score: 87, joinedAt: Date()),
            Player(name: "Charlie", team: "Blue", score: 72, joinedAt: Date()),
            Player(name: "Diana", team: "Green", score: 100, joinedAt: Date()),
        ]

        for player in demoPlayers {
            _ = try await writer.insert(player)
        }
    }

    var store: PlayerStoreLive? {
        guard let container else { return nil }
        return PlayerStoreLive(db: container.writer)
    }
}

// MARK: - Showcase View

struct GRDBShowcaseView: View {
    @StateObject private var database = GRDBDemoDatabase.shared
    @State private var players: [Player] = []
    @State private var newPlayerName = ""
    @State private var newPlayerTeam = "Blue"
    @State private var isLoading = false
    @State private var showError: Error?
    @State private var showReactiveDemo = false

    private let teams = ["Blue", "Red", "Green", "Yellow"]

    var body: some View {
        List {
            Section {
                Text("The @Persistable and @GRDBRepository macros provide type-safe SQLite persistence using GRDB. The @GRDBQuery property wrapper enables reactive SwiftUI queries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("@Persistable Macro") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Generates GRDB conformances:")
                        .font(.caption.weight(.medium))

                    GeneratedCodeRow(
                        code: "FetchableRecord",
                        description: "Read records from database"
                    )
                    GeneratedCodeRow(
                        code: "PersistableRecord",
                        description: "Write records to database"
                    )
                    GeneratedCodeRow(
                        code: "TableRecord",
                        description: "Table name definition"
                    )
                    GeneratedCodeRow(
                        code: "Columns enum",
                        description: "Type-safe column references"
                    )
                }
            }

            Section("@GRDBRepository Macro") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Generates repository pattern:")
                        .font(.caption.weight(.medium))

                    GeneratedCodeRow(
                        code: "Protocol",
                        description: "PlayerStoreProtocol with CRUD methods"
                    )
                    GeneratedCodeRow(
                        code: "Live",
                        description: "PlayerStoreLive with real DB"
                    )
                    GeneratedCodeRow(
                        code: "Mock",
                        description: "MockPlayerStore for testing"
                    )
                    GeneratedCodeRow(
                        code: "DI Helpers",
                        description: ".live(db:) and .mock()"
                    )
                }
            }

            Section("@GRDBQuery - Reactive SwiftUI") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Property wrappers for reactive queries:")
                        .font(.caption.weight(.medium))

                    GeneratedCodeRow(
                        code: "@GRDBQuery",
                        description: "Observe array of records"
                    )
                    GeneratedCodeRow(
                        code: "@GRDBQueryOne",
                        description: "Observe single record"
                    )
                    GeneratedCodeRow(
                        code: "@GRDBQueryCount",
                        description: "Observe record count"
                    )
                    GeneratedCodeRow(
                        code: "GRDBWriter",
                        description: "Write operations via environment"
                    )
                }

                if database.isReady, let container = database.container {
                    NavigationLink {
                        ReactiveQueryDemoView()
                            .grdbContainer(container)
                    } label: {
                        Label("Try Reactive Demo", systemImage: "bolt.fill")
                    }
                }
            }

            Section("CRUD Methods") {
                ForEach([
                    ("fetchAll()", "Get all records"),
                    ("fetch(id:)", "Get by ID"),
                    ("insert(_:)", "Create new record"),
                    ("update(_:)", "Update existing"),
                    ("upsert(_:)", "Insert or update"),
                    ("delete(id:)", "Remove by ID"),
                    ("deleteAll()", "Clear table"),
                    ("count()", "Get total count")
                ], id: \.0) { method, desc in
                    LabeledContent {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(method)
                            .font(.caption.monospaced())
                    }
                }
            }

            if database.isReady {
                Section("Live Demo - Add Player") {
                    TextField("Player Name", text: $newPlayerName)

                    Picker("Team", selection: $newPlayerTeam) {
                        ForEach(teams, id: \.self) { team in
                            Text(team).tag(team)
                        }
                    }

                    Button {
                        Task { await addPlayer() }
                    } label: {
                        Label("Add Player", systemImage: "plus.circle.fill")
                    }
                    .disabled(newPlayerName.isEmpty || isLoading)
                }

                Section("Players (\(players.count))") {
                    if players.isEmpty {
                        Text("No players yet. Add some above!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(players) { player in
                            PlayerRow(player: player)
                        }
                        .onDelete { indexSet in
                            Task { await deletePlayers(at: indexSet) }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task { await deleteAllPlayers() }
                    } label: {
                        Label("Delete All Players", systemImage: "trash")
                    }
                    .disabled(players.isEmpty || isLoading)
                }
            } else if let error = database.error {
                Section("Error") {
                    Text(error.localizedDescription)
                        .foregroundStyle(.red)
                }
            } else {
                Section("Loading") {
                    ProgressView("Setting up database...")
                }
            }

            Section("Usage Example") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("// Model definition")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("struct Player: Codable, Identifiable {")
                        .font(.caption.monospaced())
                    Text("    var id: Int64?")
                        .font(.caption.monospaced())
                    Text("    var name: String")
                        .font(.caption.monospaced())
                    Text("    var score: Int")
                        .font(.caption.monospaced())
                    Text("}")
                        .font(.caption.monospaced())
                    Text("")
                    Text("// Add GRDB conformances")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("@Persistable(table: \"players\")")
                        .font(.caption.monospaced())
                        .foregroundStyle(.blue)
                    Text("extension Player {}")
                        .font(.caption.monospaced())
                    Text("")
                    Text("// Generate repository")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("@GRDBRepository(record: Player.self)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.blue)
                    Text("class PlayerStore {}")
                        .font(.caption.monospaced())
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .navigationTitle("GRDB Persistence")
        .task {
            await database.setup()
            await loadPlayers()
        }
        .alert("Error", isPresented: .init(
            get: { showError != nil },
            set: { if !$0 { showError = nil } }
        )) {
            Button("OK") { showError = nil }
        } message: {
            if let error = showError {
                Text(error.localizedDescription)
            }
        }
    }

    private func loadPlayers() async {
        guard let store = database.store else { return }
        do {
            players = try await store.fetchAll()
        } catch {
            showError = error
        }
    }

    private func addPlayer() async {
        guard let store = database.store else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let player = Player(
                name: newPlayerName,
                team: newPlayerTeam,
                score: Int.random(in: 0...100),
                joinedAt: Date()
            )
            _ = try await store.insert(player)
            newPlayerName = ""
            await loadPlayers()
        } catch {
            showError = error
        }
    }

    private func deletePlayers(at offsets: IndexSet) async {
        guard let store = database.store else { return }

        for index in offsets {
            let player = players[index]
            if let id = player.id {
                do {
                    _ = try await store.delete(id: id)
                } catch {
                    showError = error
                }
            }
        }
        await loadPlayers()
    }

    private func deleteAllPlayers() async {
        guard let store = database.store else { return }
        do {
            _ = try await store.deleteAll()
            await loadPlayers()
        } catch {
            showError = error
        }
    }
}

// MARK: - Supporting Views

private struct GeneratedCodeRow: View {
    let code: String
    let description: String

    var body: some View {
        HStack {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.blue)
                .font(.caption)
            Text(code)
                .font(.caption.monospaced())
            Spacer()
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PlayerRow: View {
    let player: Player

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.subheadline.weight(.medium))
                Text("Team: \(player.team)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(player.score) pts")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.blue)
        }
    }
}

// MARK: - Reactive Query Demo View

/// Demonstrates @GRDBQuery property wrapper for reactive database queries
struct ReactiveQueryDemoView: View {
    // Reactive query - automatically updates when database changes!
    // Uses clean Archery syntax: Player.all() instead of GRDBQueryBuilder<Player>.all()
    @GRDBQuery(Player.all().order(by: Player.Columns.score, ascending: false))
    var players: [Player]

    // Reactive count - uses type-safe query builder
    @GRDBQueryCount(Player.count())
    var playerCount: Int

    // Environment writer for mutations
    @Environment(\.grdbWriter) private var writer

    @State private var newPlayerName = ""
    @State private var showError: Error?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This view uses @GRDBQuery for automatic UI updates when the database changes. No manual refresh needed!")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Image(systemName: "bolt.circle.fill")
                            .foregroundStyle(.yellow)
                        Text("Real-time updates")
                            .font(.caption.weight(.medium))
                    }
                }
            }

            Section("Add Player") {
                HStack {
                    TextField("Name", text: $newPlayerName)
                    Button("Add") {
                        Task { await addRandomPlayer() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newPlayerName.isEmpty)
                }
            }

            Section("Players (Count: \(playerCount))") {
                if $players.isLoading {
                    ProgressView("Loading...")
                } else if players.isEmpty {
                    Text("No players yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(players) { player in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(player.name)
                                    .font(.headline)
                                Text(player.team)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(player.score) pts")
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(.blue)
                        }
                    }
                    .onDelete { indexSet in
                        Task { await deletePlayers(at: indexSet) }
                    }
                }
            }

            Section {
                Button("Add 5 Random Players") {
                    Task { await addBulkPlayers() }
                }

                Button("Update All Scores +10") {
                    Task { await updateAllScores() }
                }

                Button(role: .destructive) {
                    Task { await deleteAll() }
                } label: {
                    Text("Delete All")
                }
                .disabled(players.isEmpty)
            }

            Section("Archery GRDB Integration") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("// 1. Define model with @Persistable")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("@Persistable(table: \"players\")")
                        .font(.caption.monospaced())
                        .foregroundStyle(.blue)
                    Text("struct Player: Codable, Sendable,")
                        .font(.caption.monospaced())
                    Text("  FetchableRecord, MutablePersistableRecord {")
                        .font(.caption.monospaced())
                    Text("    var id: Int64?")
                        .font(.caption.monospaced())
                    Text("    var name: String")
                        .font(.caption.monospaced())
                    Text("    var score: Int")
                        .font(.caption.monospaced())
                    Text("}")
                        .font(.caption.monospaced())
                    Text("")
                    Text("// 2. Reactive queries with @GRDBQuery")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("@GRDBQuery(Player.all())")
                        .font(.caption.monospaced())
                        .foregroundStyle(.blue)
                    Text("var players: [Player]")
                        .font(.caption.monospaced())
                    Text("")
                    Text("// Filtered & sorted")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("@GRDBQuery(Player.all()")
                        .font(.caption.monospaced())
                        .foregroundStyle(.blue)
                    Text("  .filter(Player.Columns.score > 50)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.blue)
                    Text("  .order(by: Player.Columns.name))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.blue)
                    Text("var topPlayers: [Player]")
                        .font(.caption.monospaced())
                    Text("")
                    Text("// 3. Write via environment")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("@Environment(\\.grdbWriter) var writer")
                        .font(.caption.monospaced())
                        .foregroundStyle(.blue)
                    Text("try await writer?.insert(player)")
                        .font(.caption.monospaced())
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .navigationTitle("Reactive Queries")
        .alert("Error", isPresented: .init(
            get: { showError != nil },
            set: { if !$0 { showError = nil } }
        )) {
            Button("OK") { showError = nil }
        } message: {
            if let error = showError {
                Text(error.localizedDescription)
            }
        }
    }

    private func addRandomPlayer() async {
        guard let writer else { return }
        do {
            let teams = ["Blue", "Red", "Green", "Yellow"]
            let player = Player(
                name: newPlayerName,
                team: teams.randomElement()!,
                score: Int.random(in: 50...100),
                joinedAt: Date()
            )
            _ = try await writer.insert(player)
            newPlayerName = ""
        } catch {
            showError = error
        }
    }

    private func addBulkPlayers() async {
        guard let writer else { return }
        do {
            let names = ["Eve", "Frank", "Grace", "Henry", "Ivy"]
            let teams = ["Blue", "Red", "Green", "Yellow"]

            try await writer.batch { db in
                for name in names {
                    var player = Player(
                        name: name,
                        team: teams.randomElement()!,
                        score: Int.random(in: 50...100),
                        joinedAt: Date()
                    )
                    try player.insert(db)
                }
            }
        } catch {
            showError = error
        }
    }

    private func updateAllScores() async {
        guard let writer else { return }
        do {
            try await writer.batch { db in
                var updatedPlayers = try Player.fetchAll(db)
                for i in updatedPlayers.indices {
                    updatedPlayers[i].score += 10
                    try updatedPlayers[i].update(db)
                }
            }
        } catch {
            showError = error
        }
    }

    private func deletePlayers(at offsets: IndexSet) async {
        guard let writer else { return }
        for index in offsets {
            let player = players[index]
            do {
                _ = try await writer.delete(player)
            } catch {
                showError = error
            }
        }
    }

    private func deleteAll() async {
        guard let writer else { return }
        do {
            _ = try await writer.deleteAll(Player.self)
        } catch {
            showError = error
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        GRDBShowcaseView()
    }
}

#Preview("Reactive Demo") {
    NavigationStack {
        if let container = try? GRDBContainer.inMemory() {
            ReactiveQueryDemoView()
                .grdbContainer(container)
                .task {
                    // Run migrations for preview
                    try? GRDBMigrationRunner {
                        GRDBMigration(id: "v1_create_players") { db in
                            try db.create(table: "players", ifNotExists: true) { t in
                                t.autoIncrementedPrimaryKey("id")
                                t.column("name", .text).notNull()
                                t.column("team", .text).notNull()
                                t.column("score", .integer).notNull().defaults(to: 0)
                                t.column("joined_at", .datetime).notNull()
                            }
                        }
                    }.run(on: container)
                }
        }
    }
}
