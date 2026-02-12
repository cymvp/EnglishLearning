import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - AI Service Protocol

protocol AIServiceProtocol: Sendable {
    func lookupWord(_ spelling: String) async throws -> WordLookupResult
    func generateSentences(for word: String, meaning: String) async throws -> [SentenceResult]
    func chat(messages: [ChatMessage], systemPrompt: String) async throws -> String
    func chatStream(messages: [ChatMessage], systemPrompt: String) -> AsyncThrowingStream<String, Error>
    func recognizeWords(from image: UIImage) async throws -> [RecognizedWord]
}

// MARK: - Factory

enum AIServiceFactory {

    /// Create a service for the learning scenario based on user settings.
    static func learningService() -> (any AIServiceProtocol)? {
        switch AppSettings.learningProvider {
        case .claude:
            guard let key = KeychainService.getAPIKey(for: .claude), !key.isEmpty else { return nil }
            return ClaudeAPIService(apiKey: key, model: AppSettings.learningClaudeModel.rawValue)
        case .openai:
            guard let key = KeychainService.getAPIKey(for: .openai), !key.isEmpty else { return nil }
            return OpenAIAPIService(apiKey: key, model: AppSettings.learningOpenAIModel.rawValue)
        }
    }

    /// Create a service for the chat scenario (text API, not Realtime).
    static func chatService() -> (any AIServiceProtocol)? {
        switch AppSettings.chatProvider {
        case .claude:
            guard let key = KeychainService.getAPIKey(for: .claude), !key.isEmpty else { return nil }
            return ClaudeAPIService(apiKey: key, model: AppSettings.chatClaudeModel.rawValue)
        case .openai:
            guard let key = KeychainService.getAPIKey(for: .openai), !key.isEmpty else { return nil }
            return OpenAIAPIService(apiKey: key, model: "gpt-4o")
        }
    }

    /// Whether the chat scenario should use OpenAI Realtime (WebSocket voice).
    static var chatUsesRealtime: Bool {
        AppSettings.chatProvider == .openai
    }

    /// User-friendly error message when API key is missing.
    static func apiKeyMissingMessage(for provider: AIProvider) -> String {
        switch provider {
        case .claude: return "请先在设置中配置 Claude API Key"
        case .openai: return "请先在设置中配置 OpenAI API Key"
        }
    }
}
