import SwiftUI
import CoreData
import SwiftData
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
import Archery

// MARK: - Interop Example App

struct InteropExampleApp: App {
    @StateObject private var dataManager = InteropDataManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataManager)
                .environment(\.dataCoexistence, DataCoexistenceManager.shared)
                .task {
                    await dataManager.setup()
                }
        }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HostingDemoView()
                .tabItem {
                    Label("Hosting", systemImage: "square.stack.3d.up")
                }
                .tag(0)
            
            ShareActivityDemoView()
                .tabItem {
                    Label("Sharing", systemImage: "square.and.arrow.up")
                }
                .tag(1)
            
            DataCoexistenceDemoView()
                .tabItem {
                    Label("Data", systemImage: "cylinder.split.1x2")
                }
                .tag(2)
        }
    }
}

// MARK: - Hosting Demo View

struct HostingDemoView: View {
    @State private var showUIKitView = false
    @State private var embeddedText = "Hello from SwiftUI!"
    
    var body: some View {
        NavigationView {
            List {
                Section("SwiftUI in UIKit/AppKit") {
                    Button("Show UIKit View Controller") {
                        showUIKitView = true
                    }
                    
                    #if canImport(UIKit)
                    NavigationLink("UIKit Table View with SwiftUI Cells") {
                        UIKitTableViewWithSwiftUICells()
                    }
                    #endif
                }
                
                Section("UIKit/AppKit in SwiftUI") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Native Text Field:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        #if canImport(UIKit)
                        UIKitViewRepresentable(
                            makeView: {
                                let textField = UITextField()
                                textField.placeholder = "Enter text here"
                                textField.borderStyle = .roundedRect
                                return textField
                            },
                            updateView: nil
                        )
                        .frame(height: 40)
                        #elseif canImport(AppKit)
                        AppKitViewRepresentable(
                            makeView: {
                                let textField = NSTextField()
                                textField.placeholderString = "Enter text here"
                                return textField
                            },
                            updateView: nil
                        )
                        .frame(height: 40)
                        #endif
                    }
                    .padding(.vertical, 5)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Native Progress Bar:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        #if canImport(UIKit)
                        UIKitViewRepresentable(
                            makeView: {
                                let progress = UIProgressView(progressViewStyle: .default)
                                progress.progress = 0.7
                                return progress
                            },
                            updateView: nil
                        )
                        .frame(height: 20)
                        #endif
                    }
                    .padding(.vertical, 5)
                }
                
                Section("Mixed Content") {
                    MixedContentView()
                }
            }
            .navigationTitle("UI Interop")
            .sheet(isPresented: $showUIKitView) {
                #if canImport(UIKit)
                UIKitViewControllerWrapper()
                #else
                Text("UIKit not available on this platform")
                #endif
            }
        }
    }
}

// MARK: - Share Activity Demo

struct ShareActivityDemoView: View {
    @State private var showShareSheet = false
    @State private var showDocumentPicker = false
    @State private var showImagePicker = false
    @State private var selectedDocuments: [URL] = []
    @State private var selectedImage: PlatformImage?
    @State private var shareMessage = "Check out this amazing app built with Archery!"
    
    var body: some View {
        NavigationView {
            List {
                Section("Share Sheet") {
                    Button("Share Text") {
                        showShareSheet = true
                    }
                    
                    ShareLink(
                        items: [shareMessage],
                        subject: "Archery Framework",
                        message: shareMessage
                    ) {
                        Label("Share with ShareLink", systemImage: "square.and.arrow.up")
                    }
                }
                
                Section("Document Picker") {
                    Button("Pick Documents") {
                        showDocumentPicker = true
                    }
                    
                    if !selectedDocuments.isEmpty {
                        ForEach(selectedDocuments, id: \.self) { url in
                            HStack {
                                Image(systemName: "doc.fill")
                                Text(url.lastPathComponent)
                                    .font(.caption)
                            }
                        }
                    }
                }
                
                Section("Image Picker") {
                    Button("Pick from Photo Library") {
                        showImagePicker = true
                    }
                    
                    if let image = selectedImage {
                        #if canImport(UIKit)
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                        #elseif canImport(AppKit)
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                        #endif
                    }
                }
            }
            .navigationTitle("Share & Pickers")
            .shareSheet(
                isPresented: $showShareSheet,
                items: [shareMessage, URL(string: "https://archery.example.com")!],
                excludedActivityTypes: [.assignToContact, .saveToCameraRoll]
            )
            .documentPicker(
                isPresented: $showDocumentPicker,
                allowedContentTypes: [.pdf, .text, .image],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    selectedDocuments = urls
                case .failure(let error):
                    print("Document picker error: \(error)")
                }
            }
            .imagePicker(
                isPresented: $showImagePicker,
                sourceType: .photoLibrary,
                allowsEditing: true
            ) { result in
                switch result {
                case .success(let image):
                    selectedImage = image
                case .failure(let error):
                    print("Image picker error: \(error)")
                }
            }
        }
    }
}

// MARK: - Data Coexistence Demo

struct DataCoexistenceDemoView: View {
    @EnvironmentObject var dataManager: InteropDataManager
    @State private var showMigration = false
    @State private var migrationResult: MigrationResult?
    
    var body: some View {
        NavigationView {
            List {
                Section("Data Sources") {
                    HStack {
                        Text("SwiftData")
                        Spacer()
                        Text(dataManager.swiftDataCount > 0 ? "\(dataManager.swiftDataCount) items" : "Not configured")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Core Data")
                        Spacer()
                        Text(dataManager.coreDataCount > 0 ? "\(dataManager.coreDataCount) items" : "Not configured")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Migration") {
                    Button("Migrate Core Data → SwiftData") {
                        Task {
                            migrationResult = await dataManager.migrateCoreDataToSwiftData()
                        }
                    }
                    
                    Button("Migrate SwiftData → Core Data") {
                        Task {
                            migrationResult = await dataManager.migrateSwiftDataToCoreData()
                        }
                    }
                    
                    if let result = migrationResult {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(result.summary)
                                .font(.caption)
                                .foregroundColor(result.success ? .green : .orange)
                        }
                        .padding(.vertical, 5)
                    }
                }
                
                Section("Dual Persistence") {
                    DualPersistenceExampleView()
                }
            }
            .navigationTitle("Data Coexistence")
        }
    }
}

// MARK: - Supporting Views

struct MixedContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This view mixes SwiftUI and native components")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Image(systemName: "swift")
                    .foregroundColor(.orange)
                    .font(.title)
                
                Spacer()
                
                #if canImport(UIKit)
                UIKitViewRepresentable(
                    makeView: {
                        let sw = UISwitch()
                        sw.isOn = true
                        return sw
                    },
                    updateView: nil
                )
                .fixedSize()
                #endif
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct DualPersistenceExampleView: View {
    @DualPersisted var items: [ExampleDualModel]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Items stored in both SwiftData and Core Data:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if items.isEmpty {
                Text("No items")
                    .italic()
                    .foregroundColor(.secondary)
            } else {
                ForEach(items, id: \.id) { item in
                    Text(item.name)
                }
            }
        }
    }
}

// MARK: - UIKit Integration

#if canImport(UIKit)

struct UIKitViewControllerWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = ExampleUIViewController()
        return UINavigationController(rootViewController: viewController)
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No updates needed
    }
}

class ExampleUIViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "UIKit View Controller"
        view.backgroundColor = .systemBackground
        
        // Add SwiftUI view to UIKit
        let swiftUIView = SwiftUIContentView()
        let hostingController = UIHostingController(rootView: swiftUIView)
        
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
        
        // Setup constraints
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            hostingController.view.heightAnchor.constraint(equalToConstant: 200)
        ])
        
        // Add native UIKit button
        let button = UIButton(type: .system)
        button.setTitle("Native UIKit Button", for: .normal)
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        
        view.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: hostingController.view.bottomAnchor, constant: 20),
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }
    
    @objc private func buttonTapped() {
        let alert = UIAlertController(
            title: "UIKit Alert",
            message: "This is a native UIKit alert",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

struct SwiftUIContentView: View {
    var body: some View {
        VStack {
            Text("SwiftUI View in UIKit")
                .font(.title2)
                .bold()
            
            Text("This SwiftUI view is embedded in a UIViewController")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(10)
    }
}

struct UIKitTableViewWithSwiftUICells: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UITableViewController {
        SwiftUITableViewController()
    }
    
    func updateUIViewController(_ uiViewController: UITableViewController, context: Context) {
        // No updates needed
    }
}

class SwiftUITableViewController: UITableViewController {
    let items = (1...20).map { "Item \($0)" }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "UIKit Table with SwiftUI"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        
        // Use SwiftUI for cell content
        let swiftUIView = HStack {
            Image(systemName: "star.fill")
                .foregroundColor(.yellow)
            Text(items[indexPath.row])
            Spacer()
            Text("#\(indexPath.row + 1)")
                .foregroundColor(.secondary)
        }
        .padding()
        
        let hostingController = UIHostingController(rootView: swiftUIView)
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        cell.contentView.addSubview(hostingController.view)
        
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor)
        ])
        
        return cell
    }
}

#endif

// MARK: - Data Manager

@MainActor
class InteropDataManager: ObservableObject {
    @Published var swiftDataCount = 0
    @Published var coreDataCount = 0
    
    func setup() async {
        // Setup would initialize real data stores
        swiftDataCount = 5
        coreDataCount = 3
    }
    
    func migrateCoreDataToSwiftData() async -> MigrationResult {
        // Simulate migration
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return MigrationResult(
            itemsMigrated: 3,
            itemsFailed: 0,
            errors: [],
            duration: 1.0
        )
    }
    
    func migrateSwiftDataToCoreData() async -> MigrationResult {
        // Simulate migration
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return MigrationResult(
            itemsMigrated: 5,
            itemsFailed: 0,
            errors: [],
            duration: 1.5
        )
    }
}

// MARK: - Example Models

struct ExampleDualModel: DualPersistable, Identifiable {
    typealias SwiftDataModel = ExampleSwiftDataModel
    typealias CoreDataModel = NSManagedObject
    
    let id: UUID
    let name: String
    
    func toSwiftData() -> ExampleSwiftDataModel {
        ExampleSwiftDataModel(name: name)
    }
    
    func toCoreData(context: NSManagedObjectContext) -> NSManagedObject {
        NSManagedObject()
    }
    
    static func fromSwiftData(_ model: ExampleSwiftDataModel) -> ExampleDualModel {
        ExampleDualModel(id: model.id, name: model.name)
    }
    
    static func fromCoreData(_ object: NSManagedObject) -> ExampleDualModel {
        ExampleDualModel(id: UUID(), name: "Core Data Item")
    }
}

@Model
final class ExampleSwiftDataModel {
    var id: UUID = UUID()
    var name: String
    
    init(name: String) {
        self.name = name
    }
}

// MARK: - Previews

struct InteropExample_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(InteropDataManager())
    }
}