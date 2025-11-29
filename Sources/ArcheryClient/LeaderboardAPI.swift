import Archery
import Foundation

@APIClient
class LeaderboardAPI {
    private let payload: Data

    init(payload: Data = Fixtures.success) {
        self.payload = payload
    }

    func leaderboard() async throws -> [Player] {
        let decoder = APIDecodingConfiguration(
            dateDecodingStrategy: .iso8601,
            keyDecodingStrategy: .convertFromSnakeCase
        ).makeDecoder()
        return try decoder.decode([Player].self, from: payload)
    }
}

extension LeaderboardAPI {
    enum Fixtures {
        static let success: Data = """
        [
            {"id":"00000000-0000-0000-0000-000000000001","name":"Robin","score":88},
            {"id":"00000000-0000-0000-0000-000000000002","name":"Marin","score":76},
            {"id":"00000000-0000-0000-0000-000000000003","name":"Quinn","score":64}
        ]
        """.data(using: .utf8)!

        static let empty: Data = "[]".data(using: .utf8)!
    }
}
