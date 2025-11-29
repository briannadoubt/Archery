import Archery
import SwiftUI

public struct ArcheryClientEntry: View {
    public init() {}

    public var body: some View {
        ScoreboardView()
    }
}

#if DEBUG
struct ArcheryClientEntry_Previews: PreviewProvider {
    static var previews: some View {
        ScoreboardView()
    }
}
#endif
