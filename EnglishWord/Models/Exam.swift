import SwiftData
import Foundation

@Model
final class Exam {
    var date: Date
    var totalScore: Int

    @Relationship(deleteRule: .cascade, inverse: \ExamQuestion.exam)
    var questions: [ExamQuestion]

    init(date: Date = Date()) {
        self.date = date
        self.totalScore = 0
        self.questions = []
    }
}
