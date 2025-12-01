import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#elseif os(watchOS)
import WatchKit
#endif

// MARK: - Platform-Specific Examples

/// Demonstrates how Archery adapts to different Apple platforms
/// while maintaining consistent architecture patterns

// MARK: - iOS Specific Features

#if os(iOS)
struct iOSExampleView: View {
    @StateObject private var viewModel = iOSTaskViewModel()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // iOS-specific UI components
                iOSTaskListView()
                
                // iPad-specific split view on larger screens
                if UIDevice.current.userInterfaceIdiom == .pad {
                    iPadSplitView()
                        .frame(height: 400)
                }
                
                // iPhone-specific compact layout
                if UIDevice.current.userInterfaceIdiom == .phone {
                    iPhoneCompactControls()
                }
                
                Spacer()
            }
            .navigationTitle("iOS Features")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // iOS-specific toolbar items
                    Button("Share") {
                        viewModel.shareContent()
                    }
                    
                    Button("Settings") {
                        viewModel.showSettings()
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingShare) {
                iOSShareSheet(items: viewModel.shareItems)
            }
        }
        .onAppear {
            setupiOSSpecificFeatures()
        }
    }
    
    private func setupiOSSpecificFeatures() {
        // Register for push notifications (iOS-specific)
        Task {
            await viewModel.registerForNotifications()
        }
        
        // Setup haptic feedback
        viewModel.setupHapticFeedback()
        
        // Configure appearance for iOS
        configureiOSAppearance()
    }
    
    private func configureiOSAppearance() {
        // iOS-specific appearance customization
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemBlue
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}

struct iOSTaskListView: View {
    @State private var tasks: [Task] = []
    
    var body: some View {
        List {
            ForEach(tasks) { task in
                iOSTaskRow(task: task)
                    .swipeActions(edge: .trailing) {
                        Button("Delete") {
                            deleteTask(task)
                        }
                        .tint(.red)
                        
                        Button("Archive") {
                            archiveTask(task)
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .leading) {
                        Button("Complete") {
                            completeTask(task)
                        }
                        .tint(.green)
                    }
            }
        }
        .refreshable {
            await refreshTasks()
        }
        .searchable(text: .constant(""))
    }
    
    private func deleteTask(_ task: Task) {
        // iOS-specific haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        withAnimation(.spring()) {
            tasks.removeAll { $0.id == task.id }
        }
    }
    
    private func completeTask(_ task: Task) {
        // iOS-specific success haptic
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
    }
    
    private func archiveTask(_ task: Task) {
        // iOS-specific selection haptic
        let selectionFeedback = UISelectionFeedbackGenerator()
        selectionFeedback.selectionChanged()
    }
    
    private func refreshTasks() async {
        // Simulate refresh with iOS-specific loading
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }
}

struct iOSTaskRow: View {
    let task: Task
    
    var body: some View {
        HStack {
            // iOS-specific task row design
            RoundedRectangle(cornerRadius: 8)
                .fill(task.priority.color)
                .frame(width: 4)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.headline)
                
                Text(task.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    Label(task.priority.displayName, systemImage: task.priority.icon)
                        .font(.caption)
                        .foregroundColor(task.priority.color)
                    
                    Spacer()
                    
                    Text(task.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // iOS-specific chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}

struct iPadSplitView: View {
    @State private var selectedTask: Task?
    @State private var tasks: [Task] = sampleTasks
    
    var body: some View {
        HSplitView {
            // Master pane
            List(tasks, selection: $selectedTask) { task in
                iPadTaskRow(task: task)
            }
            .frame(minWidth: 300)
            
            // Detail pane
            if let selectedTask = selectedTask {
                iPadTaskDetailView(task: selectedTask)
                    .frame(minWidth: 400)
            } else {
                iPadEmptyDetailView()
            }
        }
    }
}

struct iPadTaskRow: View {
    let task: Task
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(.headline)
            
            Text(task.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            HStack {
                Label(task.priority.displayName, systemImage: task.priority.icon)
                    .font(.caption)
                    .foregroundColor(task.priority.color)
                
                Spacer()
                
                Text(task.createdAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct iPadTaskDetailView: View {
    let task: Task
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(task.title)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(task.description)
                .font(.body)
            
            Spacer()
        }
        .padding()
        .navigationTitle(task.title)
    }
}

struct iPadEmptyDetailView: View {
    var body: some View {
        VStack {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("Select a task to view details")
                .font(.title2)
                .foregroundColor(.secondary)
        }
    }
}

struct iPhoneCompactControls: View {
    var body: some View {
        HStack(spacing: 16) {
            Button("Add Task") {
                // iPhone-specific compact action
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
            
            Button("Filter") {
                // iPhone-specific filter action
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(12)
        }
        .padding(.horizontal)
    }
}

struct iOSShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

@MainActor
class iOSTaskViewModel: ObservableObject {
    @Published var showingShare = false
    @Published var shareItems: [Any] = []
    
    func shareContent() {
        shareItems = ["Check out my tasks!"]
        showingShare = true
    }
    
    func showSettings() {
        // iOS-specific settings presentation
    }
    
    func registerForNotifications() async {
        // iOS-specific notification registration
        let center = UNUserNotificationCenter.current()
        try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }
    
    func setupHapticFeedback() {
        // iOS-specific haptic feedback setup
    }
}

#endif

// MARK: - macOS Specific Features

#if os(macOS)
struct macOSExampleView: View {
    @StateObject private var viewModel = macOSTaskViewModel()
    
    var body: some View {
        NavigationView {
            // macOS-specific sidebar
            macOSSidebar()
                .frame(minWidth: 200)
            
            // Main content area
            macOSMainContent()
                .frame(minWidth: 600)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.left")
                }
            }
            
            ToolbarItemGroup(placement: .primaryAction) {
                macOSToolbarControls()
            }
        }
        .onAppear {
            setupmacOSSpecificFeatures()
        }
    }
    
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
    
    private func setupmacOSSpecificFeatures() {
        // Setup macOS-specific menu items
        setupMenuItems()
        
        // Configure macOS appearance
        configuremacOSAppearance()
        
        // Setup keyboard shortcuts
        setupKeyboardShortcuts()
    }
    
    private func setupMenuItems() {
        // macOS-specific menu item configuration
        let menu = NSApplication.shared.mainMenu
        // Add custom menu items
    }
    
    private func configuremacOSAppearance() {
        // macOS-specific appearance settings
        NSApp.appearance = NSAppearance(named: .aqua)
    }
    
    private func setupKeyboardShortcuts() {
        // macOS-specific keyboard shortcuts
    }
}

struct macOSSidebar: View {
    @State private var selectedCategory: TaskCategory = .all
    
    enum TaskCategory: String, CaseIterable {
        case all = "All Tasks"
        case today = "Today"
        case upcoming = "Upcoming"
        case completed = "Completed"
        
        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .today: return "calendar"
            case .upcoming: return "clock"
            case .completed: return "checkmark.circle"
            }
        }
    }
    
    var body: some View {
        List(TaskCategory.allCases, id: \.self, selection: $selectedCategory) { category in
            Label(category.rawValue, systemImage: category.icon)
                .tag(category)
        }
        .listStyle(SidebarListStyle())
        .navigationTitle("Tasks")
    }
}

struct macOSMainContent: View {
    @State private var tasks: [Task] = sampleTasks
    @State private var selectedTask: Task?
    
    var body: some View {
        HSplitView {
            // Task list
            List(tasks, selection: $selectedTask) { task in
                macOSTaskRow(task: task)
            }
            .frame(minWidth: 300)
            
            // Task detail
            if let selectedTask = selectedTask {
                macOSTaskDetailView(task: selectedTask)
                    .frame(minWidth: 400)
            } else {
                macOSEmptyDetailView()
            }
        }
    }
}

struct macOSTaskRow: View {
    let task: Task
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(task.title)
                    .font(.headline)
                
                Spacer()
                
                Text(task.createdAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(task.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            HStack {
                Label(task.priority.displayName, systemImage: task.priority.icon)
                    .font(.caption)
                    .foregroundColor(task.priority.color)
                
                Spacer()
            }
        }
        .padding(.vertical, 8)
        .contextMenu {
            macOSContextMenu(for: task)
        }
    }
}

@ViewBuilder
func macOSContextMenu(for task: Task) -> some View {
    Button("Edit") {
        // Edit task
    }
    
    Button("Duplicate") {
        // Duplicate task
    }
    
    Divider()
    
    Button("Delete") {
        // Delete task
    }
}

struct macOSTaskDetailView: View {
    let task: Task
    @State private var isEditing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(task.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Edit") {
                    isEditing = true
                }
                .buttonStyle(.bordered)
            }
            
            ScrollView {
                Text(task.description)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer()
        }
        .padding()
        .sheet(isPresented: $isEditing) {
            macOSTaskEditView(task: task)
        }
    }
}

struct macOSTaskEditView: View {
    let task: Task
    @Environment(\.dismiss) var dismiss
    @State private var title: String = ""
    @State private var description: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Task")
                .font(.title)
            
            Form {
                TextField("Title", text: $title)
                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(3...6)
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    // Save changes
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
        .onAppear {
            title = task.title
            description = task.description
        }
    }
}

struct macOSEmptyDetailView: View {
    var body: some View {
        VStack {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("Select a task to view details")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Use ⌘+N to create a new task")
                .font(.caption)
                .foregroundColor(.tertiary)
        }
    }
}

struct macOSToolbarControls: View {
    var body: some View {
        HStack {
            Button(action: addTask) {
                Image(systemName: "plus")
            }
            .help("Add new task (⌘+N)")
            
            Button(action: deleteTask) {
                Image(systemName: "trash")
            }
            .help("Delete selected task (⌫)")
            
            Button(action: refreshTasks) {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh tasks (⌘+R)")
        }
    }
    
    private func addTask() {
        // Add new task
    }
    
    private func deleteTask() {
        // Delete selected task
    }
    
    private func refreshTasks() {
        // Refresh task list
    }
}

@MainActor
class macOSTaskViewModel: ObservableObject {
    @Published var tasks: [Task] = []
    @Published var selectedTask: Task?
    
    func setupMenuItems() {
        // Setup macOS-specific menu items
    }
}

#endif

// MARK: - watchOS Specific Features

#if os(watchOS)
struct watchOSExampleView: View {
    @StateObject private var viewModel = watchOSTaskViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.tasks.prefix(10)) { task in
                        watchOSTaskRow(task: task)
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            setupwatchOSSpecificFeatures()
        }
    }
    
    private func setupwatchOSSpecificFeatures() {
        // Setup watchOS-specific features
        setupDigitalCrown()
        setupHapticFeedback()
        setupComplications()
    }
    
    private func setupDigitalCrown() {
        // Digital Crown integration
    }
    
    private func setupHapticFeedback() {
        // watchOS-specific haptic feedback
    }
    
    private func setupComplications() {
        // Complication data source setup
    }
}

struct watchOSTaskRow: View {
    let task: Task
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(task.priority.color)
                    .frame(width: 8, height: 8)
                
                Text(task.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
            }
            
            Text(task.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .onTapGesture {
            // watchOS-specific task interaction
            triggerHapticFeedback()
        }
    }
    
    private func triggerHapticFeedback() {
        WKInterfaceDevice.current().play(.click)
    }
}

struct watchOSTaskDetailView: View {
    let task: Task
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(task.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                
                Text(task.description)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                
                HStack {
                    Label(task.priority.displayName, systemImage: task.priority.icon)
                        .font(.caption)
                        .foregroundColor(task.priority.color)
                    
                    Spacer()
                }
                
                Button("Complete") {
                    // Complete task action
                    WKInterfaceDevice.current().play(.success)
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle(task.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
class watchOSTaskViewModel: ObservableObject {
    @Published var tasks: [Task] = sampleTasks.prefix(5).map { $0 }
    
    func setupDigitalCrown() {
        // Digital Crown configuration
    }
    
    func setupComplications() {
        // Complication setup
    }
}

#endif

// MARK: - tvOS Specific Features

#if os(tvOS)
struct tvOSExampleView: View {
    @StateObject private var viewModel = tvOSTaskViewModel()
    @FocusState private var focusedTask: UUID?
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3), spacing: 20) {
                    ForEach(viewModel.tasks) { task in
                        tvOSTaskCard(task: task)
                            .focused($focusedTask, equals: task.id)
                    }
                }
                .padding(40)
            }
            .navigationTitle("Task Dashboard")
        }
        .onAppear {
            setuptvOSSpecificFeatures()
        }
    }
    
    private func setuptvOSSpecificFeatures() {
        // Setup tvOS-specific features
        setupRemoteControl()
        setupFocusGuides()
    }
    
    private func setupRemoteControl() {
        // Apple TV Remote integration
    }
    
    private func setupFocusGuides() {
        // tvOS focus guide setup
    }
}

struct tvOSTaskCard: View {
    let task: Task
    @Environment(\.isFocused) var isFocused
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Circle()
                    .fill(task.priority.color)
                    .frame(width: 12, height: 12)
                
                Text(task.priority.displayName)
                    .font(.caption)
                    .foregroundColor(task.priority.color)
                
                Spacer()
            }
            
            Text(task.title)
                .font(.title2)
                .fontWeight(.semibold)
                .lineLimit(2)
            
            Text(task.description)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(3)
            
            Spacer()
            
            Text(task.createdAt, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(height: 280)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(isFocused ? 0.3 : 0.1))
        )
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

@MainActor
class tvOSTaskViewModel: ObservableObject {
    @Published var tasks: [Task] = sampleTasks
    
    func setupRemoteControl() {
        // Apple TV Remote configuration
    }
}

#endif

// MARK: - Shared Sample Data

let sampleTasks = [
    Task(title: "Design new login screen", description: "Create wireframes and mockups for the new login experience", priority: .high),
    Task(title: "Implement OAuth integration", description: "Add support for Google and Apple sign-in", priority: .medium),
    Task(title: "Write unit tests", description: "Increase test coverage to 90%", priority: .medium),
    Task(title: "Update documentation", description: "Document new API endpoints", priority: .low),
    Task(title: "Fix critical bug", description: "App crashes on iPhone 12 Pro Max", priority: .urgent),
    Task(title: "Optimize performance", description: "Improve app startup time", priority: .high),
    Task(title: "Add accessibility features", description: "Implement VoiceOver support", priority: .medium),
    Task(title: "Localize app", description: "Add support for Spanish and French", priority: .low)
]

// MARK: - Platform Detection Helpers

struct PlatformInfo {
    static var isPhone: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }
    
    static var isPad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }
    
    static var isMac: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }
    
    static var isWatch: Bool {
        #if os(watchOS)
        return true
        #else
        return false
        #endif
    }
    
    static var isTV: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }
    
    static var platformName: String {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(watchOS)
        return "watchOS"
        #elseif os(tvOS)
        return "tvOS"
        #else
        return "Unknown"
        #endif
    }
}

// MARK: - Cross-Platform Example

struct CrossPlatformView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Running on \(PlatformInfo.platformName)")
                .font(.title)
            
            #if os(iOS)
            if PlatformInfo.isPad {
                iOSExampleView()
            } else {
                iOSExampleView()
            }
            #elseif os(macOS)
            macOSExampleView()
            #elseif os(watchOS)
            watchOSExampleView()
            #elseif os(tvOS)
            tvOSExampleView()
            #endif
        }
    }
}