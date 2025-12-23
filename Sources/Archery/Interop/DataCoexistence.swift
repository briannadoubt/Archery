import Foundation
import CoreData
import SwiftData
import SwiftUI

// MARK: - Data Coexistence Manager

/// Manages coexistence between SwiftData and Core Data in the same app
@MainActor
public final class DataCoexistenceManager {
    public static let shared = DataCoexistenceManager()
    
    private var swiftDataContainer: ModelContainer?
    private var coreDataContainer: NSPersistentContainer?
    private let migrationManager: DataMigrationManager
    
    private init() {
        self.migrationManager = DataMigrationManager()
    }
    
    // MARK: - Setup
    
    /// Initialize both SwiftData and Core Data containers
    public func setup(
        swiftDataSchema: Schema? = nil,
        coreDataModelName: String? = nil,
        configuration: CoexistenceConfiguration = .default
    ) throws {
        // Setup SwiftData if schema provided
        if let schema = swiftDataSchema {
            try setupSwiftData(schema: schema, configuration: configuration)
        }
        
        // Setup Core Data if model name provided
        if let modelName = coreDataModelName {
            try setupCoreData(modelName: modelName, configuration: configuration)
        }
        
        // Setup bridge if both are configured
        if swiftDataContainer != nil && coreDataContainer != nil {
            try setupBridge(configuration: configuration)
        }
    }
    
    private func setupSwiftData(
        schema: Schema,
        configuration: CoexistenceConfiguration
    ) throws {
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: configuration.inMemory,
            allowsSave: !configuration.readOnly
        )
        
        swiftDataContainer = try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
    }
    
    private func setupCoreData(
        modelName: String,
        configuration: CoexistenceConfiguration
    ) throws {
        let container = NSPersistentContainer(name: modelName)
        
        if configuration.inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        }
        
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data failed to load: \(error)")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        coreDataContainer = container
    }
    
    private func setupBridge(configuration: CoexistenceConfiguration) throws {
        guard configuration.enableBridge else { return }
        
        // Setup notification observers for syncing
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(coreDataDidSave(_:)),
            name: .NSManagedObjectContextDidSave,
            object: coreDataContainer?.viewContext
        )
    }
    
    @objc private func coreDataDidSave(_ notification: Notification) {
        // Sync changes to SwiftData if needed
        Task { @MainActor in
            await syncCoreDataToSwiftData(notification: notification)
        }
    }
    
    // MARK: - Migration
    
    /// Migrate data from Core Data to SwiftData
    public func migrateCoreDataToSwiftData<T: PersistentModel>(
        entityName: String,
        transform: @escaping @Sendable (NSManagedObject) throws -> T
    ) async throws -> MigrationResult {
        guard let coreDataContext = coreDataContainer?.viewContext,
              let swiftDataContext = swiftDataContainer?.mainContext else {
            throw CoexistenceError.containersNotConfigured
        }

        let manager = migrationManager
        return try await manager.migrate(
            from: coreDataContext,
            to: swiftDataContext,
            entityName: entityName,
            transform: transform
        )
    }
    
    /// Migrate data from SwiftData to Core Data
    public func migrateSwiftDataToCoreData<T: PersistentModel>(
        modelType: T.Type,
        entityName: String,
        transform: @escaping @Sendable (T, NSManagedObjectContext) throws -> NSManagedObject
    ) async throws -> MigrationResult {
        guard let swiftDataContext = swiftDataContainer?.mainContext,
              let coreDataContext = coreDataContainer?.viewContext else {
            throw CoexistenceError.containersNotConfigured
        }

        let manager = migrationManager
        return try await manager.migrate(
            from: swiftDataContext,
            to: coreDataContext,
            modelType: modelType,
            entityName: entityName,
            transform: transform
        )
    }
    
    // MARK: - Syncing
    
    private func syncCoreDataToSwiftData(notification: Notification) async {
        // Implementation for syncing changes
        // This would handle incremental updates between the two systems
    }
    
    // MARK: - Access
    
    public var swiftDataContext: ModelContext? {
        swiftDataContainer?.mainContext
    }
    
    public var coreDataContext: NSManagedObjectContext? {
        coreDataContainer?.viewContext
    }
}

// MARK: - Migration Manager

public final class DataMigrationManager: Sendable {
    
    /// Migrate from Core Data to SwiftData
    public func migrate<T: PersistentModel>(
        from coreDataContext: NSManagedObjectContext,
        to swiftDataContext: ModelContext,
        entityName: String,
        transform: @escaping @Sendable (NSManagedObject) throws -> T
    ) async throws -> MigrationResult {
        let startTime = Date()
        var migrated = 0
        var failed = 0
        var errors: [Error] = []
        
        // Fetch all Core Data objects
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        let coreDataObjects = try coreDataContext.fetch(request)
        
        // Batch process for better performance
        let batchSize = 100
        for batch in coreDataObjects.chunked(into: batchSize) {
            var batchMigrated = 0
            var batchFailed = 0
            var batchErrors: [Error] = []

            for object in batch {
                do {
                    let swiftDataModel = try transform(object)
                    swiftDataContext.insert(swiftDataModel)
                    batchMigrated += 1
                } catch {
                    batchFailed += 1
                    batchErrors.append(error)
                }
            }

            do {
                try swiftDataContext.save()
                migrated += batchMigrated
                failed += batchFailed
                errors.append(contentsOf: batchErrors)
            } catch {
                failed += batch.count
                errors.append(error)
            }
        }
        
        return MigrationResult(
            itemsMigrated: migrated,
            itemsFailed: failed,
            errors: errors,
            duration: Date().timeIntervalSince(startTime)
        )
    }
    
    /// Migrate from SwiftData to Core Data
    public func migrate<T: PersistentModel>(
        from swiftDataContext: ModelContext,
        to coreDataContext: NSManagedObjectContext,
        modelType: T.Type,
        entityName: String,
        transform: @escaping @Sendable (T, NSManagedObjectContext) throws -> NSManagedObject
    ) async throws -> MigrationResult {
        let startTime = Date()
        var migrated = 0
        var failed = 0
        var errors: [Error] = []
        
        // Fetch all SwiftData objects
        let descriptor = FetchDescriptor<T>()
        let swiftDataObjects = try swiftDataContext.fetch(descriptor)
        
        // Batch process
        let batchSize = 100
        for batch in swiftDataObjects.chunked(into: batchSize) {
            do {
                let (batchMigrated, batchFailed, batchErrors) = try await coreDataContext.perform { () -> (Int, Int, [Error]) in
                    var localMigrated = 0
                    var localFailed = 0
                    var localErrors: [Error] = []

                    for object in batch {
                        do {
                            _ = try transform(object, coreDataContext)
                            localMigrated += 1
                        } catch {
                            localFailed += 1
                            localErrors.append(error)
                        }
                    }

                    if coreDataContext.hasChanges {
                        try coreDataContext.save()
                    }

                    return (localMigrated, localFailed, localErrors)
                }
                migrated += batchMigrated
                failed += batchFailed
                errors.append(contentsOf: batchErrors)
            } catch {
                failed += batch.count
                errors.append(error)
            }
        }
        
        return MigrationResult(
            itemsMigrated: migrated,
            itemsFailed: failed,
            errors: errors,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

// MARK: - Dual Persistence Pattern

/// Protocol for models that can exist in both SwiftData and Core Data
public protocol DualPersistable {
    associatedtype SwiftDataModel: PersistentModel
    associatedtype CoreDataModel: NSManagedObject
    
    func toSwiftData() -> SwiftDataModel
    func toCoreData(context: NSManagedObjectContext) -> CoreDataModel
    
    static func fromSwiftData(_ model: SwiftDataModel) -> Self
    static func fromCoreData(_ object: CoreDataModel) -> Self
}

/// Wrapper that provides unified access to dual-persisted data
public struct DualPersistenceWrapper<Model: DualPersistable> {
    private let swiftDataContext: ModelContext?
    private let coreDataContext: NSManagedObjectContext?
    
    public init(
        swiftDataContext: ModelContext? = nil,
        coreDataContext: NSManagedObjectContext? = nil
    ) {
        self.swiftDataContext = swiftDataContext
        self.coreDataContext = coreDataContext
    }
    
    /// Save a model to both stores
    public func save(_ model: Model) throws {
        if let swiftDataContext = swiftDataContext {
            swiftDataContext.insert(model.toSwiftData())
            try swiftDataContext.save()
        }
        
        if let coreDataContext = coreDataContext {
            _ = model.toCoreData(context: coreDataContext)
            try coreDataContext.save()
        }
    }
    
    /// Fetch from preferred store
    public func fetch(preferSwiftData: Bool = true) throws -> [Model] {
        if preferSwiftData, let swiftDataContext = swiftDataContext {
            let descriptor = FetchDescriptor<Model.SwiftDataModel>()
            let results = try swiftDataContext.fetch(descriptor)
            return results.map { Model.fromSwiftData($0) }
        } else if let coreDataContext = coreDataContext {
            let request = Model.CoreDataModel.fetchRequest()
            let results = try coreDataContext.fetch(request) as! [Model.CoreDataModel]
            return results.map { Model.fromCoreData($0) }
        }
        
        return []
    }
}

// MARK: - Configuration

public struct CoexistenceConfiguration: Sendable {
    public let inMemory: Bool
    public let readOnly: Bool
    public let enableBridge: Bool
    public let syncDirection: SyncDirection
    public let conflictResolution: DataConflictResolution

    public init(
        inMemory: Bool = false,
        readOnly: Bool = false,
        enableBridge: Bool = false,
        syncDirection: SyncDirection = .bidirectional,
        conflictResolution: DataConflictResolution = .latestWins
    ) {
        self.inMemory = inMemory
        self.readOnly = readOnly
        self.enableBridge = enableBridge
        self.syncDirection = syncDirection
        self.conflictResolution = conflictResolution
    }

    public static let `default` = CoexistenceConfiguration()

    public static let testing = CoexistenceConfiguration(
        inMemory: true,
        readOnly: false,
        enableBridge: true
    )
}

public enum SyncDirection: Sendable {
    case coreDataToSwiftData
    case swiftDataToCoreData
    case bidirectional
    case none
}

public enum DataConflictResolution: Sendable {
    case latestWins
    case coreDataWins
    case swiftDataWins
    case manual(@Sendable (Any, Any) -> Any)
}

// MARK: - Migration Result

public struct MigrationResult {
    public let itemsMigrated: Int
    public let itemsFailed: Int
    public let errors: [Error]
    public let duration: TimeInterval
    
    public var success: Bool {
        itemsFailed == 0
    }
    
    public var summary: String {
        """
        Migration completed in \(String(format: "%.2f", duration))s
        ✅ Migrated: \(itemsMigrated) items
        ❌ Failed: \(itemsFailed) items
        """
    }
}

// MARK: - Errors

public enum CoexistenceError: LocalizedError {
    case containersNotConfigured
    case migrationFailed(String)
    case syncFailed(String)
    case incompatibleModels
    
    public var errorDescription: String? {
        switch self {
        case .containersNotConfigured:
            return "Data containers are not configured"
        case .migrationFailed(let reason):
            return "Migration failed: \(reason)"
        case .syncFailed(let reason):
            return "Sync failed: \(reason)"
        case .incompatibleModels:
            return "Models are incompatible between SwiftData and Core Data"
        }
    }
}

// MARK: - SwiftUI Environment

public struct DataCoexistenceEnvironmentKey: @preconcurrency EnvironmentKey {
    @MainActor public static let defaultValue = DataCoexistenceManager.shared
}

public extension EnvironmentValues {
    var dataCoexistence: DataCoexistenceManager {
        get { self[DataCoexistenceEnvironmentKey.self] }
        set { self[DataCoexistenceEnvironmentKey.self] = newValue }
    }
}

// MARK: - Property Wrappers

/// Property wrapper for accessing dual-persisted data in SwiftUI views
/// Note: DynamicProperty is implicitly MainActor in SwiftUI's view update cycle
@propertyWrapper
public struct DualPersisted<Model: DualPersistable>: DynamicProperty {
    @Environment(\.dataCoexistence) private var coexistence
    @State private var data: [Model] = []

    private let preferSwiftData: Bool

    nonisolated public init(preferSwiftData: Bool = true) {
        self.preferSwiftData = preferSwiftData
    }

    @MainActor
    public var wrappedValue: [Model] {
        get { data }
        nonmutating set { data = newValue }
    }

    @MainActor
    public var projectedValue: Binding<[Model]> {
        Binding(
            get: { data },
            set: { data = $0 }
        )
    }
}

// MARK: - Helpers

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}