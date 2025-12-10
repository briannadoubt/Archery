import SwiftUI

struct AdminTabContent: View {
    var body: some View {
        List {
            Section("Administration") {
                NavigationLink {
                    Text("User Management").navigationTitle("Users")
                } label: {
                    Label("Users", systemImage: "person.3")
                }
                NavigationLink {
                    Text("Permissions").navigationTitle("Permissions")
                } label: {
                    Label("Permissions", systemImage: "lock.shield")
                }
                NavigationLink {
                    Text("Audit Log").navigationTitle("Audit")
                } label: {
                    Label("Audit Log", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        .navigationTitle("Admin")
    }
}

#Preview {
    NavigationStack {
        AdminTabContent()
    }
}
