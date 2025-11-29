import Archery
import XCTest

private enum DemoTab: String, CaseIterable, Hashable {
    case home
    case scores
}

enum DemoRoute: NavigationRoute, Codable, Equatable {
    case home
    case player(id: UUID)
    case leaderboard
    case gated
}

final class NavigationRouterTests: XCTestCase {
    func testDeepLinkRoutesURLPattern() {
        var router = DeepLinkRouter<DemoRoute>()
        router.registerURL(scheme: "archery", host: "app", path: "players/:id") { _, params, _ in
            guard let raw = params["id"], let id = UUID(uuidString: raw) else { return nil }
            return .player(id: id)
        }

        let url = URL(string: "archery://app/players/00000000-0000-0000-0000-000000000042")!
        let match = router.route(from: .url(url))
        XCTAssertEqual(match?.route, .player(id: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!))
    }

    func testNotificationHandoffFallsBackToURL() {
        var router = DeepLinkRouter<DemoRoute>()
        router.registerURL(scheme: "archery", host: "app", path: "home") { _, _, _ in .home }

        let payload: [AnyHashable: Any] = ["url": "archery://app/home"]
        let match = router.route(from: .notification(userInfo: payload))
        XCTAssertEqual(match?.route, .home)
    }

    func testShortcutMatchesRegisteredHandler() {
        var router = DeepLinkRouter<DemoRoute>()
        router.registerShortcut { id, _ in
            id == "open.leaderboard" ? .leaderboard : nil
        }

        let match = router.route(from: .shortcut(id: "open.leaderboard"))
        XCTAssertEqual(match?.route, .leaderboard)
    }

    func testRouteGuardBlocksNavigation() async {
        var router = DeepLinkRouter<DemoRoute>()
        router.registerShortcut { id, _ in id == "gated" ? .gated : nil }

        let gate = RouteGuard<DemoRoute> { route in
            if case .gated = route {
                return .blocked(AppError(title: "Auth Required", message: "Sign in to continue", category: .validation))
            }
            return .allowed
        }

        let result = await router.resolve(.shortcut(id: "gated"), gate: gate)
        switch result {
        case .failure(let error):
            XCTAssertEqual(error.title, "Auth Required")
        case .success:
            XCTFail("Expected guard to block route")
        }
    }

    func testNavigationStateRestoresFromStore() {
        let store = NavigationMemoryStore()
        let persistence = NavigationPersistence(mode: .enabled, key: "nav.test", store: store)
        let restorer = NavigationRestorer<DemoTab>(persistence: persistence)

        let paths: [DemoTab: [AnyHashable]] = [
            .home: [DemoRoute.home],
            .scores: [DemoRoute.leaderboard]
        ]

        restorer.persist(selection: .scores, paths: paths, tabEncoder: { $0.rawValue }, encoder: { _, element in
            (element as? DemoRoute)?.navigationIdentifier
        })

        let restored = restorer.restore(tabDecoder: { DemoTab(rawValue: $0) }, decoder: { _, value in
            DemoRoute.decodeNavigationIdentifier(value)
        })

        XCTAssertEqual(restored.selection, .scores)
        XCTAssertEqual(restored.paths[.scores]?.first as? DemoRoute, .leaderboard)
    }
}
