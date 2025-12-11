import SwiftUI

struct SubscriptionView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Premium Features")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                FeatureRow(icon: "infinity", title: "Unlimited Tasks", description: "Create as many tasks as you need")
                FeatureRow(icon: "person.3", title: "Team Collaboration", description: "Work together with your team")
                FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Advanced Analytics", description: "Detailed insights and reports")

                Button("Subscribe Now") {
                    // Handle subscription
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        SubscriptionView()
    }
}
