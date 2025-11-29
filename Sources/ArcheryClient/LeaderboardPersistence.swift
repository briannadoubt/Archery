import Archery
import Foundation

@PersistenceGateway
enum LeaderboardCache {
    case players([Player])
    case lastUpdated(Date)
}

extension LeaderboardCache.Gateway {
    static func diskCache() -> LeaderboardCache.Gateway? {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = cacheDir.appendingPathComponent("leaderboard-cache.sqlite")
        return try? LeaderboardCache.Gateway(url: url)
    }

    static func preview(_ players: [Player]) -> LeaderboardCache.Gateway {
        try! LeaderboardCache.Gateway(
            inMemory: [
                (.players(players), players),
                (.lastUpdated(Date()), Date())
            ]
        )
    }
}
