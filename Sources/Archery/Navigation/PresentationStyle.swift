import Foundation
import SwiftUI

// MARK: - Presentation Style

/// Defines how a route should be presented in the navigation hierarchy.
///
/// Used with `@presents` macro attribute on route cases to specify presentation behavior:
/// ```swift
/// @Route(path: "tasks")
/// enum TasksRoute: NavigationRoute {
///     case list
///     case detail(id: String)
///
///     @presents(.sheet)
///     case create
///
///     @presents(.fullScreen)
///     case bulkEdit
/// }
/// ```
public enum PresentationStyle: Sendable, Hashable, Codable {
    // MARK: - Stack Navigation

    /// Push onto the current NavigationStack (default behavior)
    case push

    /// Replace the current view in the stack
    case replace

    // MARK: - Modal Presentation

    /// Present as a sheet with configurable detents
    case sheet(detents: Set<SheetDetent> = [.large])

    /// Present as a full-screen cover
    case fullScreen

    /// Present as a popover (iPad/Mac) or sheet (iPhone)
    case popover(edge: PopoverEdge = .top)

    // MARK: - Scene Presentation (Platform-Specific)

    /// Open in a new window (macOS, iPadOS with Stage Manager)
    case window(id: String)

    /// Switch to a specific tab
    case tab(index: Int)

    #if os(visionOS)
    /// Open an immersive space (visionOS)
    case immersiveSpace(id: String, style: ImmersiveStyle = .mixed)
    #endif

    #if os(macOS)
    /// Present in the Settings/Preferences window
    case settingsPane

    /// Present as an inspector panel
    case inspector
    #endif

    // MARK: - Default

    /// Default presentation style (push for routes without @presents)
    public static var `default`: PresentationStyle { .push }
}

// MARK: - Sheet Detents

/// Supported sheet detent sizes
public enum SheetDetent: String, Sendable, Hashable, Codable, CaseIterable {
    case small
    case medium
    case large
    case fraction50 = "fraction_50"
    case fraction75 = "fraction_75"

    /// Convert to SwiftUI PresentationDetent
    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    public var presentationDetent: PresentationDetent {
        switch self {
        case .small:
            return .medium // iOS doesn't have .small, use medium
        case .medium:
            return .medium
        case .large:
            return .large
        case .fraction50:
            return .fraction(0.5)
        case .fraction75:
            return .fraction(0.75)
        }
    }
}

// MARK: - Popover Edge

/// Edge for popover attachment
public enum PopoverEdge: String, Sendable, Hashable, Codable, CaseIterable {
    case top
    case bottom
    case leading
    case trailing
}

// MARK: - Immersive Style (visionOS)

#if os(visionOS)
/// Style for immersive spaces on visionOS
public enum ImmersiveStyle: String, Sendable, Hashable, Codable, CaseIterable {
    case mixed
    case progressive
    case full
}
#endif

// MARK: - Presentation Context

/// Tracks the current presentation context for recursive navigation
public struct PresentationContext: Sendable, Hashable {
    public let style: PresentationStyle
    public let depth: Int
    public let parentTab: Int?

    public init(style: PresentationStyle = .push, depth: Int = 0, parentTab: Int? = nil) {
        self.style = style
        self.depth = depth
        self.parentTab = parentTab
    }

    /// Root context for tab content
    public static func tab(_ index: Int) -> PresentationContext {
        PresentationContext(style: .push, depth: 0, parentTab: index)
    }

    /// Context for content presented in a sheet
    public static func sheet(depth: Int = 1, parentTab: Int? = nil) -> PresentationContext {
        PresentationContext(style: .sheet(), depth: depth, parentTab: parentTab)
    }

    /// Context for content presented full screen
    public static func fullScreen(parentTab: Int? = nil) -> PresentationContext {
        PresentationContext(style: .fullScreen, depth: 1, parentTab: parentTab)
    }

    /// Whether this context is a modal presentation
    public var isModal: Bool {
        switch style {
        case .sheet, .fullScreen, .popover:
            return true
        default:
            return false
        }
    }

    /// The sheet depth (0 if not in a sheet)
    public var sheetDepth: Int {
        if case .sheet = style {
            return depth
        }
        return 0
    }
}

// MARK: - Presentation Metadata

/// Metadata extracted from @presents macro for a route case
public struct PresentationMetadata: Sendable, Hashable {
    public let style: PresentationStyle
    public let dismissable: Bool
    public let interactiveDismissDisabled: Bool

    public init(
        style: PresentationStyle = .push,
        dismissable: Bool = true,
        interactiveDismissDisabled: Bool = false
    ) {
        self.style = style
        self.dismissable = dismissable
        self.interactiveDismissDisabled = interactiveDismissDisabled
    }

    /// Default metadata for routes without @presents
    public static var `default`: PresentationMetadata {
        PresentationMetadata()
    }
}

// MARK: - URL Encoding

extension PresentationStyle {
    /// Encode presentation style for deep link query parameter
    public var urlQueryValue: String {
        switch self {
        case .push: return "push"
        case .replace: return "replace"
        case .sheet(let detents):
            let detentString = detents.map(\.rawValue).sorted().joined(separator: ",")
            return "sheet:\(detentString)"
        case .fullScreen: return "fullscreen"
        case .popover(let edge): return "popover:\(edge.rawValue)"
        case .window(let id): return "window:\(id)"
        case .tab(let index): return "tab:\(index)"
        #if os(visionOS)
        case .immersiveSpace(let id, let style): return "immersive:\(id):\(style.rawValue)"
        #endif
        #if os(macOS)
        case .settingsPane: return "settings"
        case .inspector: return "inspector"
        #endif
        }
    }

    /// Decode presentation style from deep link query parameter
    public init?(urlQueryValue: String) {
        let parts = urlQueryValue.split(separator: ":").map(String.init)
        guard let type = parts.first else { return nil }

        switch type {
        case "push": self = .push
        case "replace": self = .replace
        case "sheet":
            if parts.count > 1 {
                let detentStrings = parts[1].split(separator: ",").map(String.init)
                let detents = Set(detentStrings.compactMap { SheetDetent(rawValue: $0) })
                self = .sheet(detents: detents.isEmpty ? [.large] : detents)
            } else {
                self = .sheet()
            }
        case "fullscreen": self = .fullScreen
        case "popover":
            let edge = parts.count > 1 ? PopoverEdge(rawValue: parts[1]) ?? .top : .top
            self = .popover(edge: edge)
        case "window":
            guard parts.count > 1 else { return nil }
            self = .window(id: parts[1])
        case "tab":
            guard parts.count > 1, let index = Int(parts[1]) else { return nil }
            self = .tab(index: index)
        #if os(visionOS)
        case "immersive":
            guard parts.count > 1 else { return nil }
            let id = parts[1]
            let style = parts.count > 2 ? ImmersiveStyle(rawValue: parts[2]) ?? .mixed : .mixed
            self = .immersiveSpace(id: id, style: style)
        #endif
        #if os(macOS)
        case "settings": self = .settingsPane
        case "inspector": self = .inspector
        #endif
        default: return nil
        }
    }
}
