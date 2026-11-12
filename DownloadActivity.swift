import Foundation
import Combine
import ActivityKit

// Shared between the app and the NuviGoWidgets extension. Describes the Lock Screen / Dynamic Island download card.

struct DownloadActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String       // what is downloading right now
        var progress: Double    // 0...1 for that file
        var finished: Int       // files done in this batch
        var total: Int          // files in this batch
    }
    var name = "Downloads"
}
