import SwiftUI

enum FreeChatState {
    case idle           // Not started
    case listening      // Recording user speech
    case processing     // Sending to AI
    case aiSpeaking     // AI is speaking response
}

struct FreeChatView: View {
    @State private var chatState: FreeChatState = .idle
    @State private var messages: [ChatMessage] = []
    @State private var currentUserText = ""
    @State private var errorMessage = ""

    // Claude mode
    private let tts = SpeechSynthesizerService()
    private let recognizer = SpeechRecognizerService(locale: Constants.Speech.chineseLocale)
    @State private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 2.0

    // OpenAI Realtime mode
    @State private var realtimeService = OpenAIRealtimeService()
    @State private var realtimeTranscript = ""  // Current AI transcript being streamed

    private var usesRealtime: Bool {
        AIServiceFactory.chatUsesRealtime
    }

    private var providerLabel: String {
        AppSettings.chatProvider == .openai ? "OpenAI Realtime" : "Claude"
    }

    private var systemPrompt: String {
        var prompt = """
        You are a warm, friendly English teacher chatting with a Chinese elementary school student (4th-6th grade).
        The student may speak in Chinese or English.
        You should respond in simple English, but you can mix in a little Chinese when needed to help the student understand.
        Be encouraging, patient, and fun. Use short sentences (under 40 words) since your response will be spoken aloud.
        You can talk about anything related to English learning, school life, hobbies, or help the student practice English conversation.
        If the student seems shy, ask them fun questions to keep the conversation going.
        """

        let summary = ChatHistoryService.loadTodaySummary()
        if !summary.isEmpty {
            prompt += "\n\nHere is a summary of your earlier conversation today with this student:\n\(summary)\nContinue naturally from this context."
        }

        return prompt
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Chat messages area
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { msg in
                                chatBubble(msg)
                                    .id(msg.id)
                            }

                            // Real-time user speech (Claude mode)
                            if !usesRealtime && chatState == .listening && !recognizer.recognizedText.isEmpty {
                                realTimeUserBubble(text: recognizer.recognizedText)
                            }

                            // Real-time AI transcript (Realtime mode)
                            if usesRealtime && !realtimeTranscript.isEmpty {
                                realTimeAIBubble(text: realtimeTranscript)
                            }

                            // AI thinking indicator (Claude mode)
                            if !usesRealtime && chatState == .processing {
                                HStack {
                                    ProgressView()
                                    Text("AI 正在思考...")
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .id("thinking")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: recognizer.recognizedText) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: realtimeTranscript) { _, _ in
                        scrollToBottom(proxy)
                    }
                }

                Divider()

                // Bottom control area
                bottomBar
            }
            .navigationTitle("聊天")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("聊天 (\(providerLabel))")
                        .font(.headline)
                }
            }
            .onAppear {
                loadTodayHistory()
            }
            .onDisappear {
                stopConversation()
            }
        }
    }

    // MARK: - Chat Bubble

    private func chatBubble(_ msg: ChatMessage) -> some View {
        let isUser = msg.role == "user"
        return HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            if !isUser {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.purple)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.purple.opacity(0.15)))
            }

            Text(msg.content)
                .font(.body)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isUser ? Color.blue : Color(.systemGray5))
                )
                .foregroundStyle(isUser ? .white : .primary)

            if isUser {
                Image(systemName: "person.fill")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.blue.opacity(0.15)))
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    private func realTimeUserBubble(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Spacer(minLength: 60)

            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .foregroundStyle(.white.opacity(0.7))
                    .symbolEffect(.variableColor.iterative, isActive: true)
                Text(text)
                    .font(.body)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.blue.opacity(0.7))
            )
            .foregroundStyle(.white)

            Image(systemName: "person.fill")
                .font(.subheadline)
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.blue.opacity(0.15)))
        }
        .id("realtime-user")
    }

    private func realTimeAIBubble(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(.purple)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.purple.opacity(0.15)))

            HStack(spacing: 6) {
                Text(text)
                    .font(.body)
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.purple.opacity(0.7))
                    .symbolEffect(.variableColor.iterative, isActive: true)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray5))
            )
            .foregroundStyle(.primary)

            Spacer(minLength: 60)
        }
        .id("realtime-ai")
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // State indicator
            stateIndicator

            // Main action buttons
            actionButtons
        }
        .padding()
        .background(.bar)
    }

    private var stateIndicator: some View {
        HStack(spacing: 8) {
            if usesRealtime {
                // Realtime mode indicators
                if !realtimeService.isConnected {
                    Image(systemName: "mic.slash")
                        .foregroundStyle(.secondary)
                    Text("点击下方按钮开始对话")
                        .foregroundStyle(.secondary)
                } else if realtimeService.isAISpeaking {
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.purple)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                    Text("AI 正在说话，点击打断...")
                        .foregroundStyle(.purple)
                } else {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.green)
                        .symbolEffect(.pulse, isActive: true)
                    Text("正在聆听... (自动检测)")
                        .foregroundStyle(.green)
                }
            } else {
                // Claude mode indicators
                switch chatState {
                case .idle:
                    Image(systemName: "mic.slash")
                        .foregroundStyle(.secondary)
                    Text("点击下方按钮开始对话")
                        .foregroundStyle(.secondary)
                case .listening:
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse, isActive: true)
                    Text("正在听你说话...")
                        .foregroundStyle(.blue)
                case .processing:
                    Image(systemName: "brain")
                        .foregroundStyle(.purple)
                        .symbolEffect(.pulse, isActive: true)
                    Text("AI 正在回复...")
                        .foregroundStyle(.purple)
                case .aiSpeaking:
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.purple)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                    Text("AI 正在说话，点击打断...")
                        .foregroundStyle(.purple)
                }
            }
        }
        .font(.subheadline)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if usesRealtime {
                // Realtime mode buttons
                if !realtimeService.isConnected {
                    Button {
                        startRealtimeConversation()
                    } label: {
                        Label("开始对话", systemImage: "mic.circle.fill")
                            .font(.title3)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                } else if realtimeService.isAISpeaking {
                    Button {
                        realtimeService.interrupt()
                    } label: {
                        Label("打断", systemImage: "hand.raised.fill")
                            .font(.title3)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button {
                        stopConversation()
                    } label: {
                        Label("结束", systemImage: "stop.circle.fill")
                            .font(.title3)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        stopConversation()
                    } label: {
                        Label("结束对话", systemImage: "stop.circle.fill")
                            .font(.title3)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            } else {
                // Claude mode buttons
                if chatState == .idle {
                    Button {
                        startClaudeConversation()
                    } label: {
                        Label("开始对话", systemImage: "mic.circle.fill")
                            .font(.title3)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                } else if chatState == .aiSpeaking {
                    Button {
                        handleInterruption()
                    } label: {
                        Label("打断", systemImage: "hand.raised.fill")
                            .font(.title3)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button {
                        stopConversation()
                    } label: {
                        Label("结束", systemImage: "stop.circle.fill")
                            .font(.title3)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        stopConversation()
                    } label: {
                        Label("结束对话", systemImage: "stop.circle.fill")
                            .font(.title3)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
    }

    // MARK: - Realtime Conversation Control

    private func startRealtimeConversation() {
        errorMessage = ""

        // Set up callbacks
        realtimeService.onAIResponseComplete = { transcript in
            messages.append(ChatMessage(role: "assistant", content: transcript))
            realtimeTranscript = ""
        }

        realtimeService.onUserSpeechDetected = { transcript in
            messages.append(ChatMessage(role: "user", content: transcript))
        }

        // Observe realtime transcript changes
        realtimeTranscript = ""

        realtimeService.connect(systemPrompt: systemPrompt)

        // Track transcript via polling (since @Observable properties update)
        startTranscriptPolling()
    }

    @State private var transcriptTimer: Timer?

    private func startTranscriptPolling() {
        transcriptTimer?.invalidate()
        transcriptTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                realtimeTranscript = realtimeService.currentTranscript
                if !realtimeService.errorMessage.isEmpty && errorMessage != realtimeService.errorMessage {
                    errorMessage = realtimeService.errorMessage
                }
            }
        }
    }

    // MARK: - Claude Conversation Control

    private func startClaudeConversation() {
        guard KeychainService.getAPIKey(for: .claude) != nil else {
            errorMessage = "请先在设置中配置 Claude API Key"
            return
        }

        errorMessage = ""

        recognizer.onTextChanged = { [self] in
            resetSilenceTimer()
        }

        if messages.isEmpty {
            chatState = .aiSpeaking
            let greeting = "Hi there! I'm happy to chat with you. What would you like to talk about?"
            messages.append(ChatMessage(role: "assistant", content: greeting))
            tts.speak(greeting) {
                DispatchQueue.main.async {
                    guard self.chatState == .aiSpeaking else { return }
                    self.startListening()
                }
            }
        } else {
            chatState = .listening
            startListening()
        }
    }

    private func stopConversation() {
        if usesRealtime {
            transcriptTimer?.invalidate()
            transcriptTimer = nil
            realtimeService.disconnect()
            realtimeTranscript = ""
        } else {
            silenceTimer?.invalidate()
            silenceTimer = nil
            recognizer.onTextChanged = nil
            recognizer.stopRecording()
            tts.stop()
            chatState = .idle
        }

        // Save today's chat history
        if !messages.isEmpty {
            ChatHistoryService.saveTodayMessages(messages)
        }
    }

    // MARK: - Listening (Claude mode)

    private func startListening() {
        guard chatState != .idle else { return }
        chatState = .listening
        recognizer.recognizedText = ""
        currentUserText = ""
        do {
            try recognizer.startRecording()
            startSilenceTimer(timeout: 30.0)
        } catch {
            errorMessage = "录音启动失败"
            chatState = .idle
        }
    }

    private func handleInterruption() {
        guard chatState == .aiSpeaking else { return }
        tts.stop()
        startListening()
    }

    // MARK: - Silence Detection (Claude mode)

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        guard !recognizer.recognizedText.isEmpty else { return }
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { _ in
            DispatchQueue.main.async {
                self.onSilenceDetected()
            }
        }
    }

    private func startSilenceTimer(timeout: TimeInterval) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            DispatchQueue.main.async {
                self.onSilenceDetected()
            }
        }
    }

    private func onSilenceDetected() {
        guard chatState == .listening else { return }

        recognizer.stopRecording()
        let userText = recognizer.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !userText.isEmpty else {
            startListening()
            return
        }

        messages.append(ChatMessage(role: "user", content: userText))
        currentUserText = ""

        sendToClaudeAI()
    }

    // MARK: - AI Communication (Claude mode)

    private func sendToClaudeAI() {
        chatState = .processing

        guard let service = AIServiceFactory.chatService() else {
            errorMessage = AIServiceFactory.apiKeyMissingMessage(for: AppSettings.chatProvider)
            chatState = .idle
            return
        }

        Task {
            do {
                let reply = try await service.chat(messages: messages, systemPrompt: systemPrompt)

                await MainActor.run {
                    messages.append(ChatMessage(role: "assistant", content: reply))
                    chatState = .aiSpeaking

                    tts.speak(reply, rate: 0.42) {
                        DispatchQueue.main.async {
                            guard self.chatState == .aiSpeaking else { return }
                            self.startListening()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    messages.append(ChatMessage(role: "assistant", content: "Sorry, I had a little problem. Let's try again!"))
                    errorMessage = error.localizedDescription

                    chatState = .aiSpeaking
                    tts.speak("Sorry, let me try again.") {
                        DispatchQueue.main.async {
                            guard self.chatState == .aiSpeaking else { return }
                            self.startListening()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Chat History

    private func loadTodayHistory() {
        let history = ChatHistoryService.loadTodayMessages()
        if !history.isEmpty {
            messages = history
        }
    }

    // MARK: - Helpers

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = messages.last {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
