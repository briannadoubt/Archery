import SwiftUI
@testable import Archery

// MARK: - Example App

@main
struct E2ETestingExampleApp: App {
    @StateObject private var navigator = NavigationCoordinator()
    @StateObject private var networkManager = NetworkManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(navigator)
                .environmentObject(networkManager)
                .onAppear {
                    setupE2ETesting()
                }
        }
    }
    
    private func setupE2ETesting() {
        // Setup record/replay for deterministic networking
        Task {
            await networkManager.setupRecordReplay(mode: .replay)
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var navigator: NavigationCoordinator
    @State private var showingTestResults = false
    @State private var testReport: String = ""
    
    var body: some View {
        NavigationStack(path: $navigator.path) {
            VStack(spacing: 20) {
                Text("E2E Testing Example")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                VStack(alignment: .leading, spacing: 16) {
                    TestButton(
                        title: "Run UI Tests",
                        systemImage: "play.circle.fill",
                        color: .blue
                    ) {
                        await runUITests()
                    }
                    
                    TestButton(
                        title: "Run Navigation Fuzzing",
                        systemImage: "shuffle.circle.fill",
                        color: .purple
                    ) {
                        await runNavigationFuzzing()
                    }
                    
                    TestButton(
                        title: "Run Property Tests",
                        systemImage: "checkmark.circle.fill",
                        color: .green
                    ) {
                        runPropertyTests()
                    }
                    
                    TestButton(
                        title: "Test Record/Replay",
                        systemImage: "arrow.triangle.2.circlepath.circle.fill",
                        color: .orange
                    ) {
                        await testRecordReplay()
                    }
                    
                    TestButton(
                        title: "Show Deterministic Previews",
                        systemImage: "eye.circle.fill",
                        color: .pink
                    ) {
                        navigator.navigate(to: .previews)
                    }
                }
                .padding()
                
                Spacer()
            }
            .padding()
            .navigationDestination(for: NavigationDestination.self) { destination in
                destinationView(for: destination)
            }
            .sheet(isPresented: $showingTestResults) {
                TestResultsView(report: testReport)
            }
        }
    }
    
    @ViewBuilder
    private func destinationView(for destination: NavigationDestination) -> some View {
        switch destination {
        case .home:
            HomeView()
        case .profile:
            ProfileView()
        case .settings:
            SettingsView()
        case .previews:
            DeterministicPreviewsView()
        }
    }
    
    // MARK: - Test Actions
    
    private func runUITests() async {
        let runner = UITestRunner()
        let report = await runner.runCriticalFlows()
        
        testReport = report.generateMarkdown()
        showingTestResults = true
    }
    
    private func runNavigationFuzzing() async {
        // Build navigation graph from app structure
        let routes = [
            Route(from: "root", to: "home", action: .tap("Home")),
            Route(from: "home", to: "profile", action: .tap("Profile")),
            Route(from: "home", to: "settings", action: .tap("Settings")),
            Route(from: "profile", to: "home", action: .back),
            Route(from: "settings", to: "home", action: .back)
        ]
        
        let graph = NavigationGraphBuilder.buildFromRoutes(routes)
        let fuzzer = NavigationFuzzer(
            graph: graph,
            maxDepth: 5,
            maxIterations: 50,
            seed: 12345
        )
        
        let report = await fuzzer.fuzz()
        testReport = report.summary
        showingTestResults = true
    }
    
    private func runPropertyTests() {
        // Test load state machine
        let stateMachine: StateMachine<LoadState<String>, LoadAction> = loadStateMachine()
        
        let properties = [
            LoadStateProperties.validTransitions(),
            LoadStateProperties.noDoubleLoading()
        ]
        
        let generators = [
            Generator<LoadAction>.oneOf([.startLoading, .reset]),
            Generator<LoadAction> { _ in .succeed("test") },
            Generator<LoadAction> { _ in .fail(TestError.example) }
        ]
        
        let tester = PropertyBasedTester(
            stateMachine: stateMachine,
            properties: properties,
            generators: generators
        )
        
        let report = tester.test(iterations: 100, seed: 12345)
        testReport = report.summary
        showingTestResults = true
    }
    
    private func testRecordReplay() async {
        do {
            let storage = MemoryRecordingStorage()
            let harness = RecordReplayHarness(mode: .record, storage: storage)
            
            // Record a request
            let request = URLRequest(url: URL(string: "https://api.example.com/test")!)
            
            // Create mock response for demo
            let mockData = """
            {"status": "success", "message": "Record/Replay working!"}
            """.data(using: .utf8)!
            
            let recording = Recording(
                request: request,
                response: HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                data: mockData,
                timestamp: Date()
            )
            
            try await storage.save(["test": recording])
            
            // Now replay
            let replayHarness = RecordReplayHarness(mode: .replay, storage: storage)
            try await replayHarness.loadRecordings()
            
            let (data, response) = try await replayHarness.execute(request)
            
            testReport = """
            Record/Replay Test Results
            ==========================
            
            ✅ Successfully recorded and replayed request
            
            Response Status: \((response as? HTTPURLResponse)?.statusCode ?? 0)
            Data: \(String(data: data, encoding: .utf8) ?? "N/A")
            """
            
            showingTestResults = true
            
        } catch {
            testReport = "❌ Record/Replay test failed: \(error)"
            showingTestResults = true
        }
    }
}

// MARK: - Test Button

struct TestButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () async -> Void
    
    @State private var isRunning = false
    
    var body: some View {
        Button(action: {
            Task {
                isRunning = true
                await action()
                isRunning = false
            }
        }) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(color)
                
                Text(title)
                    .font(.headline)
                
                Spacer()
                
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(color.opacity(0.1))
            .cornerRadius(12)
        }
        .disabled(isRunning)
        .buttonStyle(.plain)
    }
}

// MARK: - Test Results View

struct TestResultsView: View {
    let report: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(report)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Test Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Deterministic Previews View

struct DeterministicPreviewsView: View {
    var body: some View {
        List {
            Section("Fixed Data") {
                LabeledContent("Date", value: DeterministicPreviewData.previewDate.formatted())
                LabeledContent("UUID", value: DeterministicPreviewData.previewUUID.uuidString)
                LabeledContent("Seed", value: "\(DeterministicPreviewData.previewSeed)")
            }
            
            Section("Generated Users") {
                ForEach(0..<5) { i in
                    let user = DeterministicPreviewData.previewUser(id: i)
                    HStack {
                        AsyncImage(url: user.avatarURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        
                        VStack(alignment: .leading) {
                            Text(user.name)
                                .font(.headline)
                            Text(user.email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
            }
            
            Section("Generated Text") {
                Text(DeterministicPreviewData.previewText(wordCount: 30))
                    .font(.body)
            }
            
            Section("Generated List") {
                let items = DeterministicPreviewData.previewList(count: 10) { i in
                    "Item \(i + 1)"
                }
                
                ForEach(items, id: \.self) { item in
                    Text(item)
                }
            }
        }
        .navigationTitle("Deterministic Previews")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sample Views

struct HomeView: View {
    var body: some View {
        VStack {
            Text("Home Screen")
                .font(.largeTitle)
            
            List(0..<10) { i in
                NavigationLink("Item \(i + 1)", value: NavigationDestination.profile)
            }
        }
        .navigationTitle("Home")
    }
}

struct ProfileView: View {
    let user = DeterministicPreviewData.previewUser()
    
    var body: some View {
        VStack(spacing: 20) {
            AsyncImage(url: user.avatarURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.2))
            }
            .frame(width: 100, height: 100)
            .clipShape(Circle())
            
            Text(user.name)
                .font(.title)
            
            Text(user.email)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .navigationTitle("Profile")
    }
}

struct SettingsView: View {
    @State private var enableNotifications = true
    @State private var enableAnalytics = false
    
    var body: some View {
        Form {
            Section("Preferences") {
                Toggle("Enable Notifications", isOn: $enableNotifications)
                Toggle("Enable Analytics", isOn: $enableAnalytics)
            }
            
            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Build", value: "100")
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Navigation

enum NavigationDestination: Hashable {
    case home
    case profile
    case settings
    case previews
}

class NavigationCoordinator: ObservableObject {
    @Published var path = NavigationPath()
    
    func navigate(to destination: NavigationDestination) {
        path.append(destination)
    }
    
    func pop() {
        if !path.isEmpty {
            path.removeLast()
        }
    }
    
    func popToRoot() {
        path = NavigationPath()
    }
}

// MARK: - Network Manager

class NetworkManager: ObservableObject {
    private var harness: RecordReplayHarness?
    
    func setupRecordReplay(mode: RecordReplayHarness.Mode) async {
        let storage = FileRecordingStorage()
        harness = RecordReplayHarness(mode: mode, storage: storage)
        
        if mode == .replay {
            try? await harness?.loadRecordings()
        }
    }
    
    func executeRequest(_ request: URLRequest) async throws -> Data {
        guard let harness = harness else {
            throw TestError.notSetup
        }
        
        let (data, _) = try await harness.execute(request)
        return data
    }
}

// MARK: - Test Error

enum TestError: Error {
    case example
    case notSetup
}

// MARK: - Previews

#Preview("Main View") {
    ContentView()
        .environmentObject(NavigationCoordinator())
        .environmentObject(NetworkManager())
}

#Preview("Deterministic Data") {
    NavigationStack {
        DeterministicPreviewsView()
    }
}

#Preview("Test Results") {
    TestResultsView(report: """
    Test Report Example
    ===================
    
    ✅ All tests passed
    Total: 10
    Passed: 10
    Failed: 0
    """)
}