import SwiftUI
import SwiftData

struct WordListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Word.spelling) private var words: [Word]
    @State private var showAddWord = false
    @State private var showPhotoCapture = false

    /// Group words by their first letter (uppercased)
    private var groupedWords: [(letter: String, words: [Word])] {
        let dict = Dictionary(grouping: words) { word -> String in
            let first = word.spelling.prefix(1).uppercased()
            return first.isEmpty ? "#" : first
        }
        return dict.sorted { $0.key < $1.key }
            .map { (letter: $0.key, words: $0.value) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    ContentUnavailableView {
                        Label("还没有单词", systemImage: "book.closed")
                    } description: {
                        Text("点击右上角的 + 按钮添加单词，或者拍照识别单词")
                    }
                } else {
                    List {
                        ForEach(groupedWords, id: \.letter) { group in
                            Section(header: Text(group.letter).font(.title2.bold())) {
                                ForEach(group.words) { word in
                                    NavigationLink(value: word) {
                                        WordRowView(word: word)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            modelContext.delete(word)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }

                                        if word.isMastered {
                                            Button {
                                                word.isMastered = false
                                                word.masteredAt = nil
                                            } label: {
                                                Label("重置", systemImage: "arrow.counterclockwise")
                                            }
                                            .tint(.orange)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("单词本 (\(words.count))")
            .navigationDestination(for: Word.self) { word in
                WordCardView(initialWord: word)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showAddWord = true
                        } label: {
                            Label("手动添加", systemImage: "plus")
                        }
                        Button {
                            showPhotoCapture = true
                        } label: {
                            Label("拍照识别", systemImage: "camera")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showAddWord) {
                AddWordView()
            }
            .sheet(isPresented: $showPhotoCapture) {
                PhotoCaptureView()
            }
        }
    }
}
