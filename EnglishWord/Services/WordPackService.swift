import Foundation
import SwiftData

struct PackWordEntry: Codable {
    let spelling: String
    let phonetic: String
    let chineseMeaning: String
    let sentences: [PackSentenceEntry]
}

struct PackSentenceEntry: Codable {
    let english: String
    let chinese: String
}

struct WordPackInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let wordCount: Int
}

@Observable
@MainActor
final class WordPackService {
    var isLoading = false
    var progress: Int = 0
    var totalToImport: Int = 0
    var errorMessage: String?

    /// Discover all available word pack JSON files from the app bundle.
    static func availablePacks() -> [WordPackInfo] {
        var allURLs: [URL] = []

        // Try multiple possible subdirectory paths
        let subdirs = ["WordPacks", "Resources/WordPacks", "Resources"]
        for subdir in subdirs {
            if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: subdir) {
                allURLs.append(contentsOf: urls)
            }
            if !allURLs.isEmpty { break }
        }

        // Fallback: search bundle root
        if allURLs.isEmpty {
            if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) {
                allURLs.append(contentsOf: urls)
            }
        }

        // Filter: only include files that are valid word pack arrays
        return allURLs.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: url),
                  let words = try? JSONDecoder().decode([PackWordEntry].self, from: data) else {
                return nil
            }
            return WordPackInfo(id: name, name: name, url: url, wordCount: words.count)
        }
        .sorted { $0.name < $1.name }
    }

    /// Switch from the current pack to a new one.
    func switchPack(to newPack: String, modelContext: ModelContext) async {
        let oldPack = AppSettings.selectedWordPack

        guard newPack != oldPack else { return }

        isLoading = true
        progress = 0
        errorMessage = nil

        // Step 1: Remove old pack words
        if !oldPack.isEmpty {
            removePackWords(packName: oldPack, modelContext: modelContext)
        }

        // Step 2: Import new pack words
        if !newPack.isEmpty {
            importPack(packName: newPack, modelContext: modelContext)
        }

        // Step 3: Update setting
        AppSettings.selectedWordPack = newPack

        // Step 4: Save context
        try? modelContext.save()

        isLoading = false
    }

    private func removePackWords(packName: String, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Word>(
            predicate: #Predicate<Word> { $0.source == packName }
        )
        guard let wordsToRemove = try? modelContext.fetch(descriptor) else { return }

        for word in wordsToRemove {
            modelContext.delete(word)
        }
    }

    private func importPack(packName: String, modelContext: ModelContext) {
        // Try multiple subdirectory paths
        let url = Bundle.main.url(forResource: packName, withExtension: "json", subdirectory: "WordPacks")
            ?? Bundle.main.url(forResource: packName, withExtension: "json", subdirectory: "Resources/WordPacks")
            ?? Bundle.main.url(forResource: packName, withExtension: "json", subdirectory: "Resources")
            ?? Bundle.main.url(forResource: packName, withExtension: "json")

        guard let url else {
            errorMessage = "找不到词库文件: \(packName).json"
            return
        }

        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "无法读取词库文件"
            return
        }

        guard let entries = try? JSONDecoder().decode([PackWordEntry].self, from: data) else {
            errorMessage = "词库文件格式错误"
            return
        }

        totalToImport = entries.count
        progress = 0

        for entry in entries {
            let normalized = entry.spelling.lowercased().trimmingCharacters(in: .whitespaces)

            let descriptor = FetchDescriptor<Word>(
                predicate: #Predicate<Word> { $0.spelling == normalized }
            )

            if let existingWords = try? modelContext.fetch(descriptor),
               let existingWord = existingWords.first {
                let src = existingWord.source
                if src.isEmpty || src == "manual" || src == "ocr" {
                    // User's word takes priority, skip
                    progress += 1
                    continue
                }
                // Update existing pack word
                existingWord.phonetic = entry.phonetic
                existingWord.chineseMeaning = entry.chineseMeaning
                existingWord.source = packName
                for sentence in existingWord.sentences {
                    modelContext.delete(sentence)
                }
                for s in entry.sentences {
                    let sentence = ExampleSentence(english: s.english, chinese: s.chinese)
                    sentence.word = existingWord
                    modelContext.insert(sentence)
                }
            } else {
                let word = Word(
                    spelling: normalized,
                    phonetic: entry.phonetic,
                    chineseMeaning: entry.chineseMeaning,
                    source: packName
                )
                modelContext.insert(word)

                for s in entry.sentences {
                    let sentence = ExampleSentence(english: s.english, chinese: s.chinese)
                    sentence.word = word
                    modelContext.insert(sentence)
                }
            }

            progress += 1
        }
    }
}
