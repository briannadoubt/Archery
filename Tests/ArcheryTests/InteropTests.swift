import XCTest
import SwiftUI
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
        XCTAssertEqual(sources.count, 3)
        #endif
    }
}