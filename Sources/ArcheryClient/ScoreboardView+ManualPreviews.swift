#if DEBUG
import SwiftUI
import Archery
// The macro-generated modifier lives in the same module, so use the unqualified name.

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
#Preview("Scoreboard – Success") {
    let container = ScoreboardView.makePreviewContainer(.success)
    return ScoreboardView()
        .environment(\.archeryContainer, container)
        .task {
            if let vm: ScoreboardViewModel = container.resolve() { await vm.load() }
        }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
#Preview("Scoreboard – Empty") {
    let container = ScoreboardView.makePreviewContainer(.empty)
    return ScoreboardView()
        .environment(\.archeryContainer, container)
        .task {
            if let vm: ScoreboardViewModel = container.resolve() { await vm.load() }
        }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
#Preview("Scoreboard – Error") {
    let container = ScoreboardView.makePreviewContainer(.error)
    return ScoreboardView()
        .environment(\.archeryContainer, container)
        .task {
            if let vm: ScoreboardViewModel = container.resolve() { await vm.load() }
        }
}

#if !compiler(>=6.0)
// Xcode versions before #Preview support still need a PreviewProvider.
struct ScoreboardView_LegacyPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            ScoreboardView()
                .environment(\.archeryContainer, ScoreboardView.makePreviewContainer(.success))
            ScoreboardView()
                .environment(\.archeryContainer, ScoreboardView.makePreviewContainer(.empty))
            ScoreboardView()
                .environment(\.archeryContainer, ScoreboardView.makePreviewContainer(.error))
        }
    }
}
#endif
#endif
