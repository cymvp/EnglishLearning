import SwiftData
import Foundation

@Model
final class ExamQuestion {
    var wordSpelling: String
    var chineseMeaning: String
    var studentAnswer: String
    var isCorrect: Bool
    var score: Int
    var exam: Exam?

    init(wordSpelling: String, chineseMeaning: String) {
        self.wordSpelling = wordSpelling
        self.chineseMeaning = chineseMeaning
        self.studentAnswer = ""
        self.isCorrect = false
        self.score = 0
    }
}
