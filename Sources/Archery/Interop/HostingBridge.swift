import SwiftUI
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - UIKit/AppKit Hosting Bridge

/// Bridge for hosting SwiftUI views in UIKit/AppKit
public struct HostingBridge {

    #if os(iOS) || os(tvOS) || os(visionOS)

    // MARK: - UIKit Hosting

    /// Creates a UIViewController hosting a SwiftUI view
    @MainActor
    public static func makeViewController<Content: View>(
        rootView: Content,
        configuration: HostingConfiguration = .default
    ) -> UIViewController {
        let hostingController = ArcheryHostingController(
            rootView: rootView,
            configuration: configuration
        )
        
        // Apply configuration
        hostingController.view.backgroundColor = configuration.backgroundColor
        hostingController.preferredContentSize = configuration.preferredContentSize
        
        if configuration.disableSafeArea {
            hostingController.disableSafeArea()
        }
        
        return hostingController
    }
    
    /// Embed a SwiftUI view in an existing UIView
    @MainActor
    public static func embed<Content: View>(
        _ view: Content,
        in containerView: UIView,
        parent: UIViewController,
        configuration: EmbeddingConfiguration = .default
    ) {
        let hostingController = UIHostingController(rootView: view)
        
        parent.addChild(hostingController)
        containerView.addSubview(hostingController.view)
        
        // Configure constraints
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(
                equalTo: containerView.topAnchor,
                constant: configuration.insets.top
            ),
            hostingController.view.leadingAnchor.constraint(
                equalTo: containerView.leadingAnchor,
                constant: configuration.insets.left
            ),
            hostingController.view.trailingAnchor.constraint(
                equalTo: containerView.trailingAnchor,
                constant: -configuration.insets.right
            ),
            hostingController.view.bottomAnchor.constraint(
                equalTo: containerView.bottomAnchor,
                constant: -configuration.insets.bottom
            )
        ])
        
        hostingController.didMove(toParent: parent)
        
        if configuration.backgroundColor != nil {
            hostingController.view.backgroundColor = configuration.backgroundColor
        }
    }
    
    /// Remove an embedded SwiftUI view
    public static func removeEmbedded(from containerView: UIView) {
        containerView.subviews.forEach { subview in
            if let hostingView = subview as? UIHostingController<AnyView> {
                hostingView.willMove(toParent: nil)
                hostingView.view.removeFromSuperview()
                hostingView.removeFromParent()
            }
        }
    }
    
    #elseif canImport(AppKit)
    
    // MARK: - AppKit Hosting

    /// Creates an NSViewController hosting a SwiftUI view
    @MainActor
    public static func makeViewController<Content: View>(
        rootView: Content,
        configuration: HostingConfiguration = .default
    ) -> NSViewController {
        let hostingController = NSHostingController(rootView: rootView)
        
        // Apply configuration
        hostingController.view.wantsLayer = true
        hostingController.preferredContentSize = configuration.preferredContentSize
        
        if let backgroundColor = configuration.backgroundColor {
            hostingController.view.layer?.backgroundColor = backgroundColor.cgColor
        }
        
        return hostingController
    }
    
    /// Embed a SwiftUI view in an existing NSView
    @MainActor
    public static func embed<Content: View>(
        _ view: Content,
        in containerView: NSView,
        parent: NSViewController,
        configuration: EmbeddingConfiguration = .default
    ) {
        let hostingController = NSHostingController(rootView: view)
        
        parent.addChild(hostingController)
        containerView.addSubview(hostingController.view)
        
        // Configure constraints
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(
                equalTo: containerView.topAnchor,
                constant: configuration.insets.top
            ),
            hostingController.view.leadingAnchor.constraint(
                equalTo: containerView.leadingAnchor,
                constant: configuration.insets.left
            ),
            hostingController.view.trailingAnchor.constraint(
                equalTo: containerView.trailingAnchor,
                constant: -configuration.insets.right
            ),
            hostingController.view.bottomAnchor.constraint(
                equalTo: containerView.bottomAnchor,
                constant: -configuration.insets.bottom
            )
        ])
        
        if let backgroundColor = configuration.backgroundColor {
            hostingController.view.wantsLayer = true
            hostingController.view.layer?.backgroundColor = backgroundColor.cgColor
        }
    }
    
    /// Remove an embedded SwiftUI view
    public static func removeEmbedded(from containerView: NSView) {
        containerView.subviews.forEach { subview in
            if subview.identifier == NSUserInterfaceItemIdentifier("ArcheryHostedView") {
                if let hostingView = subview.superview as? NSHostingView<AnyView> {
                    hostingView.removeFromSuperview()
                }
            }
        }
    }
    
    #endif
}

// MARK: - Configuration Types

public struct HostingConfiguration: @unchecked Sendable {
    public var preferredContentSize: CGSize
    public var backgroundColor: PlatformColor?
    public var disableSafeArea: Bool
    public var navigationBarHidden: Bool
    public var tabBarHidden: Bool

    public init(
        preferredContentSize: CGSize = .zero,
        backgroundColor: PlatformColor? = nil,
        disableSafeArea: Bool = false,
        navigationBarHidden: Bool = false,
        tabBarHidden: Bool = false
    ) {
        self.preferredContentSize = preferredContentSize
        self.backgroundColor = backgroundColor
        self.disableSafeArea = disableSafeArea
        self.navigationBarHidden = navigationBarHidden
        self.tabBarHidden = tabBarHidden
    }

    public static let `default` = HostingConfiguration()
}

public struct EmbeddingConfiguration: @unchecked Sendable {
    public var insets: EdgeInsets
    public var backgroundColor: PlatformColor?
    public var cornerRadius: CGFloat

    public init(
        insets: EdgeInsets = .zero,
        backgroundColor: PlatformColor? = nil,
        cornerRadius: CGFloat = 0
    ) {
        self.insets = insets
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
    }

    public static let `default` = EmbeddingConfiguration()
}

public struct EdgeInsets: Sendable {
    public let top: CGFloat
    public let left: CGFloat
    public let bottom: CGFloat
    public let right: CGFloat

    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = EdgeInsets()
}

// MARK: - Platform Types

#if os(iOS) || os(tvOS) || os(visionOS)
public typealias PlatformColor = UIColor
public typealias PlatformView = UIView
public typealias PlatformViewController = UIViewController
#elseif os(macOS)
public typealias PlatformColor = NSColor
public typealias PlatformView = NSView
public typealias PlatformViewController = NSViewController
#elseif os(watchOS)
// watchOS uses SwiftUI Color since there's no traditional UIKit/AppKit hosting
public typealias PlatformColor = Color
#endif

// MARK: - Custom Hosting Controller

#if os(iOS) || os(tvOS) || os(visionOS)

/// Enhanced UIHostingController with additional functionality
public class ArcheryHostingController<Content: View>: UIHostingController<Content> {
    private let configuration: HostingConfiguration
    
    public init(rootView: Content, configuration: HostingConfiguration = .default) {
        self.configuration = configuration
        super.init(rootView: rootView)
        setupController()
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupController() {
        // Navigation bar configuration
        if configuration.navigationBarHidden {
            navigationController?.setNavigationBarHidden(true, animated: false)
        }
        
        // Tab bar configuration
        #if !os(tvOS)
        if configuration.tabBarHidden {
            hidesBottomBarWhenPushed = true
        }
        #endif
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        if configuration.disableSafeArea {
            disableSafeArea()
        }
    }
    
    func disableSafeArea() {
        guard let viewClass = object_getClass(view) else { return }
        
        let safeAreaInsets: @convention(block) (AnyObject) -> UIEdgeInsets = { _ in
            return .zero
        }
        
        guard let method = class_getInstanceMethod(
            UIView.self,
            #selector(getter: UIView.safeAreaInsets)
        ) else { return }
        
        class_replaceMethod(
            viewClass,
            #selector(getter: UIView.safeAreaInsets),
            imp_implementationWithBlock(safeAreaInsets),
            method_getTypeEncoding(method)
        )
    }
}

#endif

// MARK: - UIKit View Representable

#if os(iOS) || os(tvOS) || os(visionOS)

/// Wrapper to use UIKit views in SwiftUI
public struct UIKitViewRepresentable<ViewType: UIView>: UIViewRepresentable {
    private let makeView: () -> ViewType
    private let updateView: ((ViewType) -> Void)?
    
    public init(
        makeView: @escaping () -> ViewType,
        updateView: ((ViewType) -> Void)? = nil
    ) {
        self.makeView = makeView
        self.updateView = updateView
    }
    
    public func makeUIView(context: Context) -> ViewType {
        makeView()
    }
    
    public func updateUIView(_ uiView: ViewType, context: Context) {
        updateView?(uiView)
    }
}

/// Wrapper to use UIKit view controllers in SwiftUI
public struct UIKitViewControllerRepresentable<ViewControllerType: UIViewController>: UIViewControllerRepresentable {
    private let makeViewController: () -> ViewControllerType
    private let updateViewController: ((ViewControllerType) -> Void)?
    
    public init(
        makeViewController: @escaping () -> ViewControllerType,
        updateViewController: ((ViewControllerType) -> Void)? = nil
    ) {
        self.makeViewController = makeViewController
        self.updateViewController = updateViewController
    }
    
    public func makeUIViewController(context: Context) -> ViewControllerType {
        makeViewController()
    }
    
    public func updateUIViewController(_ uiViewController: ViewControllerType, context: Context) {
        updateViewController?(uiViewController)
    }
}

#endif

// MARK: - AppKit View Representable

#if canImport(AppKit) && !targetEnvironment(macCatalyst)

/// Wrapper to use AppKit views in SwiftUI
public struct AppKitViewRepresentable<ViewType: NSView>: NSViewRepresentable {
    private let makeView: () -> ViewType
    private let updateView: ((ViewType) -> Void)?
    
    public init(
        makeView: @escaping () -> ViewType,
        updateView: ((ViewType) -> Void)? = nil
    ) {
        self.makeView = makeView
        self.updateView = updateView
    }
    
    public func makeNSView(context: Context) -> ViewType {
        makeView()
    }
    
    public func updateNSView(_ nsView: ViewType, context: Context) {
        updateView?(nsView)
    }
}

/// Wrapper to use AppKit view controllers in SwiftUI
public struct AppKitViewControllerRepresentable<ViewControllerType: NSViewController>: NSViewControllerRepresentable {
    private let makeViewController: () -> ViewControllerType
    private let updateViewController: ((ViewControllerType) -> Void)?
    
    public init(
        makeViewController: @escaping () -> ViewControllerType,
        updateViewController: ((ViewControllerType) -> Void)? = nil
    ) {
        self.makeViewController = makeViewController
        self.updateViewController = updateViewController
    }
    
    public func makeNSViewController(context: Context) -> ViewControllerType {
        makeViewController()
    }
    
    public func updateNSViewController(_ nsViewController: ViewControllerType, context: Context) {
        updateViewController?(nsViewController)
    }
}

#endif