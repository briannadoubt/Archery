import Archery
import SwiftUI

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
    func topPlayers() async throws -> [Player] {
        []
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
            endFailure(\.leaderboard, error: error)
        }
    }
}

@ViewModelBound<ScoreboardViewModel>
struct ScoreboardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Players")
                .font(.title2.bold())

            content()
        }
        .padding()
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
        case .failure:
            Label("Could not load leaderboard", systemImage: "xmark.circle")
                .foregroundStyle(.red)
        }
    }
}

#if DEBUG
extension ScoreboardView {
    enum DemoScenario {
        case success
        case empty
        case error
    }

    /// Builds an EnvContainer seeded with a mock repo + VM for previews or host embedding.
    static func makePreviewContainer(_ scenario: DemoScenario = .success) -> EnvContainer {
        let container = previewContainer()
        let mockRepo = MockLeaderboardRepository()
        switch scenario {
        case .success:
            mockRepo.topPlayersHandler = {
                [
                    Player(name: "Robin", score: 88),
                    Player(name: "Marin", score: 76),
                    Player(name: "Quinn", score: 64)
                ]
            }
        case .empty:
            mockRepo.topPlayersHandler = { [] }
        case .error:
            mockRepo.topPlayersHandler = { throw URLError(.badServerResponse) }
        }
        container.register(mockRepo as LeaderboardRepositoryProtocol)
        container.registerFactory { ScoreboardViewModel(repo: mockRepo) }
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
            }
        }
    }
}
#endif

#Preview {
    ScoreboardView()
}
