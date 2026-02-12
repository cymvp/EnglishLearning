import SwiftUI
import SwiftData

struct WordCardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Word.spelling) private var allWords: [Word]
    @State private var currentIndex: Int = 0
    @State private var showReadAlong = false
    @State private var isLoadingSentences = false

    // Learning state for current word
    @State private var readAlongPassed = false
    @State private var spellingPassed = false
    @State private var isTestingSpelling = false
    @State private var spellingInput = ""
    @State private var spellingFeedback = ""

    // Voice chat state
    @State private var isVoiceChatActive = false
    @State private var isListeningChat = false
    @State private var chatMessages: [ChatMessage] = []
    @State private var chatFeedback = ""

    let initialWord: Word
    let tts = SpeechSynthesizerService()
    private let chatRecognizer = SpeechRecognizerService()

    private var currentWord: Word? {
        guard currentIndex >= 0, currentIndex < allWords.count else { return nil }
        return allWords[currentIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            if let word = currentWord {
                ScrollView {
                    VStack(spacing: 24) {
                        // Status badges
                        statusBadges

                        // Word Card
                        wordCard(word: word)

                        // Sentences
                        sentencesSection(word: word)

                        // Action Buttons
                        actionButtons(word: word)

                        // Voice chat messages
                        if isVoiceChatActive && !chatMessages.isEmpty {
                            chatMessagesView
                        }
                    }
                    .padding(.vertical)
                }

                // Bottom navigation
                navigationBar
            }
        }
        .navigationTitle("学习单词")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let idx = allWords.firstIndex(where: { $0.id == initialWord.id }) ?? 0
            if idx == currentIndex {
                // Index unchanged, onChange won't fire, so load directly
                loadLearningState()
                loadSentencesIfNeeded()
            } else {
                currentIndex = idx  // This triggers onChange
            }
        }
        .onChange(of: currentIndex) { _, _ in
            resetLearningState()
            loadLearningState()
            loadSentencesIfNeeded()
        }
        .onDisappear {
            tts.stop()
            if isListeningChat {
                chatRecognizer.stopRecording()
                isListeningChat = false
            }
        }
        .sheet(isPresented: $showReadAlong) {
            if let word = currentWord {
                ReadAlongView(word: word, onComplete: { passed in
                    if passed {
                        readAlongPassed = true
                        checkAndMarkMastered()
                    }
                })
            }
        }
    }

    // MARK: - Status Badges

    private var statusBadges: some View {
        HStack(spacing: 16) {
            Label(
                readAlongPassed ? "跟读通过" : "跟读未完成",
                systemImage: readAlongPassed ? "checkmark.circle.fill" : "circle"
            )
            .foregroundStyle(readAlongPassed ? .green : .secondary)

            Label(
                spellingPassed ? "测评通过" : "测评未完成",
                systemImage: spellingPassed ? "checkmark.circle.fill" : "circle"
            )
            .foregroundStyle(spellingPassed ? .green : .secondary)
        }
        .font(.subheadline)
        .padding(.horizontal)
    }

    // MARK: - Word Card

    private func wordCard(word: Word) -> some View {
        VStack(spacing: 16) {
            if isTestingSpelling {
                Text("???")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(word.spelling)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    SpeakButton(text: word.spelling, tts: tts)
                }
            }

            if !word.phonetic.isEmpty && !isTestingSpelling {
                Text(word.phonetic)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            Text(word.chineseMeaning)
                .font(.title2)
                .foregroundStyle(.blue)

            if word.isMastered {
                Label("已学会", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            }

            // Spelling input field (during test)
            if isTestingSpelling {
                VStack(spacing: 12) {
                    TextField("请输入这个单词", text: $spellingInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 28, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.blue, lineWidth: 2)
                        )
                        .padding(.horizontal, 20)

                    if !spellingFeedback.isEmpty {
                        Text(spellingFeedback)
                            .font(.body)
                            .foregroundStyle(spellingPassed ? .green : .red)
                    }

                    HStack(spacing: 16) {
                        Button("确认") {
                            submitSpelling(word: word)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(spellingInput.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button("取消") {
                            isTestingSpelling = false
                            spellingInput = ""
                            spellingFeedback = ""
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(radius: 4, y: 2)
        )
        .padding(.horizontal)
    }

    // MARK: - Sentences

    private func sentencesSection(word: Word) -> some View {
        Group {
            if !word.sentences.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("例句")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(Array(word.sentences.enumerated()), id: \.offset) { idx, sentence in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(idx + 1). \(maskedSentence(sentence.english, hiding: word.spelling))")
                                    .font(.body)
                                Spacer()
                                if !isTestingSpelling {
                                    SpeakButton(text: sentence.english, tts: tts)
                                        .controlSize(.small)
                                }
                            }
                            Text(sentence.chinese)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                        .padding(.horizontal)
                    }
                }
            } else if isLoadingSentences {
                ProgressView("正在生成例句...")
                    .padding()
            }
        }
    }

    // MARK: - Action Buttons

    private func actionButtons(word: Word) -> some View {
        VStack(spacing: 12) {
            // 跟读 button
            Button {
                showReadAlong = true
            } label: {
                HStack {
                    Label("跟读", systemImage: "mic.fill")
                        .font(.title3)
                    if readAlongPassed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(readAlongPassed ? .green : .blue)

            // 测评 button
            Button {
                isTestingSpelling = true
                spellingInput = ""
                spellingFeedback = ""
            } label: {
                HStack {
                    Label("测评", systemImage: "pencil.line")
                        .font(.title3)
                    if spellingPassed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(spellingPassed ? .green : .orange)
            .disabled(isTestingSpelling)

            // 聊天 button (toggle voice chat)
            Button {
                toggleVoiceChat()
            } label: {
                HStack {
                    Label(
                        isVoiceChatActive ? "结束聊天" : "聊天",
                        systemImage: isVoiceChatActive ? "stop.circle.fill" : "bubble.left.and.bubble.right.fill"
                    )
                    .font(.title3)
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isVoiceChatActive ? .red : .purple)

            // Voice chat recording area
            if isVoiceChatActive {
                VStack(spacing: 8) {
                    RecordButton(isRecording: isListeningChat) {
                        if isListeningChat {
                            stopChatListening()
                        } else {
                            startChatListening()
                        }
                    }

                    if !chatFeedback.isEmpty {
                        Text(chatFeedback)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("点击录音，再点击发送")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Chat Messages View

    private var chatMessagesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("对话记录")
                .font(.headline)
                .padding(.horizontal)

            ForEach(chatMessages) { msg in
                HStack {
                    if msg.role == "user" { Spacer() }
                    Text(msg.content)
                        .font(.body)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(msg.role == "user" ? Color.blue : Color(.systemGray5))
                        )
                        .foregroundStyle(msg.role == "user" ? .white : .primary)
                    if msg.role != "user" { Spacer() }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Navigation

    private var navigationBar: some View {
        HStack {
            Button {
                if currentIndex > 0 { currentIndex -= 1 }
            } label: {
                Label("上一个", systemImage: "chevron.left")
                    .font(.title3)
                    .padding()
            }
            .disabled(currentIndex <= 0)

            Spacer()

            Text("\(currentIndex + 1) / \(allWords.count)")
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                if currentIndex < allWords.count - 1 { currentIndex += 1 }
            } label: {
                Label("下一个", systemImage: "chevron.right")
                    .font(.title3)
                    .padding()
            }
            .disabled(currentIndex >= allWords.count - 1)
        }
        .padding(.horizontal)
        .background(.bar)
    }

    // MARK: - Voice Chat

    private func toggleVoiceChat() {
        if isVoiceChatActive {
            // Stop voice chat
            if isListeningChat {
                chatRecognizer.stopRecording()
                isListeningChat = false
            }
            tts.stop()
            isVoiceChatActive = false
            chatMessages = []
            chatFeedback = ""
        } else {
            isVoiceChatActive = true
            chatMessages = []
            chatFeedback = ""
        }
    }

    private func startChatListening() {
        isListeningChat = true
        chatRecognizer.setLocale(Constants.Speech.chineseLocale)
        chatRecognizer.recognizedText = ""
        do {
            try chatRecognizer.startRecording()
        } catch {
            isListeningChat = false
            chatFeedback = "录音失败"
        }
    }

    private func stopChatListening() {
        chatRecognizer.stopRecording()
        isListeningChat = false

        let userText = chatRecognizer.recognizedText
        guard !userText.isEmpty else {
            chatFeedback = "没有听到你说什么"
            return
        }

        chatMessages.append(ChatMessage(role: "user", content: userText))
        chatFeedback = ""

        guard let word = currentWord else { return }
        guard let service = AIServiceFactory.learningService() else {
            chatFeedback = AIServiceFactory.apiKeyMissingMessage(for: AppSettings.learningProvider)
            return
        }

        let systemPrompt = """
        You are a friendly English teacher helping a 4th grade student learn the word "\(word.spelling)" (\(word.chineseMeaning)).
        You can understand both Chinese and English questions from the student.
        You MUST always respond in simple English only, using words a 10-year-old can understand.
        Only answer questions about this word. If asked about unrelated topics, gently redirect.
        Keep answers under 30 words since they will be spoken aloud.
        """

        Task {
            do {
                let reply = try await service.chat(messages: chatMessages, systemPrompt: systemPrompt)
                chatMessages.append(ChatMessage(role: "assistant", content: reply))
                tts.speak(reply, rate: 0.45) {}
            } catch {
                chatMessages.append(ChatMessage(role: "assistant", content: "Sorry, something went wrong."))
            }
        }
    }

    // MARK: - Logic

    private func maskedSentence(_ sentence: String, hiding word: String) -> String {
        guard isTestingSpelling else { return sentence }
        let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        let blank = String(repeating: "_", count: word.count)
        return sentence.replacingOccurrences(of: pattern, with: blank, options: .regularExpression)
    }

    private func submitSpelling(word: Word) {
        let normalized = spellingInput.lowercased().trimmingCharacters(in: .whitespaces)
        if normalized == word.spelling.lowercased() {
            spellingPassed = true
            spellingFeedback = "太棒了! 拼写完全正确!"
            isTestingSpelling = false
            spellingInput = ""
            checkAndMarkMastered()
        } else {
            spellingFeedback = "还差一点点，再试试看"
            spellingInput = ""
        }
    }

    private func checkAndMarkMastered() {
        guard let word = currentWord, readAlongPassed && spellingPassed else { return }
        guard !word.isMastered else { return }
        word.isMastered = true
        word.masteredAt = Date()
        let record = LearningRecord(date: Date())
        record.pronunciationPassed = true
        record.spellingPassed = true
        record.word = word
        modelContext.insert(record)
    }

    private func loadLearningState() {
        guard let word = currentWord else { return }
        // If the word is already mastered, show both as passed
        if word.isMastered {
            readAlongPassed = true
            spellingPassed = true
        }
    }

    private func resetLearningState() {
        readAlongPassed = false
        spellingPassed = false
        isTestingSpelling = false
        spellingInput = ""
        spellingFeedback = ""
        // Stop voice chat when switching words
        if isVoiceChatActive {
            toggleVoiceChat()
        }
    }

    private func loadSentencesIfNeeded() {
        guard let word = currentWord, word.sentences.isEmpty else { return }
        guard !isLoadingSentences else { return }  // Prevent duplicate calls
        guard let service = AIServiceFactory.learningService() else { return }

        isLoadingSentences = true
        let wordId = word.persistentModelID
        Task {
            do {
                let results = try await service.generateSentences(for: word.spelling, meaning: word.chineseMeaning)
                // Double-check the word hasn't changed and sentences weren't already added
                if let current = currentWord,
                   current.persistentModelID == wordId,
                   current.sentences.isEmpty {
                    for result in results {
                        let sentence = ExampleSentence(english: result.english, chinese: result.chinese)
                        sentence.word = current
                        modelContext.insert(sentence)
                    }
                }
            } catch {
                // Silently fail
            }
            isLoadingSentences = false
        }
    }
}
