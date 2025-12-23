import Archery
import Foundation
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

@MainActor
@ObservableViewModel
final class ScoreboardViewModel: Resettable {
    nonisolated(unsafe) private let api: LeaderboardAPIProtocol
    var leaderboard: LoadState<[Player]> = .idle

    convenience init() {
        self.init(api: LeaderboardAPILive())
    }

    init(api: LeaderboardAPIProtocol) {
        self.api = api
    }

    func load() async {
        beginLoading(\.leaderboard)
        do {
            let players = try await api.leaderboard()
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
    @Environment(\.archeryTheme) private var theme

    private typealias Palette = ArcheryDesignTokens.ColorToken
    private typealias TypeScale = ArcheryDesignTokens.TypographyToken
    private typealias Spacing = ArcheryDesignTokens.SpacingToken

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(Spacing.md)) {
            Text("Top Players")
                .font(theme.typography(TypeScale.title).font)
                .foregroundStyle(theme.color(Palette.text))

            content()
        }
        .padding(theme.spacing(Spacing.lg))
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
                .tint(theme.color(Palette.accent))
        case .success(let players):
            if players.isEmpty {
                Label("No scores yet", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(theme.color(Palette.mutedText))
            } else {
                List(players) { player in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(player.name)
                                .font(theme.typography(TypeScale.body).font)
                                .foregroundStyle(theme.color(Palette.text))
                            Text("Score: \(player.score)")
                                .font(theme.typography(TypeScale.caption).font)
                                .foregroundStyle(theme.color(Palette.mutedText))
                        }
                        Spacer()
                        Image(systemName: "target")
                            .foregroundStyle(theme.color(Palette.accent))
                    }
                    .padding(.vertical, theme.spacing(Spacing.sm))
                    .listRowBackground(theme.color(Palette.surface))
                }
                .listStyle(.plain)
            }
        case .failure(let error):
            let appError = (error as? AppError) ?? AppError.wrap(error, fallbackMessage: "Could not load the leaderboard.")
            VStack(alignment: .leading, spacing: theme.spacing(Spacing.md)) {
                Label(appError.title, systemImage: "xmark.circle")
                    .font(theme.typography(TypeScale.label).font)
                    .foregroundStyle(theme.color(Palette.danger))
                Text(appError.message)
                    .font(theme.typography(TypeScale.body).font)
                    .foregroundStyle(theme.color(Palette.mutedText))
                Button {
                    playRetryHaptic()
                    Task { await vm.load() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                        .padding(.vertical, theme.spacing(Spacing.xs))
                        .padding(.horizontal, theme.spacing(Spacing.sm))
                        .background(theme.color(Palette.accent).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: theme.spacing(Spacing.sm)))
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

    /// Builds an EnvContainer seeded with a mock API + VM for previews or host embedding.
    static func makePreviewContainer(_ scenario: DemoScenario = .success) -> EnvContainer {
        let container = previewContainer()
        let api: LeaderboardAPIProtocol

        switch scenario {
        case .success:
            let mockAPI = MockLeaderboardAPI()
            mockAPI.leaderboardHandler = {
                [
                    Player(name: "Robin", score: 88),
                    Player(name: "Marin", score: 76),
                    Player(name: "Quinn", score: 64)
                ]
            }
            api = mockAPI
        case .empty:
            let mockAPI = MockLeaderboardAPI()
            mockAPI.leaderboardHandler = { [] }
            api = mockAPI
        case .error:
            let mockAPI = MockLeaderboardAPI()
            mockAPI.leaderboardHandler = { throw URLError(.badServerResponse) }
            api = mockAPI
        case .networkStub:
            let stubAPI = MockLeaderboardAPI()
            stubAPI.leaderboardHandler = {
                try APIDecodingConfiguration(keyDecodingStrategy: .convertFromSnakeCase)
                    .makeDecoder()
                    .decode([Player].self, from: LeaderboardAPI.Fixtures.success)
            }
            api = stubAPI
        }

        container.register(api as LeaderboardAPIProtocol)
        container.registerFactory { ScoreboardViewModel(api: api) }
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
        .environment(\.archeryContainer, ScoreboardView.makePreviewContainer(.success))
        .archeryThemeScope()
}
