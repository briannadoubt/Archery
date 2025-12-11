import SwiftUI

struct ProfileView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Profile header
                VStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)

                    Text("Demo User")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("demo@archery.app")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical)

                // Account info
                GroupBox("Account Info") {
                    VStack(spacing: 0) {
                        InfoRow(label: "Member Since", value: "January 2024")
                        Divider()
                        InfoRow(label: "Plan", value: "Premium")
                        Divider()
                        InfoRow(label: "Tasks Created", value: "147")
                    }
                }
                .padding(.horizontal)

                // Sign out button
                Button(role: .destructive) {
                    // Sign out action
                } label: {
                    Text("Sign Out")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
}
