import SwiftUI

struct DictionarySearchView: View {
    @State private var searchText = ""
    @State private var lookupResult: WordLookupResult?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var tts = SpeechSynthesizerService()

    // Voice chat state
    @State private var isVoiceChatActive = false
    @State private var isListeningChat = false
    @State private var chatMessages: [ChatMessage] = []
    @State private var chatFeedback = ""
    private let chatRecognizer = SpeechRecognizerService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    TextField("输入要查的单词", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.title3)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )

                    Button {
                        lookupWord()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
                .padding()

                if isLoading {
                    Spacer()
                    ProgressView("查询中...")
                        .font(.title3)
                    Spacer()
                } else if let result = lookupResult {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Word info
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(result.spelling)
                                        .font(.system(size: 40, weight: .bold, design: .rounded))
                                    SpeakButton(text: result.spelling, tts: tts)
                                }
                                Text(result.phonetic)
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text(result.chineseMeaning)
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                            }
                            .padding()

                            // Sentences
                            VStack(alignment: .leading, spacing: 12) {
                                Text("例句")
                                    .font(.headline)
                                ForEach(Array(result.sentences.enumerated()), id: \.offset) { idx, sentence in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("\(idx + 1). \(sentence.english)")
                                                .font(.body)
                                            Spacer()
                                            SpeakButton(text: sentence.english, tts: tts)
                                                .controlSize(.small)
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
                                }
                            }
                            .padding(.horizontal)

                            // Voice chat button
                            Button {
                                toggleVoiceChat()
                            } label: {
                                HStack {
                                    Label(
                                        isVoiceChatActive ? "结束聊天" : "向 AI 提问",
                                        systemImage: isVoiceChatActive ? "stop.circle.fill" : "bubble.left.and.bubble.right.fill"
                                    )
                                    .font(.title3)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(isVoiceChatActive ? .red : .purple)
                            .padding(.horizontal)

                            // Voice chat area
                            if isVoiceChatActive {
                                VStack(spacing: 12) {
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
                                .padding(.horizontal)
                            }

                            // Chat messages
                            if isVoiceChatActive && !chatMessages.isEmpty {
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
                        }
                    }
                } else if let error = errorMessage {
                    Spacer()
                    ContentUnavailableView {
                        Label("查询失败", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    }
                    Spacer()
                } else {
                    Spacer()
                    ContentUnavailableView {
                        Label("查单词", systemImage: "character.book.closed")
                    } description: {
                        Text("输入英语单词，查看释义、音标和例句")
                    }
                    Spacer()
                }
            }
            .navigationTitle("查词")
            .onDisappear {
                tts.stop()
                if isListeningChat {
                    chatRecognizer.stopRecording()
                    isListeningChat = false
                }
            }
        }
    }

    // MARK: - Lookup

    private func lookupWord() {
        let word = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !word.isEmpty else { return }

        guard let apiKey = KeychainService.getAPIKey() else {
            errorMessage = "请先在设置中配置 Claude API Key"
            return
        }

        // Stop voice chat when searching a new word
        if isVoiceChatActive { toggleVoiceChat() }

        isLoading = true
        errorMessage = nil
        lookupResult = nil

        Task {
            do {
                let service = ClaudeAPIService(apiKey: apiKey)
                lookupResult = try await service.lookupWord(word)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - Voice Chat

    private func toggleVoiceChat() {
        if isVoiceChatActive {
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

        guard let result = lookupResult else { return }

        chatMessages.append(ChatMessage(role: "user", content: userText))
        chatFeedback = ""

        guard let apiKey = KeychainService.getAPIKey() else {
            chatFeedback = "请先配置 API Key"
            return
        }

        let systemPrompt = """
        You are a friendly English teacher helping a 4th grade student learn the word "\(result.spelling)" (\(result.chineseMeaning)).
        You can understand both Chinese and English questions from the student.
        You MUST always respond in simple English only, using words a 10-year-old can understand.
        Only answer questions about this word. If asked about unrelated topics, gently redirect.
        Keep answers under 30 words since they will be spoken aloud.
        """

        Task {
            do {
                let service = ClaudeAPIService(apiKey: apiKey)
                let reply = try await service.chat(messages: chatMessages, systemPrompt: systemPrompt)
                chatMessages.append(ChatMessage(role: "assistant", content: reply))
                tts.speak(reply, rate: 0.45) {}
            } catch {
                chatMessages.append(ChatMessage(role: "assistant", content: "Sorry, something went wrong."))
            }
        }
    }
}
