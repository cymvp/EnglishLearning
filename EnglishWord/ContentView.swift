import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("单词本", systemImage: "book.fill") {
                WordListView()
            }
            Tab("测评", systemImage: "checkmark.circle.fill") {
                ExamHomeView()
            }
            Tab("查词", systemImage: "magnifyingglass") {
                DictionarySearchView()
            }
            Tab("聊天", systemImage: "bubble.left.and.bubble.right.fill") {
                FreeChatView()
            }
            Tab("统计", systemImage: "chart.bar.fill") {
                StatisticsHomeView()
            }
            Tab("设置", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
