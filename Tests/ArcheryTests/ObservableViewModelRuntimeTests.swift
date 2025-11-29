import Archery
import XCTest

@ObservableViewModel
@MainActor
final class DebounceThrottleVM: Resettable {
    var count = 0
}

final class ObservableViewModelRuntimeTests: XCTestCase {
    func testDebounceCancelsPreviousTask() async throws {
        let vm = await MainActor.run { DebounceThrottleVM() }

        await MainActor.run {
            vm.debounce(dueTime: .milliseconds(80)) { @MainActor in
                vm.count += 1
            }
            vm.debounce(dueTime: .milliseconds(80)) { @MainActor in
                vm.count += 1
            }
        }

        try await Task.sleep(for: .milliseconds(150))

        let value = await MainActor.run { vm.count }
        XCTAssertEqual(value, 1)
    }

    func testThrottleSkipsWithinIntervalThenFires() async throws {
        let vm = await MainActor.run { DebounceThrottleVM() }

        await MainActor.run {
            vm.throttle(interval: .milliseconds(100)) { @MainActor in
                vm.count += 1
            }
            vm.throttle(interval: .milliseconds(100)) { @MainActor in
                vm.count += 1
            }
        }

        try await Task.sleep(for: .milliseconds(160))
        let first = await MainActor.run { vm.count }
        XCTAssertEqual(first, 1)

        await MainActor.run {
            vm.throttle(interval: .milliseconds(100)) { @MainActor in
                vm.count += 1
            }
        }

        try await Task.sleep(for: .milliseconds(140))
        let second = await MainActor.run { vm.count }
        XCTAssertEqual(second, 2)
    }
}
