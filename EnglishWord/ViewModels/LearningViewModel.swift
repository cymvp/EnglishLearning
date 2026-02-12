import SwiftUI
import SwiftData

enum ReadAlongPhase: Equatable {
    case idle

    case aiSpeakingWord                 // AI reading the word aloud
    case waitingStudentReadWord         // Waiting for student to read word
    case listeningWord                  // Recording student reading word
    case wordFailed                     // Student failed, must retry
    case wordPassed                     // Word pronunciation passed

    case aiSpeakingSentence(index: Int)
    case waitingStudentReadSentence(index: Int)
    case listeningSentence(index: Int)
    case sentenceFailed(index: Int)
    case sentencePassed(index: Int)

    case readAlongComplete              // All reading done
    case voiceChat                      // Free voice chat about the word
}

@Observable
final class LearningViewModel {
    var currentWord: Word?
    var phase: ReadAlongPhase = .idle
    var feedbackMessage: String = ""
    var readAlongPassed: Bool = false

    let tts = SpeechSynthesizerService()
    let speechRecognizer = SpeechRecognizerService()

    var currentSentences: [ExampleSentence] {
        currentWord?.sentences ?? []
    }

    var statusText: String {
        switch phase {
        case .idle: return ""
        case .aiSpeakingWord: return "请仔细听单词发音"
        case .waitingStudentReadWord: return "请跟读这个单词"
        case .listeningWord: return "正在听你的发音..."
        case .wordFailed: return "没关系，再来一次"
        case .wordPassed: return "太棒了! 单词发音通过!"
        case .aiSpeakingSentence(let idx): return "请听第 \(idx + 1) 个例句"
        case .waitingStudentReadSentence(let idx): return "请跟读第 \(idx + 1) 个例句"
        case .listeningSentence: return "正在听你的发音..."
        case .sentenceFailed(let idx): return "没关系，第 \(idx + 1) 句再来一次"
        case .sentencePassed(let idx): return "太棒了! 第 \(idx + 1) 句通过!"
        case .readAlongComplete: return "你真厉害! 跟读全部通过!"
        case .voiceChat: return "你可以语音提问关于这个单词的问题"
        }
    }

    // MARK: - Start

    func setup(word: Word) {
        currentWord = word
        phase = .idle
        feedbackMessage = ""
        readAlongPassed = false
    }

    /// User tapped "跟读" button - directly start reading the word (no activation prompt)
    func beginReadAlong() {
        speakWord()
    }

    // MARK: - Word Reading

    private func speakWord() {
        guard let word = currentWord else { return }
        phase = .aiSpeakingWord
        speechRecognizer.setLocale(Constants.Speech.englishLocale)
        tts.speak(word.spelling) { [weak self] in
            DispatchQueue.main.async {
                self?.phase = .waitingStudentReadWord
                self?.feedbackMessage = "请跟读: \(word.spelling)"
            }
        }
    }

    func startListeningWord() {
        phase = .listeningWord
        speechRecognizer.recognizedText = ""
        do {
            try speechRecognizer.startRecording()
        } catch {
            feedbackMessage = "录音失败"
            phase = .waitingStudentReadWord
        }
    }

    func stopAndEvaluateWord() {
        speechRecognizer.stopRecording()
        guard let word = currentWord else { return }

        let passed = evaluatePronunciationStrict(expected: word.spelling, recognized: speechRecognizer.recognizedText)

        if passed {
            phase = .wordPassed
            feedbackMessage = "发音很标准!"
            tts.speak("Well done! You said it perfectly!") { [weak self] in
                DispatchQueue.main.async {
                    self?.moveToSentences()
                }
            }
        } else {
            // Must keep retrying - AI re-reads the word first
            phase = .wordFailed
            feedbackMessage = "没关系，再听一遍，你可以的"
            tts.speak("Almost there! Listen one more time.") { [weak self] in
                DispatchQueue.main.async {
                    guard let self, case .wordFailed = self.phase else { return }
                    // Re-read the word for the student
                    self.tts.speak(word.spelling) { [weak self] in
                        DispatchQueue.main.async {
                            guard let self, case .wordFailed = self.phase else { return }
                            self.phase = .waitingStudentReadWord
                            self.feedbackMessage = "请跟读: \(word.spelling)"
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sentence Reading

    private func moveToSentences() {
        if currentSentences.isEmpty {
            completeReadAlong()
            return
        }
        speakSentence(at: 0)
    }

    private func speakSentence(at index: Int) {
        guard index < currentSentences.count else {
            completeReadAlong()
            return
        }
        phase = .aiSpeakingSentence(index: index)
        tts.speak(currentSentences[index].english) { [weak self] in
            DispatchQueue.main.async {
                self?.phase = .waitingStudentReadSentence(index: index)
                self?.feedbackMessage = "请跟读这个例句"
            }
        }
    }

    func startListeningSentence(at index: Int) {
        phase = .listeningSentence(index: index)
        speechRecognizer.recognizedText = ""
        do {
            try speechRecognizer.startRecording()
        } catch {
            feedbackMessage = "录音失败"
            phase = .waitingStudentReadSentence(index: index)
        }
    }

    func stopAndEvaluateSentence(at index: Int) {
        speechRecognizer.stopRecording()
        let sentence = currentSentences[index].english
        let passed = evaluatePronunciationStrict(expected: sentence, recognized: speechRecognizer.recognizedText)

        if passed {
            phase = .sentencePassed(index: index)
            feedbackMessage = "读得很标准!"
            tts.speak("Wonderful! That was great!") { [weak self] in
                DispatchQueue.main.async {
                    self?.speakSentence(at: index + 1)
                }
            }
        } else {
            // Must keep retrying - AI re-reads the sentence first
            phase = .sentenceFailed(index: index)
            feedbackMessage = "没关系，再听一遍，你可以的"
            tts.speak("You're doing great! Listen one more time.") { [weak self] in
                DispatchQueue.main.async {
                    guard let self, case .sentenceFailed(let idx) = self.phase else { return }
                    // Re-read the sentence for the student
                    self.tts.speak(self.currentSentences[idx].english) { [weak self] in
                        DispatchQueue.main.async {
                            guard let self, case .sentenceFailed(let idx) = self.phase else { return }
                            self.phase = .waitingStudentReadSentence(index: idx)
                            self.feedbackMessage = "请跟读这个例句"
                        }
                    }
                }
            }
        }
    }

    // MARK: - Complete

    private func completeReadAlong() {
        readAlongPassed = true
        phase = .readAlongComplete
        feedbackMessage = "你真厉害! 跟读全部通过!"
        tts.speak("Amazing! You did a wonderful job!", rate: 0.38) {}
    }

    func markAsMastered(modelContext: ModelContext) {
        guard let word = currentWord else { return }
        word.isMastered = true
        word.masteredAt = Date()

        let record = LearningRecord(date: Date())
        record.pronunciationPassed = true
        record.spellingPassed = true
        record.word = word
        modelContext.insert(record)
    }

    // MARK: - Pronunciation Evaluation

    func evaluatePronunciationStrict(expected: String, recognized: String) -> Bool {
        let normalizedExpected = expected
            .lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespaces)

        let normalizedRecognized = recognized
            .lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespaces)

        if normalizedRecognized.isEmpty { return false }

        // Compare with all spaces removed (handles "schoolbag" vs "school bag")
        let expectedNoSpaces = normalizedExpected.replacingOccurrences(of: " ", with: "")
        let recognizedNoSpaces = normalizedRecognized.replacingOccurrences(of: " ", with: "")

        // Single word: match with and without spaces
        if normalizedExpected.split(separator: " ").count == 1 {
            return recognizedNoSpaces == expectedNoSpaces ||
                   normalizedRecognized.split(separator: " ").contains(where: { String($0) == normalizedExpected })
        }

        // Sentence: 90% word match, also tolerant of compound word splits
        let expectedWords = normalizedExpected.split(separator: " ").map(String.init)
        let recognizedWords = normalizedRecognized.split(separator: " ").map(String.init)
        let expectedSet = Set(expectedWords)
        let recognizedSet = Set(recognizedWords)

        // Direct word match
        var matchCount = expectedSet.intersection(recognizedSet).count

        // For unmatched expected words, check if they appear as joined/split forms in recognized text
        let unmatched = expectedSet.subtracting(recognizedSet)
        for word in unmatched {
            if recognizedNoSpaces.contains(word) {
                matchCount += 1
            }
        }

        let matchRate = Double(matchCount) / Double(expectedSet.count)
        return matchRate >= 0.9
    }
}
