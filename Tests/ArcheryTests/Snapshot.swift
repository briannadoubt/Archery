import Foundation

@MainActor
func snapshot(_ name: String, file: StaticString = #filePath, line: UInt = #line) -> String {
    recordSnapshotsIfNeeded()

    let base = URL(fileURLWithPath: String(describing: file))
        .deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__")
        .appendingPathComponent(name)
        .appendingPathExtension("txt")

    do {
        return try String(contentsOf: base, encoding: .utf8)
    } catch {
        fatalError("Missing snapshot \(base.path) – run the snapshot generator. (\(error))")
    }
}
