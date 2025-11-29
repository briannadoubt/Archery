#if DEBUG
import SwiftUI
import Archery

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
#Preview("Scoreboard – Catalog") {
    ThemePreviewCatalog { variant, _ in
        Group {
            ScoreboardView.preview(scenario: .success, variant: variant, name: "Success")
            ScoreboardView.preview(scenario: .empty, variant: variant, name: "Empty")
            ScoreboardView.preview(scenario: .error, variant: variant, name: "Error")
        }
    }
}

#if !compiler(>=6.0)
// Legacy previews for Xcode before #Preview support.
struct ScoreboardView_LegacyPreviews: PreviewProvider {
    static var previews: some View {
        ThemePreviewCatalog { variant, _ in
            Group {
                ScoreboardView.preview(scenario: .success, variant: variant, name: "Success")
                ScoreboardView.preview(scenario: .empty, variant: variant, name: "Empty")
                ScoreboardView.preview(scenario: .error, variant: variant, name: "Error")
            }
        }
    }
}
#endif

private extension ScoreboardView {
    @ViewBuilder
    static func preview(scenario: DemoScenario, variant: ThemeVariant, name: String) -> some View {
        let container = makePreviewContainer(scenario)
        ScoreboardView()
            .environment(\.archeryContainer, container)
            .archeryThemeScope(ArcheryDesignTokens.self, variant: variant)
            .task {
                if let vm: ScoreboardViewModel = container.resolve() {
                    await vm.load()
                }
            }
            .previewDisplayName("\(variant.rawValue.capitalized) – \(name)")
    }
}
#endif
