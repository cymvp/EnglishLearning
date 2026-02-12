import SwiftUI

struct SentencePracticeView: View {
    let word: Word

    @Environment(\.dismiss) private var dismiss

    // Phase
    enum Phase {
        case idle, recording, evaluating, result
    }
    @State private var phase: Phase = .idle

    // Recognition & evaluation
    @State private var recognizedSentence = ""
    @State private var isNatural = false
    @State private var feedback = ""
    @State private var betterExpression = ""
    @State private var errorMessage = ""

    // Services
    private let recognizer = SpeechRecognizerService()
    private let tts = SpeechSynthesizerService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Prompt
                    Text("请用 \(word.spelling) 造一个英文句子")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .padding(.top)

                    // Record button
                    if phase == .idle || phase == .recording {
                        RecordButton(isRecording: phase == .recording) {
                            if phase == .recording {
                                stopRecording()
                            } else {
                                startRecording()
                            }
                        }

                        Text(phase == .recording ? "点击停止录音" : "点击开始录音")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Recognized sentence card
                    if !recognizedSentence.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("你的句子")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text(recognizedSentence)
                                .font(.title3)

                            if phase == .evaluating {
                                HStack {
                                    ProgressView()
                                    Text("正在评判...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                        .padding(.horizontal)
                    }

                    // Error message
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    // Result cards
                    if phase == .result {
                        if isNatural {
                            // Natural expression - green card
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.title2)
                                Text(feedback)
                                    .font(.body)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.green.opacity(0.1))
                            )
                            .padding(.horizontal)
                        } else {
                            // Not natural - orange feedback
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.title2)
                                Text(feedback)
                                    .font(.body)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.orange.opacity(0.1))
                            )
                            .padding(.horizontal)

                            // Better expression - blue card
                            if !betterExpression.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("更好的表达")
                                        .font(.headline)
                                        .foregroundStyle(.blue)
                                    HStack {
                                        Text(betterExpression)
                                            .font(.title3)
                                        Spacer()
                                        SpeakButton(text: betterExpression, tts: tts)
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.blue.opacity(0.1))
                                )
                                .padding(.horizontal)
                            }
                        }

                        // Retry button
                        Button {
                            reset()
                        } label: {
                            Label("再试一次", systemImage: "arrow.counterclockwise")
                                .font(.title3)
                                .padding()
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("用 \(word.spelling) 造句")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        recognizer.stopRecording()
                        tts.stop()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Recording

    private func startRecording() {
        recognizedSentence = ""
        errorMessage = ""
        recognizer.setLocale(Constants.Speech.englishLocale)
        recognizer.recognizedText = ""
        do {
            try recognizer.startRecording()
            phase = .recording
        } catch {
            errorMessage = "录音失败: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        recognizer.stopRecording()
        recognizedSentence = recognizer.recognizedText
        guard !recognizedSentence.isEmpty else {
            errorMessage = "没有听到你说什么，请再试一次"
            phase = .idle
            return
        }
        phase = .evaluating
        evaluateSentence()
    }

    // MARK: - AI Evaluation

    private func evaluateSentence() {
        guard let service = AIServiceFactory.learningService() else {
            errorMessage = AIServiceFactory.apiKeyMissingMessage(for: AppSettings.learningProvider)
            phase = .idle
            return
        }

        let systemPrompt = """
        You are an English language expert. A student is learning the word "\(word.spelling)" (\(word.chineseMeaning)).
        They made this sentence: "\(recognizedSentence)"

        Evaluate if this sentence uses natural, native-like English and correctly uses the word "\(word.spelling)".
        Respond ONLY in valid JSON (no markdown, no extra text):
        {"isNatural": true, "feedback": "中文反馈(1-2句)", "betterExpression": ""}
        or
        {"isNatural": false, "feedback": "中文反馈(1-2句)", "betterExpression": "a more natural English sentence"}
        """

        let messages = [ChatMessage(role: "user", content: recognizedSentence)]
        Task {
            do {
                let reply = try await service.chat(messages: messages, systemPrompt: systemPrompt)
                parseEvaluation(reply)
            } catch {
                await MainActor.run {
                    errorMessage = "评判失败: \(error.localizedDescription)"
                    phase = .idle
                }
            }
        }
    }

    private func parseEvaluation(_ text: String) {
        // Try to extract JSON from the response
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences
        if let start = jsonString.range(of: "```json") {
            jsonString = String(jsonString[start.upperBound...])
        } else if let start = jsonString.range(of: "```") {
            jsonString = String(jsonString[start.upperBound...])
        }
        if let end = jsonString.range(of: "```", options: .backwards) {
            jsonString = String(jsonString[..<end.lowerBound])
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON object
        if let braceStart = jsonString.firstIndex(of: "{"),
           let braceEnd = jsonString.lastIndex(of: "}") {
            jsonString = String(jsonString[braceStart...braceEnd])
        }

        guard let data = jsonString.data(using: .utf8) else {
            errorMessage = "解析失败"
            phase = .idle
            return
        }

        struct EvalResult: Decodable {
            let isNatural: Bool
            let feedback: String
            let betterExpression: String
        }

        do {
            let result = try JSONDecoder().decode(EvalResult.self, from: data)
            isNatural = result.isNatural
            feedback = result.feedback
            betterExpression = result.betterExpression
            phase = .result
        } catch {
            errorMessage = "解析失败，请重试"
            phase = .idle
        }
    }

    // MARK: - Reset

    private func reset() {
        phase = .idle
        recognizedSentence = ""
        isNatural = false
        feedback = ""
        betterExpression = ""
        errorMessage = ""
    }
}
