import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    // Claude API Key
    @State private var claudeApiKey: String = ""
    @State private var showClaudeKey = false
    @State private var claudeSavedSuccessfully = false

    // OpenAI API Key
    @State private var openaiApiKey: String = ""
    @State private var showOpenAIKey = false
    @State private var openaiSavedSuccessfully = false

    // Learning scenario
    @State private var learningProvider: AIProvider = AppSettings.learningProvider
    @State private var learningClaudeModel: ClaudeModelOption = AppSettings.learningClaudeModel
    @State private var learningOpenAIModel: OpenAIModelOption = AppSettings.learningOpenAIModel
    @State private var thinkingMode: ThinkingMode = AppSettings.thinkingMode

    // Chat scenario
    @State private var chatProvider: AIProvider = AppSettings.chatProvider
    @State private var chatClaudeModel: ClaudeModelOption = AppSettings.chatClaudeModel
    @State private var chatRealtimeModel: OpenAIRealtimeModel = AppSettings.chatRealtimeModel
    @State private var chatVoice: OpenAIVoice = AppSettings.chatVoice

    // Word pack state
    @State private var selectedPack: String = AppSettings.selectedWordPack
    @State private var pendingPack: String = ""
    @State private var showPackConfirmation = false
    @State private var packService = WordPackService()
    @State private var availablePacks: [WordPackInfo] = []
    @State private var suppressPackChange = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Claude API Key
                Section {
                    apiKeyField(
                        key: $claudeApiKey,
                        showKey: $showClaudeKey,
                        placeholder: "sk-ant-...",
                        provider: .claude
                    )
                } header: {
                    Text("Claude API Key")
                } footer: {
                    Text("Anthropic Claude 的 API Key，用于学习和聊天场景。")
                }

                // MARK: - OpenAI API Key
                Section {
                    apiKeyField(
                        key: $openaiApiKey,
                        showKey: $showOpenAIKey,
                        placeholder: "sk-...",
                        provider: .openai
                    )
                } header: {
                    Text("OpenAI API Key")
                } footer: {
                    Text("OpenAI 的 API Key，用于学习和聊天（Realtime 语音）场景。")
                }

                // MARK: - Learning Scenario
                Section {
                    Picker("服务商", selection: $learningProvider) {
                        ForEach(AIProvider.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }

                    if learningProvider == .claude {
                        Picker("Claude 模型", selection: $learningClaudeModel) {
                            ForEach(ClaudeModelOption.allCases) { model in
                                Text(model.displayName).tag(model)
                            }
                        }

                        Picker("思考模式", selection: $thinkingMode) {
                            ForEach(ThinkingMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                    } else {
                        Picker("OpenAI 模型", selection: $learningOpenAIModel) {
                            ForEach(OpenAIModelOption.allCases) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                    }
                } header: {
                    Text("学习场景（查词、例句、OCR、问答）")
                } footer: {
                    if learningProvider == .claude {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Haiku: 速度最快，费用最低，适合日常使用")
                            Text("Sonnet: 速度和质量均衡，推荐使用")
                            Text("Opus: 质量最高，速度较慢，费用最高")
                            Text("")
                            Text("快思考: 普通模式，响应快")
                            Text("慢思考: 深度推理模式，回答更准确但更慢")
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("GPT-5.2: 最新最强模型")
                            Text("GPT-5 mini: 速度和质量均衡，推荐使用")
                            Text("GPT-4o: 经典模型，稳定可靠")
                            Text("GPT-4o mini: 速度最快，费用最低")
                        }
                    }
                }

                // MARK: - Chat Scenario
                Section {
                    Picker("服务商", selection: $chatProvider) {
                        ForEach(AIProvider.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }

                    if chatProvider == .claude {
                        Picker("Claude 模型", selection: $chatClaudeModel) {
                            ForEach(ClaudeModelOption.allCases) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                    } else {
                        Picker("Realtime 模型", selection: $chatRealtimeModel) {
                            ForEach(OpenAIRealtimeModel.allCases) { model in
                                Text(model.displayName).tag(model)
                            }
                        }

                        Picker("语音", selection: $chatVoice) {
                            ForEach(OpenAIVoice.allCases) { voice in
                                Text(voice.displayName).tag(voice)
                            }
                        }
                    }
                } header: {
                    Text("聊天场景（自由对话）")
                } footer: {
                    if chatProvider == .openai {
                        Text("OpenAI Realtime 模式：直接通过 WebSocket 进行语音对话，延迟更低，体验更自然。服务端自动检测语音和静音。")
                    } else {
                        Text("Claude 模式：使用语音识别 → Claude API → 语音合成的流程。")
                    }
                }

                // MARK: - Word Pack
                Section {
                    if availablePacks.isEmpty {
                        Text("未找到预置词库文件")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("词库", selection: $selectedPack) {
                            Text("无").tag("")
                            ForEach(availablePacks) { pack in
                                Text("\(pack.name) (\(pack.wordCount) 词)").tag(pack.name)
                            }
                        }
                    }

                    if packService.isLoading {
                        HStack {
                            ProgressView()
                            Text("正在导入词库... \(packService.progress)/\(packService.totalToImport)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = packService.errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("预置词库")
                } footer: {
                    Text("选择词库后会导入对应的单词和例句。切换词库时，之前词库的单词会被移除（手动添加和拍照识别的单词不受影响）。")
                }
            }
            .navigationTitle("设置")
            .alert("保存成功", isPresented: $claudeSavedSuccessfully) {
                Button("好的") {}
            } message: {
                Text("Claude API Key 已安全保存")
            }
            .alert("保存成功", isPresented: $openaiSavedSuccessfully) {
                Button("好的") {}
            } message: {
                Text("OpenAI API Key 已安全保存")
            }
            .onAppear {
                if let key = KeychainService.getAPIKey(for: .claude) { claudeApiKey = key }
                if let key = KeychainService.getAPIKey(for: .openai) { openaiApiKey = key }
                learningProvider = AppSettings.learningProvider
                learningClaudeModel = AppSettings.learningClaudeModel
                learningOpenAIModel = AppSettings.learningOpenAIModel
                thinkingMode = AppSettings.thinkingMode
                chatProvider = AppSettings.chatProvider
                chatClaudeModel = AppSettings.chatClaudeModel
                chatRealtimeModel = AppSettings.chatRealtimeModel
                chatVoice = AppSettings.chatVoice
                availablePacks = WordPackService.availablePacks()
                selectedPack = AppSettings.selectedWordPack
            }
            .onChange(of: learningProvider) { _, newValue in AppSettings.learningProvider = newValue }
            .onChange(of: learningClaudeModel) { _, newValue in AppSettings.learningClaudeModel = newValue }
            .onChange(of: learningOpenAIModel) { _, newValue in AppSettings.learningOpenAIModel = newValue }
            .onChange(of: thinkingMode) { _, newValue in AppSettings.thinkingMode = newValue }
            .onChange(of: chatProvider) { _, newValue in AppSettings.chatProvider = newValue }
            .onChange(of: chatClaudeModel) { _, newValue in AppSettings.chatClaudeModel = newValue }
            .onChange(of: chatRealtimeModel) { _, newValue in AppSettings.chatRealtimeModel = newValue }
            .onChange(of: chatVoice) { _, newValue in AppSettings.chatVoice = newValue }
            .onChange(of: selectedPack) { oldValue, newValue in
                guard oldValue != newValue, !suppressPackChange else {
                    suppressPackChange = false
                    return
                }
                pendingPack = newValue
                suppressPackChange = true
                selectedPack = oldValue
                showPackConfirmation = true
            }
            .confirmationDialog(
                "切换词库",
                isPresented: $showPackConfirmation,
                titleVisibility: .visible
            ) {
                Button("确认切换", role: .destructive) {
                    let target = pendingPack
                    suppressPackChange = true
                    selectedPack = target
                    Task {
                        await packService.switchPack(to: target, modelContext: modelContext)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                if pendingPack.isEmpty {
                    Text("将移除当前词库(\(AppSettings.selectedWordPack))的所有单词及学习记录。手动添加的单词不受影响。")
                } else if AppSettings.selectedWordPack.isEmpty {
                    Text("将导入 \(pendingPack) 词库的单词和例句。")
                } else {
                    Text("将移除 \(AppSettings.selectedWordPack) 词库的单词，并导入 \(pendingPack) 词库。手动添加的单词不受影响。")
                }
            }
        }
    }

    // MARK: - Reusable API Key Field

    @ViewBuilder
    private func apiKeyField(
        key: Binding<String>,
        showKey: Binding<Bool>,
        placeholder: String,
        provider: AIProvider
    ) -> some View {
        HStack {
            if showKey.wrappedValue {
                TextField(placeholder, text: key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
            } else {
                SecureField(placeholder, text: key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Button {
                showKey.wrappedValue.toggle()
            } label: {
                Image(systemName: showKey.wrappedValue ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
        }

        Button("保存 API Key") {
            if KeychainService.save(apiKey: key.wrappedValue, for: provider) {
                switch provider {
                case .claude: claudeSavedSuccessfully = true
                case .openai: openaiSavedSuccessfully = true
                }
            }
        }
        .disabled(key.wrappedValue.isEmpty)

        if KeychainService.getAPIKey(for: provider) != nil {
            Button("删除 API Key", role: .destructive) {
                _ = KeychainService.deleteAPIKey(for: provider)
                key.wrappedValue = ""
            }
        }
    }
}
