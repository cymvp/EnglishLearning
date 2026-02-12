import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var apiKey: String = ""
    @State private var showKey = false
    @State private var savedSuccessfully = false
    @State private var selectedModel: ClaudeModelOption = AppSettings.selectedModel
    @State private var thinkingMode: ThinkingMode = AppSettings.thinkingMode

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
                // API Key
                Section {
                    HStack {
                        if showKey {
                            TextField("sk-ant-...", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("sk-ant-...", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("保存 API Key") {
                        if KeychainService.save(apiKey: apiKey) {
                            savedSuccessfully = true
                        }
                    }
                    .disabled(apiKey.isEmpty)

                    if KeychainService.getAPIKey() != nil {
                        Button("删除 API Key", role: .destructive) {
                            _ = KeychainService.deleteAPIKey()
                            apiKey = ""
                        }
                    }
                } header: {
                    Text("Claude API Key")
                } footer: {
                    Text("API Key 安全存储在设备 Keychain 中。请让家长来设置。")
                }

                // Model Selection
                Section {
                    Picker("AI 模型", selection: $selectedModel) {
                        ForEach(ClaudeModelOption.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }

                    Picker("思考模式", selection: $thinkingMode) {
                        ForEach(ThinkingMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                } header: {
                    Text("AI 模型设置")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Haiku: 速度最快，费用最低，适合日常使用")
                        Text("Sonnet: 速度和质量均衡，推荐使用")
                        Text("Opus: 质量最高，速度较慢，费用最高")
                        Text("")
                        Text("快思考: 普通模式，响应快")
                        Text("慢思考: 深度推理模式，回答更准确但更慢")
                    }
                }

                // Word Pack
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
            .alert("保存成功", isPresented: $savedSuccessfully) {
                Button("好的") {}
            } message: {
                Text("API Key 已安全保存")
            }
            .onAppear {
                if let key = KeychainService.getAPIKey() {
                    apiKey = key
                }
                selectedModel = AppSettings.selectedModel
                thinkingMode = AppSettings.thinkingMode
                availablePacks = WordPackService.availablePacks()
                selectedPack = AppSettings.selectedWordPack
            }
            .onChange(of: selectedModel) { _, newValue in
                AppSettings.selectedModel = newValue
            }
            .onChange(of: thinkingMode) { _, newValue in
                AppSettings.thinkingMode = newValue
            }
            .onChange(of: selectedPack) { oldValue, newValue in
                guard oldValue != newValue, !suppressPackChange else {
                    suppressPackChange = false
                    return
                }
                pendingPack = newValue
                suppressPackChange = true
                selectedPack = oldValue  // Revert until confirmed
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
}
