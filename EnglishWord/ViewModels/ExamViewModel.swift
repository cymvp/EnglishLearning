import SwiftUI
import SwiftData

@Observable
final class ExamViewModel {
    var questions: [ExamQuestion] = []
    var currentIndex: Int = 0
    var isFinished: Bool = false
    var spellingInput: String = ""
    var exam: Exam?

    let tts = SpeechSynthesizerService()

    var currentQuestion: ExamQuestion? {
        guard currentIndex >= 0, currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var totalScore: Int {
        questions.reduce(0) { $0 + $1.score }
    }

    func generateExam(from words: [Word], modelContext: ModelContext) {
        let pool = words.filter { !$0.spelling.isEmpty }
        guard !pool.isEmpty else { return }

        let count = min(pool.count, Constants.Exam.questionsPerExam)
        let selected = Array(pool.shuffled().prefix(count))
        let newExam = Exam(date: Date())
        modelContext.insert(newExam)

        var newQuestions: [ExamQuestion] = []
        for word in selected {
            let question = ExamQuestion(wordSpelling: word.spelling, chineseMeaning: word.chineseMeaning)
            question.exam = newExam
            modelContext.insert(question)
            newQuestions.append(question)
        }

        exam = newExam
        questions = newQuestions
        currentIndex = 0
        isFinished = false
        spellingInput = ""
    }

    func speakCurrentWord() {
        guard let question = currentQuestion else { return }
        tts.speak(question.wordSpelling)
    }

    func submitAnswer() {
        guard let question = currentQuestion else { return }
        let normalized = spellingInput.lowercased().trimmingCharacters(in: .whitespaces)
        question.studentAnswer = normalized
        question.isCorrect = normalized == question.wordSpelling.lowercased()
        question.score = question.isCorrect ? Constants.Exam.scorePerQuestion : 0

        if currentIndex < questions.count - 1 {
            currentIndex += 1
            spellingInput = ""
        } else {
            finishExam()
        }
    }

    private func finishExam() {
        exam?.totalScore = totalScore
        isFinished = true
    }
}
