import SwiftData
import Foundation

@Model
final class ExampleSentence {
    var english: String
    var chinese: String
    var word: Word?

    init(english: String, chinese: String) {
        self.english = english
        self.chinese = chinese
    }
}
