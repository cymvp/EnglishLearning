import SwiftUI
import SwiftData

struct ReadAlongView: View {
    let word: Word
    var onComplete: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var vm = LearningViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Status bar
                Text(vm.statusText)
                    .font(.title2.bold())
                    .foregroundStyle(.blue)
                    .multilineTextAlignment(.center)
                    .padding(.top)

                Spacer()

                // Main content area
                mainContent

                // Recognized text
                if !vm.speechRecognizer.recognizedText.isEmpty {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundStyle(.blue)
                        Text(vm.speechRecognizer.recognizedText)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray6))
                    )
                    .padding(.horizontal)
                }

                // Feedback message
                if !vm.feedbackMessage.isEmpty {
                    Text(vm.feedbackMessage)
                        .font(.title3)
                        .foregroundStyle(feedbackColor)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(feedbackColor.opacity(0.1))
                        )
                        .padding(.horizontal)
                }

                Spacer()

                // Action area
                actionArea

                Spacer()
            }
            .padding()
            .navigationTitle("跟读")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("退出") {
                        vm.tts.stop()
                        vm.speechRecognizer.stopRecording()
                        onComplete(vm.readAlongPassed)
                        dismiss()
                    }
                }
            }
            .onAppear {
                vm.setup(word: word)
                // Directly start reading the word (no activation prompt)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    vm.beginReadAlong()
                }
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 20) {
            // Always show the word during read-along
            Text(word.spelling)
                .font(.system(size: 56, weight: .bold, design: .rounded))

            if !word.phonetic.isEmpty {
                Text(word.phonetic)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            Text(word.chineseMeaning)
                .font(.title2)
                .foregroundStyle(.blue)

            // Show current sentence
            if let idx = currentSentenceIndex, idx < word.sentences.count {
                Divider().padding(.vertical, 4)
                VStack(spacing: 6) {
                    Text(word.sentences[idx].english)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                    Text(word.sentences[idx].chinese)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Action Area

    @ViewBuilder
    private var actionArea: some View {
        switch vm.phase {
        case .idle:
            ProgressView()
                .scaleEffect(1.5)

        case .aiSpeakingWord, .aiSpeakingSentence, .wordFailed, .sentenceFailed:
            // AI is speaking (or re-reading after failure)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 50))
                .foregroundStyle(.blue)
                .symbolEffect(.variableColor.iterative, isActive: true)

        case .waitingStudentReadWord:
            RecordButton(isRecording: false) {
                vm.startListeningWord()
            }

        case .listeningWord:
            RecordButton(isRecording: true) {
                vm.stopAndEvaluateWord()
            }

        case .waitingStudentReadSentence:
            RecordButton(isRecording: false) {
                if let idx = currentSentenceIndex {
                    vm.startListeningSentence(at: idx)
                }
            }

        case .listeningSentence:
            RecordButton(isRecording: true) {
                if let idx = currentSentenceIndex {
                    vm.stopAndEvaluateSentence(at: idx)
                }
            }

        case .wordPassed, .sentencePassed:
            ProgressView()
                .scaleEffect(1.5)

        case .readAlongComplete:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.green)

                Button {
                    onComplete(true)
                    dismiss()
                } label: {
                    Text("完成")
                        .font(.title3)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

        case .voiceChat:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private var currentSentenceIndex: Int? {
        switch vm.phase {
        case .aiSpeakingSentence(let idx): return idx
        case .waitingStudentReadSentence(let idx): return idx
        case .listeningSentence(let idx): return idx
        case .sentenceFailed(let idx): return idx
        case .sentencePassed(let idx): return idx
        default: return nil
        }
    }

    private var feedbackColor: Color {
        switch vm.phase {
        case .wordPassed, .sentencePassed, .readAlongComplete:
            return .green
        case .wordFailed, .sentenceFailed:
            return .orange
        default:
            return .blue
        }
    }
}
