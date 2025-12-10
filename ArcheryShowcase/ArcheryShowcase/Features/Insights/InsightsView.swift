import SwiftUI

struct InsightsTabContent: View {
    var body: some View {
        List {
            Section("Premium Insights") {
                NavigationLink {
                    Text("Weekly Summary").navigationTitle("Weekly")
                } label: {
                    Label("Weekly Summary", systemImage: "chart.bar")
                }
                NavigationLink {
                    Text("Trend Analysis").navigationTitle("Trends")
                } label: {
                    Label("Trend Analysis", systemImage: "chart.line.uptrend.xyaxis")
                }
                NavigationLink {
                    Text("Productivity Score").navigationTitle("Score")
                } label: {
                    Label("Productivity Score", systemImage: "gauge")
                }
            }

            Section("Reports") {
                NavigationLink {
                    Text("Export Reports").navigationTitle("Export")
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle("Insights")
    }
}

#Preview {
    NavigationStack {
        InsightsTabContent()
    }
}
