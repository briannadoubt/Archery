import SwiftUI

struct OnboardingFlow: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack {
            TabView {
                OnboardingPage(
                    title: "Welcome to Archery",
                    description: "A powerful task management app built with SwiftUI macros",
                    icon: "target",
                    color: .blue
                )

                OnboardingPage(
                    title: "Stay Organized",
                    description: "Create tasks, set priorities, and track your progress",
                    icon: "checklist",
                    color: .green
                )

                OnboardingPage(
                    title: "Work Together",
                    description: "Collaborate with your team in real-time",
                    icon: "person.3",
                    color: .purple
                )
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button("Get Started") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 40)
        }
    }
}

struct OnboardingPage: View {
    let title: String
    let description: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 80))
                .foregroundStyle(color)

            Text(title)
                .font(.title)
                .fontWeight(.bold)

            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

#Preview {
    OnboardingFlow()
}
