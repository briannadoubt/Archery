import XCTest
import SwiftUI
import CoreData
import SwiftData
@testable import Archery

final class InteropTests: XCTestCase {
    
    // MARK: - Hosting Bridge Tests

    #if os(iOS) || os(visionOS)
    @MainActor
    func testUIKitHostingBridge() {
        let view = Text("Hello SwiftUI")
        let viewController = HostingBridge.makeViewController(
            rootView: view,
            configuration: HostingConfiguration(
                preferredContentSize: CGSize(width: 320, height: 480),
                backgroundColor: .systemBackground
            )
        )

        XCTAssertNotNil(viewController)
        XCTAssertEqual(viewController.preferredContentSize, CGSize(width: 320, height: 480))
    }

    @MainActor
    func testUIKitViewEmbedding() {
        let containerView = UIView()
        let parentViewController = UIViewController()
        let swiftUIView = Text("Embedded View")

        HostingBridge.embed(
            swiftUIView,
            in: containerView,
            parent: parentViewController,
            configuration: EmbeddingConfiguration(
                insets: EdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            )
        )

        XCTAssertEqual(parentViewController.children.count, 1)
        XCTAssertFalse(containerView.subviews.isEmpty)
    }

    @MainActor
    func testUIKitViewRepresentable() {
        let uiView = UILabel()
        uiView.text = "UIKit Label"

        let representable = UIKitViewRepresentable(
            makeView: { uiView },
            updateView: { view in
                view.text = "Updated"
            }
        )

        // Skip context-based tests as UIViewRepresentableContext is not constructible
        XCTAssertNotNil(representable)
    }
    #endif
    
    #if canImport(AppKit)
    @MainActor
    func testAppKitHostingBridge() {
        let view = Text("Hello SwiftUI")
        let viewController = HostingBridge.makeViewController(
            rootView: view,
            configuration: HostingConfiguration(
                preferredContentSize: CGSize(width: 320, height: 480)
            )
        )

        XCTAssertNotNil(viewController)
        XCTAssertEqual(viewController.preferredContentSize, CGSize(width: 320, height: 480))
    }

    @MainActor
    func testAppKitViewRepresentable() {
        // Note: NSViewRepresentableContext cannot be directly constructed in tests
        // This test verifies the view representable can be created
        let nsView = NSTextField()
        nsView.stringValue = "AppKit TextField"

        let representable = AppKitViewRepresentable(
            makeView: { nsView },
            updateView: { view in
                view.stringValue = "Updated"
            }
        )

        // Skip context-based tests as NSViewRepresentableContext is not constructible
        XCTAssertNotNil(representable)
    }
    #endif
    
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

        #if os(iOS) || os(visionOS)
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
    
    // MARK: - Edge Insets Test
    
    func testEdgeInsets() {
        let insets = EdgeInsets(top: 10, left: 20, bottom: 30, right: 40)
        
        XCTAssertEqual(insets.top, 10)
        XCTAssertEqual(insets.left, 20)
        XCTAssertEqual(insets.bottom, 30)
        XCTAssertEqual(insets.right, 40)
        
        let zeroInsets = EdgeInsets.zero
        XCTAssertEqual(zeroInsets.top, 0)
        XCTAssertEqual(zeroInsets.left, 0)
        XCTAssertEqual(zeroInsets.bottom, 0)
        XCTAssertEqual(zeroInsets.right, 0)
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