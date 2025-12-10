import SwiftUI

// MARK: - Premium Task Features

struct TaskAnalyticsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Task Analytics")
                .font(.largeTitle)

            Text("Premium feature - requires .premium entitlement")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Analytics")
    }
}

struct TaskBulkEditView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Bulk Edit")
                .font(.largeTitle)

            Text("Pro feature - requires .pro entitlement")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Bulk Edit")
    }
}

#Preview("Analytics") {
    NavigationStack {
        TaskAnalyticsView()
    }
}

#Preview("Bulk Edit") {
    NavigationStack {
        TaskBulkEditView()
    }
}
