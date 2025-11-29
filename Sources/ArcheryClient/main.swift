import Archery
import Foundation

@KeyValueStore
enum ClientStore {
    case username(String)
    case highScore(Int)
}

@main
struct ArcheryClient {
    static func main() async {
        var store = ClientStore.Store(
            migrations: ["ClientStore.user_name": "ClientStore.username"]
        )

        // Demonstrate default values and async/throwing set/get
        let initialUser = try? await store.username(default: "Guest")
        print("Initial user:", initialUser ?? "<nil>")

        try? await store.set(.username("Taylor"))
        let updatedUser = try? await store.username(default: "Guest")
        print("Updated user:", updatedUser ?? "<nil>")

        // Listen for change notifications
        let changes = store.changes()
        var iterator = changes.makeAsyncIterator()

        try? await store.set(.highScore(9001))
        if let change = await iterator.next(),
           case .highScore = change.key,
           let data = change.data,
           let score = try? JSONDecoder().decode(Int.self, from: data) {
            print("High score updated:", score)
        }
    }
}
