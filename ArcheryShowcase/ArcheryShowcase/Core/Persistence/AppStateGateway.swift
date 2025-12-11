import Foundation
import SwiftUI
import Archery

// MARK: - @PersistenceGateway Demo
//
// The @PersistenceGateway macro generates:
// - keyName computed property for each case
// - Gateway struct with typed getters/setters
// - SQLite-backed storage with migrations and seeding

@PersistenceGateway
enum AppState {
    case userPreferences(UserPreferences)
    case onboardingProgress(OnboardingProgress)
    case draftTask(DraftTask)
    case recentSearches([String])
    case lastSyncTimestamp(Date)
}

// MARK: - Codable Types

struct UserPreferences: Codable, Equatable, Sendable {
    var theme: Theme = .system
    var accentColor: AccentColor = .blue
    var notificationsEnabled: Bool = true
    var compactMode: Bool = false
    var hapticFeedback: Bool = true

    enum Theme: String, Codable, CaseIterable, Sendable {
        case system, light, dark

        var displayName: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }

    enum AccentColor: String, Codable, CaseIterable, Sendable {
        case blue, purple, green, orange, pink

        var color: Color {
            switch self {
            case .blue: return .blue
            case .purple: return .purple
            case .green: return .green
            case .orange: return .orange
            case .pink: return .pink
            }
        }
    }
}

struct OnboardingProgress: Codable, Equatable, Sendable {
    var completedSteps: Set<String> = []
    var skippedSteps: Set<String> = []
    var startedAt: Date?
    var completedAt: Date?

    var isComplete: Bool {
        completedAt != nil
    }
}

struct DraftTask: Codable, Equatable, Sendable {
    var title: String = ""
    var description: String = ""
    var priority: String = "medium"
    var dueDate: Date?
    var tags: [String] = []
    var lastModified: Date = Date()

    var isEmpty: Bool {
        title.isEmpty && description.isEmpty && tags.isEmpty
    }
}

// MARK: - Persistence Gateway Showcase View

@MainActor
struct PersistenceGatewayShowcaseView: View {
    @State private var gateway: AppState.Gateway?
    @State private var preferences = UserPreferences()
    @State private var onboarding = OnboardingProgress()
    @State private var draftTask = DraftTask()
    @State private var recentSearches: [String] = []
    @State private var lastSync: Date?

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var error: Error?
    @State private var statusMessage: String?
    @State private var newSearch = ""

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("@PersistenceGateway")
                        .font(.headline)
                    Text("SQLite-backed typed key-value storage with auto-generated getters/setters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading from SQLite...")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let error {
                Section {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Button("Retry") {
                        Task { await initialize() }
                    }
                }
            } else {
                preferencesSection
                onboardingSection
                draftTaskSection
                recentSearchesSection
                syncSection
                actionsSection
            }
        }
        .navigationTitle("Persistence Gateway")
        .task {
            await initialize()
        }
        .overlay {
            if let message = statusMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.caption)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 20)
                }
                .animation(.easeInOut, value: statusMessage)
            }
        }
    }

    // MARK: - Sections

    private var preferencesSection: some View {
        Section("User Preferences") {
            Picker("Theme", selection: $preferences.theme) {
                ForEach(UserPreferences.Theme.allCases, id: \.self) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .onChange(of: preferences.theme) { _, _ in savePreferences() }

            Picker("Accent Color", selection: $preferences.accentColor) {
                ForEach(UserPreferences.AccentColor.allCases, id: \.self) { color in
                    HStack {
                        Circle()
                            .fill(color.color)
                            .frame(width: 12, height: 12)
                        Text(color.rawValue.capitalized)
                    }
                    .tag(color)
                }
            }
            .onChange(of: preferences.accentColor) { _, _ in savePreferences() }

            Toggle("Notifications", isOn: $preferences.notificationsEnabled)
                .onChange(of: preferences.notificationsEnabled) { _, _ in savePreferences() }

            Toggle("Compact Mode", isOn: $preferences.compactMode)
                .onChange(of: preferences.compactMode) { _, _ in savePreferences() }

            Toggle("Haptic Feedback", isOn: $preferences.hapticFeedback)
                .onChange(of: preferences.hapticFeedback) { _, _ in savePreferences() }
        }
    }

    private var onboardingSection: some View {
        Section("Onboarding Progress") {
            LabeledContent("Started", value: onboarding.startedAt?.formatted() ?? "Not started")
            LabeledContent("Completed", value: onboarding.completedAt?.formatted() ?? "In progress")
            LabeledContent("Steps Done", value: "\(onboarding.completedSteps.count)")
            LabeledContent("Steps Skipped", value: "\(onboarding.skippedSteps.count)")

            Button("Simulate Step Completion") {
                onboarding.completedSteps.insert("step_\(onboarding.completedSteps.count + 1)")
                if onboarding.startedAt == nil {
                    onboarding.startedAt = Date()
                }
                saveOnboarding()
            }

            Button("Mark Complete") {
                onboarding.completedAt = Date()
                saveOnboarding()
            }
            .disabled(onboarding.isComplete)
        }
    }

    private var draftTaskSection: some View {
        Section("Draft Task (Auto-saved)") {
            TextField("Title", text: $draftTask.title)
                .onChange(of: draftTask.title) { _, _ in saveDraft() }

            TextField("Description", text: $draftTask.description, axis: .vertical)
                .lineLimit(3...6)
                .onChange(of: draftTask.description) { _, _ in saveDraft() }

            Picker("Priority", selection: $draftTask.priority) {
                Text("Low").tag("low")
                Text("Medium").tag("medium")
                Text("High").tag("high")
            }
            .onChange(of: draftTask.priority) { _, _ in saveDraft() }

            if !draftTask.isEmpty {
                LabeledContent("Last Modified", value: draftTask.lastModified.formatted())

                Button("Clear Draft", role: .destructive) {
                    draftTask = DraftTask()
                    saveDraft()
                }
            }
        }
    }

    private var recentSearchesSection: some View {
        Section("Recent Searches") {
            HStack {
                TextField("Add search...", text: $newSearch)
                    .textFieldStyle(.roundedBorder)

                Button("Add") {
                    guard !newSearch.isEmpty else { return }
                    recentSearches.insert(newSearch, at: 0)
                    if recentSearches.count > 10 {
                        recentSearches = Array(recentSearches.prefix(10))
                    }
                    newSearch = ""
                    saveSearches()
                }
                .disabled(newSearch.isEmpty)
            }

            if recentSearches.isEmpty {
                Text("No recent searches")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentSearches, id: \.self) { search in
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        Text(search)
                    }
                }
                .onDelete { indexSet in
                    recentSearches.remove(atOffsets: indexSet)
                    saveSearches()
                }
            }
        }
    }

    private var syncSection: some View {
        Section("Sync Status") {
            if let lastSync {
                LabeledContent("Last Sync", value: lastSync.formatted())
            } else {
                Text("Never synced")
                    .foregroundStyle(.secondary)
            }

            Button("Update Sync Timestamp") {
                lastSync = Date()
                Task {
                    try? await gateway?.setLastSyncTimestamp(Date())
                    showStatus("Sync timestamp updated")
                }
            }
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            Button("Reload All Data") {
                Task { await loadAllData() }
            }

            Button("Clear All Data", role: .destructive) {
                Task { await clearAllData() }
            }
        }
    }

    // MARK: - Data Operations

    private func initialize() async {
        isLoading = true
        error = nil

        do {
            // Create gateway with file-based storage
            let url = gatewayURL
            gateway = try AppState.Gateway(url: url)
            await loadAllData()
        } catch {
            self.error = error
        }

        isLoading = false
    }

    private var gatewayURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ArcheryShowcase")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("appstate.sqlite")
    }

    private func loadAllData() async {
        guard let gateway else { return }

        do {
            // Load all persisted values using typed getters
            if let prefs = try await gateway.userPreferences() {
                preferences = prefs
            }
            if let progress = try await gateway.onboardingProgress() {
                onboarding = progress
            }
            if let draft = try await gateway.draftTask() {
                draftTask = draft
            }
            if let searches = try await gateway.recentSearches() {
                recentSearches = searches
            }
            lastSync = try await gateway.lastSyncTimestamp()

            showStatus("Data loaded from SQLite")
        } catch {
            self.error = error
        }
    }

    private func savePreferences() {
        Task {
            try? await gateway?.setUserPreferences(preferences)
            showStatus("Preferences saved")
        }
    }

    private func saveOnboarding() {
        Task {
            try? await gateway?.setOnboardingProgress(onboarding)
            showStatus("Onboarding progress saved")
        }
    }

    private func saveDraft() {
        draftTask.lastModified = Date()
        Task {
            try? await gateway?.setDraftTask(draftTask)
            // Don't show status for auto-save to reduce noise
        }
    }

    private func saveSearches() {
        Task {
            try? await gateway?.setRecentSearches(recentSearches)
            showStatus("Searches saved")
        }
    }

    private func clearAllData() async {
        guard let gateway else { return }

        do {
            try await gateway.remove(.userPreferences(UserPreferences()))
            try await gateway.remove(.onboardingProgress(OnboardingProgress()))
            try await gateway.remove(.draftTask(DraftTask()))
            try await gateway.remove(.recentSearches([]))
            try await gateway.remove(.lastSyncTimestamp(Date()))

            preferences = UserPreferences()
            onboarding = OnboardingProgress()
            draftTask = DraftTask()
            recentSearches = []
            lastSync = nil

            showStatus("All data cleared")
        } catch {
            self.error = error
        }
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }
}

#Preview {
    NavigationStack {
        PersistenceGatewayShowcaseView()
    }
}
