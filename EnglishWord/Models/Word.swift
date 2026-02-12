import SwiftData
import Foundation

@Model
final class Word {
    @Attribute(.unique) var spelling: String
    var phonetic: String
    var chineseMeaning: String
    var createdAt: Date
    var isMastered: Bool
    var masteredAt: Date?
    var source: String = "manual"

    @Relationship(deleteRule: .cascade, inverse: \ExampleSentence.word)
    var sentences: [ExampleSentence]

    @Relationship(deleteRule: .cascade, inverse: \LearningRecord.word)
    var learningRecords: [LearningRecord]

    init(spelling: String, phonetic: String = "", chineseMeaning: String = "", source: String = "manual") {
        self.spelling = spelling.lowercased().trimmingCharacters(in: .whitespaces)
        self.phonetic = phonetic
        self.chineseMeaning = chineseMeaning
        self.createdAt = Date()
        self.isMastered = false
        self.masteredAt = nil
        self.sentences = []
        self.learningRecords = []
        self.source = source
    }
}
