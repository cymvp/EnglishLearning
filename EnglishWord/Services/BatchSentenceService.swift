import Foundation
import SwiftData

@Observable
@MainActor
final class BatchSentenceService {
    var totalCount: Int = 0
    var completedCount: Int = 0
    var failedCount: Int = 0
    var isProcessing: Bool = false

    var progressText: String {
        "正在为 \(totalCount) 个单词生成例句... \(completedCount)/\(totalCount)"
    }

    func generateSentencesForAll(
        words: [(spelling: String, meaning: String, modelID: PersistentIdentifier)],
        modelContext: ModelContext,
        maxConcurrency: Int = 5
    ) async {
        guard let service = AIServiceFactory.learningService() else { return }

        isProcessing = true
        totalCount = words.count
        completedCount = 0
        failedCount = 0

        await withTaskGroup(of: (PersistentIdentifier, [SentenceResult]?).self) { group in
            var wordIterator = words.makeIterator()

            // Seed with up to maxConcurrency tasks
            for _ in 0..<maxConcurrency {
                guard let word = wordIterator.next() else { break }
                group.addTask {
                    do {
                        let results = try await service.generateSentences(
                            for: word.spelling, meaning: word.meaning
                        )
                        return (word.modelID, results)
                    } catch {
                        return (word.modelID, nil)
                    }
                }
            }

            // As each task completes, add the next one
            for await (modelID, results) in group {
                if let results = results {
                    if let word = modelContext.model(for: modelID) as? Word,
                       word.sentences.isEmpty {
                        for result in results {
                            let sentence = ExampleSentence(english: result.english, chinese: result.chinese)
                            sentence.word = word
                            modelContext.insert(sentence)
                        }
                    }
                    completedCount += 1
                } else {
                    completedCount += 1
                    failedCount += 1
                }

                if let nextWord = wordIterator.next() {
                    group.addTask {
                        do {
                            let results = try await service.generateSentences(
                                for: nextWord.spelling, meaning: nextWord.meaning
                            )
                            return (nextWord.modelID, results)
                        } catch {
                            return (nextWord.modelID, nil)
                        }
                    }
                }
            }
        }

        isProcessing = false
    }
}
