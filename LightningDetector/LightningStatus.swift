import Foundation

struct LightningStatus {
    var isDetected: Bool
    var timestamp: Date

    static let safe = LightningStatus(isDetected: false, timestamp: .now)
}
