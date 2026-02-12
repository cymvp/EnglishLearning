import SwiftUI
import SwiftData

struct LearningHomeView: View {
    @Query(
        filter: #Predicate<Word> { !$0.isMastered },
        sort: \Word.spelling
    ) private var unlearnedWords: [Word]

    @Query(
        filter: #Predicate<Word> { $0.isMastered },
        sort: \Word.spelling
    ) private var masteredWords: [Word]

    @State private var selectedWord: Word?
    @State private var showLearning = false

    var body: some View {
        NavigationStack {
            Group {
                if unlearnedWords.isEmpty && masteredWords.isEmpty {
                    ContentUnavailableView {
                        Label("还没有单词", systemImage: "book.closed")
                    } description: {
                        Text("请先在单词本中添加单词")
                    }
                } else {
                    List {
                        if !unlearnedWords.isEmpty {
                            Section("未学习 (\(unlearnedWords.count))") {
                                ForEach(unlearnedWords) { word in
                                    Button {
                                        selectedWord = word
                                        showLearning = true
                                    } label: {
                                        WordRowView(word: word)
                                    }
                                    .tint(.primary)
                                }
                            }
                        }

                        if !masteredWords.isEmpty {
                            Section("已学会 (\(masteredWords.count))") {
                                ForEach(masteredWords) { word in
                                    Button {
                                        selectedWord = word
                                        showLearning = true
                                    } label: {
                                        WordRowView(word: word)
                                    }
                                    .tint(.primary)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("学习")
            .navigationDestination(isPresented: $showLearning) {
                if let word = selectedWord {
                    WordCardView(initialWord: word)
                }
            }
        }
    }
}
