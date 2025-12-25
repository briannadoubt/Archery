import Foundation

/// Feature scaffold generator - creates new features with Archery macros
@main
struct FeatureScaffold {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())

        guard arguments.count >= 2 else {
            printUsage()
            exit(1)
        }

        let featureName = arguments[0]
        let outputPath = arguments[1]
        let options = parseOptions(Array(arguments.dropFirst(2)))

        let generator = FeatureGenerator(
            name: featureName,
            outputPath: URL(fileURLWithPath: outputPath),
            options: options
        )

        try generator.generate()
        print("✅ Feature '\(featureName)' created successfully!")
    }

    static func printUsage() {
        print("""
        Usage: feature-scaffold <FeatureName> <OutputPath> [options]

        Options:
          --with-persistence    Include @Persistable model (default: true)
          --with-route          Include @Route enum (default: true)
          --with-viewmodel      Include ViewModel (default: true)
          --with-tests          Include test file (default: true)
          --minimal             Only create View file

        Example:
          feature-scaffold Profile ./Features
          feature-scaffold Settings ./Features --minimal
        """)
    }

    static func parseOptions(_ args: [String]) -> FeatureOptions {
        var options = FeatureOptions()

        if args.contains("--minimal") {
            options.includePersistence = false
            options.includeRoute = false
            options.includeViewModel = false
            options.includeTests = false
        }

        if args.contains("--with-persistence") {
            options.includePersistence = true
        }
        if args.contains("--with-route") {
            options.includeRoute = true
        }
        if args.contains("--with-viewmodel") {
            options.includeViewModel = true
        }
        if args.contains("--with-tests") {
            options.includeTests = true
        }

        return options
    }
}

struct FeatureOptions {
    var includePersistence = true
    var includeRoute = true
    var includeViewModel = true
    var includeTests = true
}

struct FeatureGenerator {
    let name: String
    let outputPath: URL
    let options: FeatureOptions

    private let fileManager = FileManager.default

    func generate() throws {
        // Create feature directory
        let featurePath = outputPath.appendingPathComponent(name)
        try fileManager.createDirectory(at: featurePath, withIntermediateDirectories: true)

        // Generate files
        try generateView(at: featurePath)

        if options.includeViewModel {
            try generateViewModel(at: featurePath)
        }

        if options.includePersistence {
            try generateModel(at: featurePath)
        }

        if options.includeRoute {
            try generateRoute(at: featurePath)
        }

        if options.includeTests {
            try generateTests(at: featurePath)
        }

        print("  Created: \(featurePath.path)")
    }

    // MARK: - View Generation

    private func generateView(at path: URL) throws {
        let viewModelBinding = options.includeViewModel ? """
            @State private var viewModel = \(name)ViewModel()

            """ : ""

        let routeImport = options.includeRoute ? """
            @Environment(\\.navigationHandle) private var nav

            """ : ""

        let content = """
        import SwiftUI
        import Archery

        struct \(name)View: View {
            \(viewModelBinding)\(routeImport)
            var body: some View {
                ScrollView {
                    VStack(spacing: 16) {
                        Text("\(name)")
                            .font(.largeTitle)
                            .bold()

                        Text("Your \(name.lowercased()) content here")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .navigationTitle("\(name)")
            }
        }

        #Preview {
            NavigationStack {
                \(name)View()
            }
        }

        """

        try content.write(to: path.appendingPathComponent("\(name)View.swift"), atomically: true, encoding: .utf8)
        print("  + \(name)View.swift")
    }

    // MARK: - ViewModel Generation

    private func generateViewModel(at path: URL) throws {
        let content = """
        import Foundation
        import Archery

        @MainActor
        @Observable
        final class \(name)ViewModel {
            // MARK: - State

            enum State {
                case idle
                case loading
                case loaded
                case error(Error)
            }

            var state: State = .idle

            // MARK: - Lifecycle

            func onAppear() {
                // Called when view appears
            }

            func onDisappear() {
                // Called when view disappears
            }

            // MARK: - Actions

            func load() async {
                state = .loading

                do {
                    // Load data here
                    state = .loaded
                } catch {
                    state = .error(error)
                }
            }
        }

        """

        try content.write(to: path.appendingPathComponent("\(name)ViewModel.swift"), atomically: true, encoding: .utf8)
        print("  + \(name)ViewModel.swift")
    }

    // MARK: - Model Generation

    private func generateModel(at path: URL) throws {
        let tableName = name.lowercased() + "s"

        let content = """
        import Foundation
        import Archery
        import GRDB

        /// \(name) model with database persistence.
        ///
        /// The `@Persistable` macro generates:
        /// - Columns enum for type-safe queries
        /// - Database table name
        /// - App Intents (AppEntity, CreateIntent, ListIntent, DeleteIntent)
        @Persistable(
            table: "\(tableName)",
            displayName: "\(name)",
            titleProperty: "title"
        )
        struct \(name)Item: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
            @PrimaryKey var id: String
            var title: String
            var itemDescription: String?
            @CreatedAt var createdAt: Date

            enum CodingKeys: String, CodingKey {
                case id
                case title
                case itemDescription = "description"
                case createdAt = "created_at"
            }

            init(
                id: String = UUID().uuidString,
                title: String,
                itemDescription: String? = nil,
                createdAt: Date = Date()
            ) {
                self.id = id
                self.title = title
                self.itemDescription = itemDescription
                self.createdAt = createdAt
            }
        }

        // MARK: - Query Sources

        extension \(name)Item: HasQuerySources {
            @QuerySources
            struct Sources: Sendable {
                var all: QuerySource<\(name)Item> {
                    QuerySource(\(name)Item.all())
                }

                var byCreatedAt: QuerySource<\(name)Item> {
                    QuerySource(\(name)Item.all().order(by: Columns.createdAt, ascending: false))
                }
            }
        }

        """

        try content.write(to: path.appendingPathComponent("\(name)Item.swift"), atomically: true, encoding: .utf8)
        print("  + \(name)Item.swift")
    }

    // MARK: - Route Generation

    private func generateRoute(at path: URL) throws {
        let routePath = name.lowercased()

        let content = """
        import SwiftUI
        import Archery

        @Route(path: "\(routePath)")
        enum \(name)Route: NavigationRoute {
            case root
            case detail(id: String)

            @presents(.sheet)
            case create

            @presents(.sheet, detents: [.medium, .large])
            case edit(id: String)
        }

        """

        try content.write(to: path.appendingPathComponent("\(name)Route.swift"), atomically: true, encoding: .utf8)
        print("  + \(name)Route.swift")
    }

    // MARK: - Tests Generation

    private func generateTests(at path: URL) throws {
        let content = """
        import XCTest
        @testable import Archery

        final class \(name)Tests: XCTestCase {

            func test\(name)ViewModelInitialState() {
                let viewModel = \(name)ViewModel()

                switch viewModel.state {
                case .idle:
                    break // Expected
                default:
                    XCTFail("Expected idle state")
                }
            }

            func test\(name)ItemCreation() {
                let item = \(name)Item(title: "Test \(name)")

                XCTAssertFalse(item.id.isEmpty)
                XCTAssertEqual(item.title, "Test \(name)")
                XCTAssertNil(item.itemDescription)
            }
        }

        """

        try content.write(to: path.appendingPathComponent("\(name)Tests.swift"), atomically: true, encoding: .utf8)
        print("  + \(name)Tests.swift")
    }
}
