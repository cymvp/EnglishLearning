import SwiftUI
import SwiftData

@main
struct EnglishWordApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            Word.self,
            ExampleSentence.self,
            LearningRecord.self,
            Exam.self,
            ExamQuestion.self
        ])
    }
}
