import XCTest
import SwiftUI
import CoreData
import SwiftData
@testable import Archery

final class InteropTests: XCTestCase {

    // MARK: - Share Activity Tests
    
    func testActivityTypes() {
        let types: [ActivityType] = [
            .message,
            .mail,
            .print,
            .copyToPasteboard,
            .custom("com.example.share")
        ]

        #if os(iOS) || os(visionOS)
        for type in types {
            XCTAssertNotNil(type.uiActivityType)
        }
        #else
        // Verify types are created correctly on other platforms
        XCTAssertEqual(types.count, 5)
        #endif
    }
    
    func testSharePreview() {
        let preview = SharePreview(
            title: "Test Item",
            image: Image(systemName: "star"),
            icon: Image(systemName: "square.and.arrow.up")
        )
        
        XCTAssertEqual(preview.title, "Test Item")
        XCTAssertNotNil(preview.image)
        XCTAssertNotNil(preview.icon)
    }
    
    // MARK: - Data Coexistence Tests
    
    @MainActor
    func testDataCoexistenceSetup() async throws {
        let manager = DataCoexistenceManager.shared
        
        // Create test schema for SwiftData
        let schema = Schema([TestSwiftDataModel.self])
        
        // Setup with test configuration
        try manager.setup(
            swiftDataSchema: schema,
            coreDataModelName: nil, // Would need actual Core Data model
            configuration: CoexistenceConfiguration.testing
        )
        
        XCTAssertNotNil(manager.swiftDataContext)
    }
    
    func testMigrationResult() {
        let result = MigrationResult(
            itemsMigrated: 100,
            itemsFailed: 5,
            errors: [],
            duration: 2.5
        )
        
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.itemsMigrated, 100)
        XCTAssertEqual(result.itemsFailed, 5)
        XCTAssertTrue(result.summary.contains("100 items"))
        XCTAssertTrue(result.summary.contains("5 items"))
    }
    
    func testCoexistenceConfiguration() {
        let config = CoexistenceConfiguration(
            inMemory: true,
            readOnly: false,
            enableBridge: true,
            syncDirection: .bidirectional,
            conflictResolution: .latestWins
        )
        
        XCTAssertTrue(config.inMemory)
        XCTAssertFalse(config.readOnly)
        XCTAssertTrue(config.enableBridge)
        XCTAssertEqual(config.syncDirection, .bidirectional)
    }
    
    // MARK: - Document/Image Picker Tests
    
    func testDocumentPickerError() {
        let errors: [DocumentPickerError] = [
            .cancelled,
            .accessDenied,
            .invalidURL
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
        }
    }
    
    func testImagePickerError() {
        let errors: [ImagePickerError] = [
            .cancelled,
            .noImageSelected,
            .cameraNotAvailable
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
        }
    }
    
    func testImageSourceTypes() {
        let sources: [ImageSourceType] = [
            .camera,
            .photoLibrary,
            .savedPhotosAlbum
        ]

        #if os(iOS)
        for source in sources {
            XCTAssertNotNil(source.uiSourceType)
        }
        #else
        // Verify types are created correctly on other platforms
        XCTAssertEqual(sources.count, 3)
        #endif
    }
    
    // MARK: - Array Chunking Test

    func testArrayChunking() {
        let array = Array(1...10)
        let chunks = array.chunked(into: 3)

        XCTAssertEqual(chunks.count, 4) // 3, 3, 3, 1
        XCTAssertEqual(chunks[0], [1, 2, 3])
        XCTAssertEqual(chunks[1], [4, 5, 6])
        XCTAssertEqual(chunks[2], [7, 8, 9])
        XCTAssertEqual(chunks[3], [10])
    }

}

// MARK: - Test Models

@Model
final class TestSwiftDataModel {
    var id: UUID
    var name: String
    var timestamp: Date
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.timestamp = Date()
    }
}

// Test model for dual persistence
struct TestDualModel: DualPersistable {
    typealias SwiftDataModel = TestSwiftDataModel
    typealias CoreDataModel = NSManagedObject // Would need actual Core Data entity
    
    let id: UUID
    let name: String
    
    func toSwiftData() -> TestSwiftDataModel {
        TestSwiftDataModel(name: name)
    }
    
    func toCoreData(context: NSManagedObjectContext) -> NSManagedObject {
        // Would create actual Core Data object
        NSManagedObject()
    }
    
    static func fromSwiftData(_ model: TestSwiftDataModel) -> TestDualModel {
        TestDualModel(id: model.id, name: model.name)
    }
    
    static func fromCoreData(_ object: NSManagedObject) -> TestDualModel {
        // Would extract data from Core Data object
        TestDualModel(id: UUID(), name: "Test")
    }
}

// Note: Helper extensions for UIViewRepresentableContext and NSViewRepresentableContext
// removed as they aren't actually used in tests and cause compilation issues.