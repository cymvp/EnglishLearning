import SwiftUI

struct AIChatView: View {
    let word: String
    let meaning: String
    @Environment(\.dismiss) private var dismiss
    @State private var vm = ChatViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Chat messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(vm.messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }

                            if !vm.streamingText.isEmpty {
                                ChatBubble(message: ChatMessage(role: "assistant", content: vm.streamingText))
                            }

                            if vm.isLoading && vm.streamingText.isEmpty {
                                HStack {
                                    ProgressView()
                                    Text("AI 正在思考...")
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                            }
                        }
                        .padding()
                    }
                    .onChange(of: vm.messages.count) { _, _ in
                        if let last = vm.messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Input bar
                HStack(spacing: 12) {
                    TextField("输入你的问题...", text: $vm.inputText)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)

                    Button {
                        vm.sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty || vm.isLoading)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("关于 \"\(word)\"")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                vm.setup(word: word, meaning: meaning)
            }
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer() }

            VStack(alignment: isUser ? .trailing : .leading) {
                Text(message.content)
                    .font(.body)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isUser ? Color.blue : Color(.systemGray5))
                    )
                    .foregroundStyle(isUser ? .white : .primary)
            }
            .frame(maxWidth: 500, alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer() }
        }
    }
}
