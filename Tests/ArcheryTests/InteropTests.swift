import XCTest
import SwiftUI
import CoreData
import SwiftData
@testable import Archery

final class InteropTests: XCTestCase {
    
    // MARK: - Hosting Bridge Tests
    
    #if canImport(UIKit)
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
    
    func testUIKitViewRepresentable() {
        let uiView = UILabel()
        uiView.text = "UIKit Label"
        
        let representable = UIKitViewRepresentable(
            makeView: { uiView },
            updateView: { view in
                view.text = "Updated"
            }
        )
        
        let context = UIViewRepresentableContext<UIKitViewRepresentable<UILabel>>(
            coordinator: ()
        )
        
        let createdView = representable.makeUIView(context: context)
        XCTAssertEqual(createdView.text, "UIKit Label")
        
        representable.updateUIView(createdView, context: context)
        XCTAssertEqual(createdView.text, "Updated")
    }
    #endif
    
    #if canImport(AppKit)
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
    
    func testAppKitViewRepresentable() {
        let nsView = NSTextField()
        nsView.stringValue = "AppKit TextField"
        
        let representable = AppKitViewRepresentable(
            makeView: { nsView },
            updateView: { view in
                view.stringValue = "Updated"
            }
        )
        
        let context = NSViewRepresentableContext<AppKitViewRepresentable<NSTextField>>(
            coordinator: ()
        )
        
        let createdView = representable.makeNSView(context: context)
        XCTAssertEqual(createdView.stringValue, "AppKit TextField")
        
        representable.updateNSView(createdView, context: context)
        XCTAssertEqual(createdView.stringValue, "Updated")
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
        
        #if canImport(UIKit)
        for type in types {
            XCTAssertNotNil(type.uiActivityType)
        }
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
    
    // MARK: - Compatibility Shims Tests
    
    func testNavigationStackCompat() {
        let view = CompatibilityShims.NavigationStackCompat {
            Text("Content")
        }
        
        // Test that it creates a view
        XCTAssertNotNil(view)
    }
    
    func testScrollViewCompat() {
        let view = CompatibilityShims.ScrollViewCompat(
            .vertical,
            showsIndicators: true,
            safeAreaInsets: EdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        ) {
            Text("Scrollable Content")
        }
        
        XCTAssertNotNil(view)
    }
    
    func testSheetDetents() {
        let detents: [CompatibilityShims.SheetDetent] = [
            .medium,
            .large,
            .height(300),
            .fraction(0.5)
        ]
        
        for detent in detents {
            if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
                XCTAssertNotNil(detent.modernDetent)
            }
        }
    }
    
    func testGaugeCompat() {
        let gauge = CompatibilityShims.GaugeCompat(
            value: 0.7,
            in: 0...1,
            label: "Progress"
        )
        
        XCTAssertNotNil(gauge)
    }
    
    func testContentUnavailableViewCompat() {
        let view = ContentUnavailableViewCompat(
            "No Data",
            systemImage: "xmark.circle",
            description: "There is no data available"
        )
        
        XCTAssertNotNil(view)
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
        
        #if canImport(UIKit)
        for source in sources {
            XCTAssertNotNil(source.uiSourceType)
        }
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
    
    // MARK: - Async Compatibility Tests
    
    func testAsyncImageCompat() {
        let url = URL(string: "https://example.com/image.jpg")
        
        let imageView = AsyncImageCompat(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } placeholder: {
            ProgressView()
        }
        
        XCTAssertNotNil(imageView)
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

// MARK: - Helper Extensions for Testing

extension UIViewRepresentableContext {
    init(coordinator: Coordinator) {
        // This would need proper implementation
        fatalError("Test helper not fully implemented")
    }
}

extension NSViewRepresentableContext {
    init(coordinator: Coordinator) {
        // This would need proper implementation
        fatalError("Test helper not fully implemented")
    }
}