import SwiftUI
import SwiftData

struct AddWordView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var spelling = ""
    @State private var isLoading = false
    @State private var showDuplicateAlert = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "character.textbox")
                    .font(.system(size: 50))
                    .foregroundStyle(.blue)

                Text("输入英文单词")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                TextField("例如: apple", text: $spelling)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 28, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.blue, lineWidth: 2)
                    )
                    .padding(.horizontal, 40)

                Text("AI 会自动补全音标、中文释义和例句")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if isLoading {
                    ProgressView("AI 正在查询...")
                        .font(.title3)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .navigationTitle("添加单词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") { addWord() }
                        .disabled(spelling.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
            }
            .alert("单词已存在", isPresented: $showDuplicateAlert) {
                Button("好的") {}
            } message: {
                Text("\(spelling) 已经在单词本里了")
            }
        }
    }

    private func addWord() {
        let normalized = spelling.lowercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return }

        // Check duplicate
        let descriptor = FetchDescriptor<Word>(
            predicate: #Predicate { $0.spelling == normalized }
        )
        if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty {
            showDuplicateAlert = true
            return
        }

        guard let apiKey = KeychainService.getAPIKey(), !apiKey.isEmpty else {
            errorMessage = "请先在设置中配置 Claude API Key"
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let service = ClaudeAPIService(apiKey: apiKey)
                let result = try await service.lookupWord(normalized)

                let word = Word(
                    spelling: result.spelling.lowercased(),
                    phonetic: result.phonetic,
                    chineseMeaning: result.chineseMeaning,
                    source: "manual"
                )
                modelContext.insert(word)

                for s in result.sentences {
                    let sentence = ExampleSentence(english: s.english, chinese: s.chinese)
                    sentence.word = word
                    modelContext.insert(sentence)
                }

                try modelContext.save()
                dismiss()
            } catch {
                errorMessage = "查询失败: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}
