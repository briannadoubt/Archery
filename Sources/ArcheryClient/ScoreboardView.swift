import Archery
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(WatchKit)
import WatchKit
#endif

struct Player: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let score: Int

    init(id: UUID = UUID(), name: String, score: Int) {
        self.id = id
        self.name = name
        self.score = score
    }
}

@Repository
class LeaderboardRepository {
    private let api: LeaderboardAPIProtocol

    init(api: LeaderboardAPIProtocol = LeaderboardAPILive()) {
        self.api = api
    }

    func topPlayers() async throws -> [Player] {
        try await api.leaderboard()
    }
}

@MainActor
@ObservableViewModel
final class ScoreboardViewModel: Resettable {
    nonisolated(unsafe) private let repo: LeaderboardRepositoryProtocol
    var leaderboard: LoadState<[Player]> = .idle

    convenience init() {
        self.init(repo: LeaderboardRepositoryLive())
    }

    init(repo: LeaderboardRepositoryProtocol) {
        self.repo = repo
    }

    func load() async {
        beginLoading(\.leaderboard)
        do {
            let players = try await repo.topPlayers()
            endSuccess(\.leaderboard, value: players)
        } catch {
            endFailure(\.leaderboard, error: mapToAppError(error))
        }
    }

    private func mapToAppError(_ error: Error) -> AppError {
        if let app = error as? AppError { return app }
        if error is URLError {
            return AppError(
                title: "Network Issue",
                message: "Could not load the leaderboard. Please check your connection.",
                category: .network,
                metadata: ["context": "leaderboard.load"],
                underlying: error
            )
        }
        return AppError.wrap(
            error,
            fallbackMessage: "Could not load the leaderboard. Please try again.",
            category: .unknown
        )
    }
}

@ViewModelBound<ScoreboardViewModel>
struct ScoreboardView: View {
    @State private var presentedError: AppError?
    @Environment(\.archeryHapticsEnabled) private var hapticsEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Players")
                .font(.title2.bold())

            content()
        }
        .padding()
        .onChange(of: vm.leaderboard) { _, state in
            if case .failure(let error) = state {
                presentedError = (error as? AppError) ?? AppError.wrap(error, fallbackMessage: "Could not load the leaderboard.")
            }
        }
        .alert(item: $presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private func content() -> some View {
        switch vm.leaderboard {
        case .idle:
            ProgressView().task { await vm.load() }
        case .loading:
            ProgressView("Loading…")
        case .success(let players):
            if players.isEmpty {
                Label("No scores yet", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            } else {
                List(players) { player in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(player.name).font(.headline)
                            Text("Score: \(player.score)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "target")
                            .foregroundStyle(.blue)
                    }
                }
                .listStyle(.plain)
            }
        case .failure(let error):
            let appError = (error as? AppError) ?? AppError.wrap(error, fallbackMessage: "Could not load the leaderboard.")
            VStack(alignment: .leading, spacing: 12) {
                Label(appError.title, systemImage: "xmark.circle")
                    .foregroundStyle(.red)
                Text(appError.message).foregroundStyle(.secondary)
                Button {
                    playRetryHaptic()
                    Task { await vm.load() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }

    private func playRetryHaptic() {
        guard hapticsEnabled else { return }
        #if canImport(UIKit) && !os(tvOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #elseif canImport(WatchKit)
        WKInterfaceDevice.current().play(.click)
        #endif
    }
}

#if DEBUG
extension ScoreboardView {
    enum DemoScenario {
        case success
        case empty
        case error
        case networkStub
    }

    /// Builds an EnvContainer seeded with a mock repo + VM for previews or host embedding.
    static func makePreviewContainer(_ scenario: DemoScenario = .success) -> EnvContainer {
        let container = previewContainer()
        let repo: LeaderboardRepositoryProtocol

        switch scenario {
        case .success:
            let mockRepo = MockLeaderboardRepository()
            mockRepo.topPlayersHandler = {
                [
                    Player(name: "Robin", score: 88),
                    Player(name: "Marin", score: 76),
                    Player(name: "Quinn", score: 64)
                ]
            }
            repo = mockRepo
        case .empty:
            let mockRepo = MockLeaderboardRepository()
            mockRepo.topPlayersHandler = { [] }
            repo = mockRepo
        case .error:
            let mockRepo = MockLeaderboardRepository()
            mockRepo.topPlayersHandler = { throw URLError(.badServerResponse) }
            repo = mockRepo
        case .networkStub:
            let stubAPI = MockLeaderboardAPI()
            stubAPI.leaderboardHandler = {
                try APIDecodingConfiguration(keyDecodingStrategy: .convertFromSnakeCase)
                    .makeDecoder()
                    .decode([Player].self, from: LeaderboardAPI.Fixtures.success)
            }
            repo = LeaderboardRepositoryLive(baseFactory: { LeaderboardRepository(api: stubAPI) })
        }

        container.register(repo as LeaderboardRepositoryProtocol)
        container.registerFactory { ScoreboardViewModel(repo: repo) }
        return container
    }

    struct Mocked_Previews: PreviewProvider {
        static var previews: some View {
            Group {
                ScoreboardView()
                    .environment(\.archeryContainer, makePreviewContainer(.success))
                    .previewDisplayName("Success")

                ScoreboardView()
                    .environment(\.archeryContainer, makePreviewContainer(.empty))
                    .previewDisplayName("Empty")

                ScoreboardView()
                    .environment(\.archeryContainer, makePreviewContainer(.error))
                    .previewDisplayName("Error")

                ScoreboardView()
                    .environment(\.archeryContainer, makePreviewContainer(.networkStub))
                    .previewDisplayName("Network Stub")
            }
        }
    }
}
#endif

#Preview {
    ScoreboardView()
}
