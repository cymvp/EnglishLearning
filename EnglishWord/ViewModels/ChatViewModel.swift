import Foundation

@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isLoading: Bool = false
    var streamingText: String = ""

    private var currentWord: String = ""
    private var currentMeaning: String = ""

    var systemPrompt: String {
        """
        You are a friendly English teacher helping a 4th grade student learn the word "\(currentWord)" (\(currentMeaning)).
        You can understand both Chinese and English questions from the student.
        You MUST always respond in simple English only, using words a 10-year-old can understand.
        Only answer questions related to this word (other meanings, movies/cartoons it appears in, similar words, synonyms, antonyms, etc.)
        If the student asks about unrelated topics, gently bring the conversation back to the word.
        Keep answers under 50 words.
        """
    }

    func setup(word: String, meaning: String) {
        currentWord = word
        currentMeaning = meaning
        messages = []
        inputText = ""
        streamingText = ""

        messages.append(ChatMessage(
            role: "assistant",
            content: "你好！我们正在学习单词 \"\(word)\"（\(meaning)）。你有什么想问的吗？"
        ))
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        messages.append(ChatMessage(role: "user", content: text))
        inputText = ""
        isLoading = true
        streamingText = ""

        guard let apiKey = KeychainService.getAPIKey() else {
            messages.append(ChatMessage(role: "assistant", content: "请先在设置中配置 API Key"))
            isLoading = false
            return
        }

        let service = ClaudeAPIService(apiKey: apiKey)
        // Only send user messages for API call (filter out initial greeting)
        let apiMessages = messages.filter { $0.role == "user" || ($0.role == "assistant" && messages.firstIndex(where: { $0.id == $0.id }) != nil) }

        Task { @MainActor in
            do {
                let stream = service.chatStream(messages: apiMessages, systemPrompt: systemPrompt)
                for try await chunk in stream {
                    streamingText += chunk
                }
                messages.append(ChatMessage(role: "assistant", content: streamingText))
                streamingText = ""
            } catch {
                messages.append(ChatMessage(role: "assistant", content: "出错了：\(error.localizedDescription)"))
            }
            isLoading = false
        }
    }
}
