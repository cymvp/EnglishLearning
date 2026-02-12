import SwiftUI
import SwiftData

struct RecognizedWord: Identifiable, Codable {
    var id = UUID()
    var spelling: String
    var phonetic: String
    var chinese: String
    var selected: Bool = true

    enum CodingKeys: String, CodingKey {
        case spelling, phonetic, chinese
    }
}

struct OCRResultView: View {
    let image: UIImage
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var recognizedWords: [RecognizedWord] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var batchService = BatchSentenceService()
    @State private var showBatchProgress = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("AI 正在识别单词...")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("识别失败", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重试") {
                            Task { await recognizeWords() }
                        }
                    }
                } else if recognizedWords.isEmpty {
                    ContentUnavailableView {
                        Label("未识别到单词", systemImage: "text.magnifyingglass")
                    } description: {
                        Text("请重新拍照或手动添加单词")
                    }
                } else {
                    List {
                        Section("识别结果（点击取消选择）") {
                            ForEach($recognizedWords) { $word in
                                HStack {
                                    Image(systemName: word.selected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(word.selected ? .blue : .secondary)
                                        .font(.title3)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(word.spelling)
                                            .font(.title3.bold())
                                        HStack {
                                            if !word.phonetic.isEmpty {
                                                Text(word.phonetic)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Text(word.chinese)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    word.selected.toggle()
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("识别结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(showBatchProgress)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加选中") { addSelectedWords() }
                        .disabled(recognizedWords.filter(\.selected).isEmpty || showBatchProgress)
                }
            }
            .task {
                await recognizeWords()
            }
            .overlay {
                if showBatchProgress {
                    VStack(spacing: 20) {
                        if batchService.isProcessing {
                            ProgressView(value: Double(batchService.completedCount),
                                         total: max(Double(batchService.totalCount), 1))
                                .progressViewStyle(.linear)
                                .padding(.horizontal, 40)
                            Text(batchService.progressText)
                                .font(.title3)
                            Text("请稍候，正在批量生成例句...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(.green)
                            let successCount = batchService.completedCount - batchService.failedCount
                            Text("完成! 已为 \(successCount) 个单词生成例句")
                                .font(.title3)
                            if batchService.failedCount > 0 {
                                Text("\(batchService.failedCount) 个单词生成失败，可在学习时重试")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                            }
                            Button("完成") { dismiss() }
                                .buttonStyle(.borderedProminent)
                                .padding(.top)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                }
            }
        }
    }

    private func recognizeWords() async {
        isLoading = true
        errorMessage = nil

        guard let service = AIServiceFactory.learningService() else {
            errorMessage = AIServiceFactory.apiKeyMissingMessage(for: AppSettings.learningProvider)
            isLoading = false
            return
        }

        do {
            recognizedWords = try await service.recognizeWords(from: image)
            isLoading = false
        } catch {
            errorMessage = "识别出错：\(error.localizedDescription)"
            isLoading = false
        }
    }

    private func addSelectedWords() {
        let selected = recognizedWords.filter(\.selected)
        var insertedWords: [(spelling: String, meaning: String, modelID: PersistentIdentifier)] = []

        for rw in selected {
            let normalized = rw.spelling.lowercased().trimmingCharacters(in: .whitespaces)
            let descriptor = FetchDescriptor<Word>(
                predicate: #Predicate { $0.spelling == normalized }
            )
            if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty {
                continue
            }
            let word = Word(spelling: normalized, phonetic: rw.phonetic, chineseMeaning: rw.chinese, source: "ocr")
            modelContext.insert(word)
            insertedWords.append((normalized, rw.chinese, word.persistentModelID))
        }

        if insertedWords.isEmpty {
            dismiss()
            return
        }

        // Start batch sentence generation
        showBatchProgress = true
        Task {
            await batchService.generateSentencesForAll(
                words: insertedWords,
                modelContext: modelContext
            )
        }
    }
}
