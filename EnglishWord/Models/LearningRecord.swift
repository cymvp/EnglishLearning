import SwiftData
import Foundation

@Model
final class LearningRecord {
    var date: Date
    var pronunciationPassed: Bool
    var spellingPassed: Bool
    var word: Word?

    var isFullyPassed: Bool {
        pronunciationPassed && spellingPassed
    }

    init(date: Date = Date()) {
        self.date = date
        self.pronunciationPassed = false
        self.spellingPassed = false
    }
}
