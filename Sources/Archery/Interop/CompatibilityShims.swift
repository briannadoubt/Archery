import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Compatibility Shims for Older OS Versions

/// Provides backward compatibility for newer SwiftUI features
public struct CompatibilityShims {
    
    // MARK: - Navigation Compatibility
    
    /// Navigation stack compatibility for iOS 15 and below
    public struct NavigationStackCompat<Content: View>: View {
        let content: Content
        
        public init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }
        
        public var body: some View {
            if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
                NavigationStack {
                    content
                }
            } else {
                NavigationView {
                    content
                }
                .navigationViewStyle(.stack)
            }
        }
    }
    
    /// Navigation split view compatibility
    public struct NavigationSplitViewCompat<Sidebar: View, Detail: View>: View {
        let sidebar: Sidebar
        let detail: Detail
        
        public init(
            @ViewBuilder sidebar: () -> Sidebar,
            @ViewBuilder detail: () -> Detail
        ) {
            self.sidebar = sidebar()
            self.detail = detail()
        }
        
        public var body: some View {
            if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
                NavigationSplitView {
                    sidebar
                } detail: {
                    detail
                }
            } else {
                NavigationView {
                    sidebar
                    detail
                }
            }
        }
    }
    
    // MARK: - ScrollView Compatibility
    
    /// ScrollView with safe area inset compatibility
    public struct ScrollViewCompat<Content: View>: View {
        let axes: Axis.Set
        let showsIndicators: Bool
        let content: Content
        let safeAreaInsets: EdgeInsets?
        
        public init(
            _ axes: Axis.Set = .vertical,
            showsIndicators: Bool = true,
            safeAreaInsets: EdgeInsets? = nil,
            @ViewBuilder content: () -> Content
        ) {
            self.axes = axes
            self.showsIndicators = showsIndicators
            self.safeAreaInsets = safeAreaInsets
            self.content = content()
        }
        
        public var body: some View {
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
                ScrollView(axes, showsIndicators: showsIndicators) {
                    content
                }
                .safeAreaInset(edge: .bottom) {
                    if let insets = safeAreaInsets {
                        Color.clear.frame(height: insets.bottom)
                    }
                }
            } else {
                ScrollView(axes, showsIndicators: showsIndicators) {
                    content
                    if let insets = safeAreaInsets {
                        Color.clear.frame(height: insets.bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Sheet Presentation Compatibility
    
    /// Sheet presentation detents compatibility
    public struct SheetCompat<Content: View>: ViewModifier {
        @Binding var isPresented: Bool
        let detents: [SheetDetent]
        let content: Content
        
        public init(
            isPresented: Binding<Bool>,
            detents: [SheetDetent] = [.large],
            @ViewBuilder content: () -> Content
        ) {
            self._isPresented = isPresented
            self.detents = detents
            self.content = content()
        }
        
        public func body(content: Content) -> some View {
            if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
                content.sheet(isPresented: $isPresented) {
                    self.content
                        .presentationDetents(Set(detents.map { $0.modernDetent }))
                }
            } else {
                content.sheet(isPresented: $isPresented) {
                    self.content
                }
            }
        }
    }
    
    public enum SheetDetent {
        case medium
        case large
        case height(CGFloat)
        case fraction(CGFloat)
        
        @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
        var modernDetent: PresentationDetent {
            switch self {
            case .medium:
                return .medium
            case .large:
                return .large
            case .height(let height):
                return .height(height)
            case .fraction(let fraction):
                return .fraction(fraction)
            }
        }
    }
    
    // MARK: - Grid Compatibility
    
    /// Grid layout compatibility for iOS 15 and below
    public struct GridCompat<Content: View>: View {
        let columns: [GridItem]
        let spacing: CGFloat?
        let content: Content
        
        public init(
            columns: [GridItem],
            spacing: CGFloat? = nil,
            @ViewBuilder content: () -> Content
        ) {
            self.columns = columns
            self.spacing = spacing
            self.content = content()
        }
        
        public var body: some View {
            if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
                Grid(alignment: .leading, horizontalSpacing: spacing, verticalSpacing: spacing) {
                    content
                }
            } else {
                LazyVGrid(columns: columns, spacing: spacing) {
                    content
                }
            }
        }
    }
    
    // MARK: - ViewThatFits Compatibility
    
    /// ViewThatFits compatibility for older OS versions
    public struct ViewThatFitsCompat<Content: View>: View {
        let content: [AnyView]
        
        public init(@ViewBuilder content: () -> Content) {
            if let tupleContent = content() as? TupleView<Content> {
                self.content = []  // Would need reflection to extract tuple elements
            } else {
                self.content = [AnyView(content())]
            }
        }
        
        public var body: some View {
            if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
                ViewThatFits {
                    ForEach(0..<content.count, id: \.self) { index in
                        content[index]
                    }
                }
            } else {
                // Fallback to first view
                content.first ?? AnyView(EmptyView())
            }
        }
    }
    
    // MARK: - Gauge Compatibility
    
    /// Gauge view compatibility
    public struct GaugeCompat: View {
        let value: Double
        let label: String
        let range: ClosedRange<Double>
        
        public init(
            value: Double,
            in range: ClosedRange<Double> = 0...1,
            label: String
        ) {
            self.value = value
            self.range = range
            self.label = label
        }
        
        public var body: some View {
            if #available(iOS 16.0, macOS 13.0, watchOS 9.0, *) {
                Gauge(value: value, in: range) {
                    Text(label)
                }
            } else {
                // Fallback to progress view
                VStack(alignment: .leading) {
                    Text(label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ProgressView(value: value, total: range.upperBound)
                }
            }
        }
    }
    
    // MARK: - Table Compatibility
    
    /// Table view compatibility for macOS
    #if os(macOS)
    public struct TableCompat<Data, Content>: View where Data: RandomAccessCollection, Content: View {
        let data: Data
        let content: (Data.Element) -> Content
        
        public init(
            _ data: Data,
            @ViewBuilder content: @escaping (Data.Element) -> Content
        ) {
            self.data = data
            self.content = content
        }
        
        public var body: some View {
            if #available(macOS 12.0, *) {
                Table(data) { item in
                    TableRow(item) {
                        content(item)
                    }
                }
            } else {
                List(data, id: \.self) { item in
                    content(item)
                }
            }
        }
    }
    #endif
    
    // MARK: - ShareLink Compatibility
    
    /// ShareLink compatibility for older OS versions
    public struct ShareLinkCompat<Item, Label: View>: View {
        let item: Item
        let label: Label
        @State private var showShareSheet = false
        
        public init(
            item: Item,
            @ViewBuilder label: () -> Label
        ) {
            self.item = item
            self.label = label()
        }
        
        public var body: some View {
            if #available(iOS 16.0, macOS 13.0, watchOS 9.0, *) {
                ShareLink(item: item) {
                    label
                }
            } else {
                Button(action: { showShareSheet = true }) {
                    label
                }
                .modifier(ShareSheet(
                    isPresented: $showShareSheet,
                    items: [item]
                ))
            }
        }
    }
    
    // MARK: - LabeledContent Compatibility
    
    /// LabeledContent compatibility
    public struct LabeledContentCompat<Label: View, Content: View>: View {
        let label: Label
        let content: Content
        
        public init(
            @ViewBuilder label: () -> Label,
            @ViewBuilder content: () -> Content
        ) {
            self.label = label()
            self.content = content()
        }
        
        public var body: some View {
            if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
                LabeledContent {
                    content
                } label: {
                    label
                }
            } else {
                HStack {
                    label
                    Spacer()
                    content
                }
            }
        }
    }
}

// MARK: - Async Image Compatibility

/// AsyncImage compatibility for iOS 14 and below
public struct AsyncImageCompat<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var image: PlatformImage?
    
    public init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }
    
    public var body: some View {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    content(image)
                case .failure(_), .empty:
                    placeholder()
                @unknown default:
                    placeholder()
                }
            }
        } else {
            Group {
                if let image = image {
                    #if canImport(UIKit)
                    content(Image(uiImage: image))
                    #elseif canImport(AppKit)
                    content(Image(nsImage: image))
                    #endif
                } else {
                    placeholder()
                        .onAppear {
                            loadImage()
                        }
                }
            }
        }
    }
    
    private func loadImage() {
        guard let url = url else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else { return }
            
            DispatchQueue.main.async {
                #if canImport(UIKit)
                self.image = UIImage(data: data)
                #elseif canImport(AppKit)
                self.image = NSImage(data: data)
                #endif
            }
        }.resume()
    }
}

// MARK: - ContentUnavailableView Compatibility

/// ContentUnavailableView compatibility for iOS 16 and below
public struct ContentUnavailableViewCompat: View {
    let title: String
    let systemImage: String
    let description: String?
    
    public init(
        _ title: String,
        systemImage: String,
        description: String? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }
    
    public var body: some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                if let description = description {
                    Text(description)
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
                
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if let description = description {
                    Text(description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding()
        }
    }
}

// MARK: - Searchable Compatibility

public extension View {
    /// Searchable modifier compatibility
    func searchableCompat(
        text: Binding<String>,
        prompt: String? = nil
    ) -> some View {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            return self.searchable(text: text, prompt: prompt ?? "Search")
        } else {
            return VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(prompt ?? "Search", text: text)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding()
                
                self
            }
        }
    }
    
    /// Refreshable modifier compatibility
    func refreshableCompat(action: @escaping () async -> Void) -> some View {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            return self.refreshable {
                await action()
            }
        } else {
            return self
        }
    }
    
    /// Task modifier compatibility
    func taskCompat(priority: TaskPriority = .userInitiated, _ action: @escaping () async -> Void) -> some View {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            return self.task(priority: priority) {
                await action()
            }
        } else {
            return self.onAppear {
                Task(priority: priority) {
                    await action()
                }
            }
        }
    }
    
    /// Confirmation dialog compatibility
    func confirmationDialogCompat<A>(
        _ title: String,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        actions: () -> A
    ) -> some View where A: View {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            return self.confirmationDialog(
                title,
                isPresented: isPresented,
                titleVisibility: titleVisibility,
                actions: actions
            )
        } else {
            return self.actionSheet(isPresented: isPresented) {
                ActionSheet(title: Text(title))
            }
        }
    }
}