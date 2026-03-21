import SeleneShared
import Foundation

#if DEBUG

/// Protocol for types that can contribute to debug snapshots
protocol DebugSnapshotProvider {
    /// Returns a dictionary representation of the current state
    /// Values must be JSON-serializable (String, Int, Double, Bool, Array, Dictionary)
    func debugSnapshot() -> [String: Any]
}

#endif
