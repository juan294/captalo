import Foundation

extension Duration {
    nonisolated var seconds: Double {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    var short: String {
        formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated, maximumUnitCount: 1))
    }
}
