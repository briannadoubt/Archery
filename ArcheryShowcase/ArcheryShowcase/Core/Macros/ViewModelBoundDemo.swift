import Foundation
import SwiftUI
import Archery

// MARK: - @ViewModelBound Demo
//
// The @ViewModelBound macro generates:
// - ViewModel storage with DI container integration
// - `vm` computed property for accessing the ViewModel
// - Preview container helper for SwiftUI previews
// - Auto-load wrapper that calls load() on appear
// - PreviewModifier for modern #Preview syntax

// First, define a simple ViewModel using @ObservableViewModel
@Observable
@MainActor
final class CounterViewModel: Resettable {
    var count: Int = 0
    var isLoading = false

    func increment() {
        count += 1
    }

    func decrement() {
        count = max(0, count - 1)
    }

    func reset() {
        count = 0
    }

    func load() async {
        isLoading = true
        // Simulate loading initial state
        try? await Task.sleep(for: .milliseconds(500))
        count = 42 // Load initial value
        isLoading = false
    }
}

// Apply @ViewModelBound to bind the view to the ViewModel
// The macro generates DI-aware binding with automatic preview support
@ViewModelBound<CounterViewModel>
struct CounterView: View {
    var body: some View {
        VStack(spacing: 24) {
            // Access ViewModel via generated `vm` property
            if vm.isLoading {
                ProgressView("Loading...")
            } else {
                Text("\(vm.count)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())

                HStack(spacing: 20) {
                    Button {
                        vm.decrement()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 44))
                    }
                    .disabled(vm.count == 0)

                    Button {
                        vm.increment()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 44))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
        .animation(.spring(duration: 0.3), value: vm.count)
        .animation(.easeInOut, value: vm.isLoading)
    }
}

// MARK: - Showcase View

struct ViewModelBoundShowcaseView: View {
    var body: some View {
        List {
            Section {
                Text("@ViewModelBound generates DI-aware View binding with automatic ViewModel injection and preview support.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Live Demo") {
                // Use the generated preview container for this demo
                let container = CounterView.previewContainer()
                CounterView()
                    .environment(\.archeryContainer, container)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }

            Section("What Gets Generated") {
                VStack(alignment: .leading, spacing: 12) {
                    GeneratedCodeRow(
                        name: "vm property",
                        description: "Access to the injected ViewModel"
                    )
                    GeneratedCodeRow(
                        name: "previewContainer()",
                        description: "Static method for preview DI setup"
                    )
                    GeneratedCodeRow(
                        name: "PreviewModifier",
                        description: "For #Preview(traits:) syntax"
                    )
                    GeneratedCodeRow(
                        name: "Auto-load",
                        description: "Calls load() when view appears"
                    )
                }
            }

            Section("Usage") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("@ViewModelBound<MyViewModel>")
                        .font(.caption.monospaced())
                    Text("struct MyView: View {")
                        .font(.caption.monospaced())
                    Text("    var body: some View {")
                        .font(.caption.monospaced())
                    Text("        Text(vm.title)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("    }")
                        .font(.caption.monospaced())
                    Text("}")
                        .font(.caption.monospaced())
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Section("Options") {
                LabeledContent("useStateObject") {
                    Text("true (default)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                LabeledContent("autoLoad") {
                    Text("true (default)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("@ViewModelBound")
    }
}

private struct GeneratedCodeRow: View {
    let name: String
    let description: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

#Preview {
    NavigationStack {
        ViewModelBoundShowcaseView()
    }
}
