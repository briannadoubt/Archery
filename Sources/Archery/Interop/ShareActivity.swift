import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
import UniformTypeIdentifiers

// MARK: - Share Sheet Wrapper

/// SwiftUI wrapper for platform share sheets
public struct ShareSheet: ViewModifier {
    @Binding var isPresented: Bool
    let items: [Any]
    let excludedActivityTypes: [ActivityType]?
    let completion: ((Bool) -> Void)?
    
    public init(
        isPresented: Binding<Bool>,
        items: [Any],
        excludedActivityTypes: [ActivityType]? = nil,
        completion: ((Bool) -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self.items = items
        self.excludedActivityTypes = excludedActivityTypes
        self.completion = completion
    }
    
    public func body(content: Content) -> some View {
        #if canImport(UIKit)
        content
            .sheet(isPresented: $isPresented) {
                ShareActivityViewController(
                    activityItems: items,
                    excludedActivityTypes: excludedActivityTypes,
                    completion: completion
                )
                .ignoresSafeArea()
            }
        #elseif canImport(AppKit)
        content
            .onChange(of: isPresented) { newValue in
                if newValue {
                    showMacShareSheet()
                }
            }
        #else
        content
        #endif
    }
    
    #if canImport(AppKit)
    private func showMacShareSheet() {
        guard let window = NSApplication.shared.keyWindow else { return }
        
        let picker = NSSharingServicePicker(items: items)
        picker.delegate = MacShareDelegate(completion: { success in
            isPresented = false
            completion?(success)
        })
        
        if let contentView = window.contentView {
            picker.show(
                relativeTo: .zero,
                of: contentView,
                preferredEdge: .minY
            )
        }
    }
    #endif
}

// MARK: - iOS/iPadOS Share Activity

#if canImport(UIKit)

/// UIKit activity view controller wrapper for SwiftUI
public struct ShareActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let excludedActivityTypes: [ActivityType]?
    let completion: ((Bool) -> Void)?
    
    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        if let excluded = excludedActivityTypes {
            controller.excludedActivityTypes = excluded.compactMap { $0.uiActivityType }
        }
        
        controller.completionWithItemsHandler = { _, completed, _, _ in
            completion?(completed)
        }
        
        // iPad configuration
        if let popover = controller.popoverPresentationController {
            popover.sourceView = UIView()
            popover.sourceRect = .zero
            popover.permittedArrowDirections = []
        }
        
        return controller
    }
    
    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

#endif

// MARK: - macOS Share Delegate

#if canImport(AppKit)

class MacShareDelegate: NSObject, NSSharingServicePickerDelegate {
    let completion: ((Bool) -> Void)?
    
    init(completion: ((Bool) -> Void)?) {
        self.completion = completion
    }
    
    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose service: NSSharingService?
    ) {
        completion?(service != nil)
    }
}

#endif

// MARK: - Activity Types

public enum ActivityType {
    case message
    case mail
    case print
    case copyToPasteboard
    case airDrop
    case postToFacebook
    case postToTwitter
    case saveToCameraRoll
    case addToReadingList
    case postToFlickr
    case postToVimeo
    case postToTencentWeibo
    case postToWeibo
    case assignToContact
    case openInIBooks
    case markupAsPDF
    case custom(String)
    
    #if canImport(UIKit)
    var uiActivityType: UIActivity.ActivityType? {
        switch self {
        case .message: return .message
        case .mail: return .mail
        case .print: return .print
        case .copyToPasteboard: return .copyToPasteboard
        case .airDrop: return .airDrop
        case .postToFacebook: return .postToFacebook
        case .postToTwitter: return .postToTwitter
        case .saveToCameraRoll: return .saveToCameraRoll
        case .addToReadingList: return .addToReadingList
        case .postToFlickr: return .postToFlickr
        case .postToVimeo: return .postToVimeo
        case .postToTencentWeibo: return .postToTencentWeibo
        case .postToWeibo: return .postToWeibo
        case .assignToContact: return .assignToContact
        case .openInIBooks: return .openInIBooks
        case .markupAsPDF: return .markupAsPDF
        case .custom(let identifier): return UIActivity.ActivityType(identifier)
        }
    }
    #endif
}

// MARK: - Share Link

/// SwiftUI-native share link with platform-specific behavior
public struct ShareLink<Label: View>: View {
    let items: [Any]
    let subject: String?
    let message: String?
    let preview: SharePreview?
    let label: Label
    
    @State private var showingShareSheet = false
    
    public init(
        items: [Any],
        subject: String? = nil,
        message: String? = nil,
        preview: SharePreview? = nil,
        @ViewBuilder label: () -> Label
    ) {
        self.items = items
        self.subject = subject
        self.message = message
        self.preview = preview
        self.label = label()
    }
    
    public var body: some View {
        Button(action: share) {
            label
        }
        .modifier(ShareSheet(
            isPresented: $showingShareSheet,
            items: prepareItems()
        ))
    }
    
    private func share() {
        showingShareSheet = true
    }
    
    private func prepareItems() -> [Any] {
        var shareItems = items
        
        if let message = message {
            shareItems.append(message)
        }
        
        if let preview = preview {
            shareItems.append(preview)
        }
        
        return shareItems
    }
}

// MARK: - Share Preview

public struct SharePreview {
    public let title: String
    public let image: Image?
    public let icon: Image?
    
    public init(
        title: String,
        image: Image? = nil,
        icon: Image? = nil
    ) {
        self.title = title
        self.image = image
        self.icon = icon
    }
}

// MARK: - Document Picker

/// Cross-platform document picker
public struct DocumentPicker: ViewModifier {
    @Binding var isPresented: Bool
    let allowedContentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onCompletion: (Result<[URL], Error>) -> Void
    
    public func body(content: Content) -> some View {
        #if canImport(UIKit)
        content
            .sheet(isPresented: $isPresented) {
                DocumentPickerViewController(
                    allowedContentTypes: allowedContentTypes,
                    allowsMultipleSelection: allowsMultipleSelection,
                    onCompletion: onCompletion
                )
                .ignoresSafeArea()
            }
        #elseif canImport(AppKit)
        content
            .onChange(of: isPresented) { newValue in
                if newValue {
                    showMacDocumentPicker()
                }
            }
        #else
        content
        #endif
    }
    
    #if canImport(AppKit)
    private func showMacDocumentPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = allowedContentTypes
        
        panel.begin { response in
            isPresented = false
            
            if response == .OK {
                onCompletion(.success(panel.urls))
            } else {
                onCompletion(.failure(DocumentPickerError.cancelled))
            }
        }
    }
    #endif
}

#if canImport(UIKit)

/// UIKit document picker wrapper
public struct DocumentPickerViewController: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onCompletion: (Result<[URL], Error>) -> Void
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }
    
    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: allowedContentTypes,
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = allowsMultipleSelection
        return picker
    }
    
    public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No updates needed
    }
    
    public class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onCompletion: (Result<[URL], Error>) -> Void
        
        init(onCompletion: @escaping (Result<[URL], Error>) -> Void) {
            self.onCompletion = onCompletion
        }
        
        public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onCompletion(.success(urls))
        }
        
        public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCompletion(.failure(DocumentPickerError.cancelled))
        }
    }
}

#endif

// MARK: - Image Picker

/// Cross-platform image picker
public struct ImagePicker: ViewModifier {
    @Binding var isPresented: Bool
    let sourceType: ImageSourceType
    let allowsEditing: Bool
    let onCompletion: (Result<PlatformImage, Error>) -> Void
    
    public func body(content: Content) -> some View {
        #if canImport(UIKit)
        content
            .sheet(isPresented: $isPresented) {
                ImagePickerViewController(
                    sourceType: sourceType.uiSourceType,
                    allowsEditing: allowsEditing,
                    onCompletion: onCompletion
                )
                .ignoresSafeArea()
            }
        #else
        content
        #endif
    }
}

public enum ImageSourceType {
    case camera
    case photoLibrary
    case savedPhotosAlbum
    
    #if canImport(UIKit)
    var uiSourceType: UIImagePickerController.SourceType {
        switch self {
        case .camera: return .camera
        case .photoLibrary: return .photoLibrary
        case .savedPhotosAlbum: return .savedPhotosAlbum
        }
    }
    #endif
}

#if canImport(UIKit)

/// UIKit image picker wrapper
public struct ImagePickerViewController: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let allowsEditing: Bool
    let onCompletion: (Result<UIImage, Error>) -> Void
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }
    
    public func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.allowsEditing = allowsEditing
        picker.delegate = context.coordinator
        return picker
    }
    
    public func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // No updates needed
    }
    
    public class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCompletion: (Result<UIImage, Error>) -> Void
        
        init(onCompletion: @escaping (Result<UIImage, Error>) -> Void) {
            self.onCompletion = onCompletion
        }
        
        public func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                onCompletion(.success(image))
            } else {
                onCompletion(.failure(ImagePickerError.noImageSelected))
            }
        }
        
        public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCompletion(.failure(ImagePickerError.cancelled))
        }
    }
}

#endif

// MARK: - Platform Image Types

#if canImport(UIKit)
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
public typealias PlatformImage = NSImage
#endif

// MARK: - Errors

public enum DocumentPickerError: LocalizedError {
    case cancelled
    case accessDenied
    case invalidURL
    
    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Document selection was cancelled"
        case .accessDenied:
            return "Access to the document was denied"
        case .invalidURL:
            return "The selected document URL is invalid"
        }
    }
}

public enum ImagePickerError: LocalizedError {
    case cancelled
    case noImageSelected
    case cameraNotAvailable
    
    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Image selection was cancelled"
        case .noImageSelected:
            return "No image was selected"
        case .cameraNotAvailable:
            return "Camera is not available on this device"
        }
    }
}

// MARK: - View Extensions

public extension View {
    /// Present a share sheet
    func shareSheet(
        isPresented: Binding<Bool>,
        items: [Any],
        excludedActivityTypes: [ActivityType]? = nil,
        completion: ((Bool) -> Void)? = nil
    ) -> some View {
        modifier(ShareSheet(
            isPresented: isPresented,
            items: items,
            excludedActivityTypes: excludedActivityTypes,
            completion: completion
        ))
    }
    
    /// Present a document picker
    func documentPicker(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool = false,
        onCompletion: @escaping (Result<[URL], Error>) -> Void
    ) -> some View {
        modifier(DocumentPicker(
            isPresented: isPresented,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: allowsMultipleSelection,
            onCompletion: onCompletion
        ))
    }
    
    /// Present an image picker
    func imagePicker(
        isPresented: Binding<Bool>,
        sourceType: ImageSourceType,
        allowsEditing: Bool = false,
        onCompletion: @escaping (Result<PlatformImage, Error>) -> Void
    ) -> some View {
        modifier(ImagePicker(
            isPresented: isPresented,
            sourceType: sourceType,
            allowsEditing: allowsEditing,
            onCompletion: onCompletion
        ))
    }
}