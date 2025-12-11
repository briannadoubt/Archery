import SwiftUI

struct DeepLinkTesterView: View {
    @State private var urlText = "tasks/list"
    @State private var matchedRoute: String?

    var body: some View {
        Form {
            Section("Test URL Path") {
                TextField("Enter path (e.g., tasks/list)", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Test Route") {
                    testRoute()
                }
            }

            Section("Result") {
                if let route = matchedRoute {
                    Label(route, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("No match", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Available Routes") {
                Group {
                    Text("dashboard/main, dashboard/stats, dashboard/insights")
                    Text("tasks/list, tasks/create, tasks/{id}")
                    Text("forms/list, forms/registration, forms/contact")
                    Text("settings/main, settings/profile, settings/preferences")
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Deep Links")
    }

    private func testRoute() {
        let path = urlText.split(separator: "/").map(String.init)

        if let route = TasksRoute.fromURL(path: path, query: [:]) {
            matchedRoute = "TasksRoute.\(route)"
        } else if let route = DashboardRoute.fromURL(path: path, query: [:]) {
            matchedRoute = "DashboardRoute.\(route)"
        } else if let route = FormsRoute.fromURL(path: path, query: [:]) {
            matchedRoute = "FormsRoute.\(route)"
        } else if let route = SettingsRoute.fromURL(path: path, query: [:]) {
            matchedRoute = "SettingsRoute.\(route)"
        } else {
            matchedRoute = nil
        }
    }
}

#Preview {
    NavigationStack {
        DeepLinkTesterView()
    }
}
