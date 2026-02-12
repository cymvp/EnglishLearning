import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct SentenceResult: Codable {
    let english: String
    let chinese: String
}

struct WordLookupResult: Decodable {
    let spelling: String
    let phonetic: String
    let chineseMeaning: String
    let sentences: [SentenceResult]

    enum CodingKeys: String, CodingKey {
        case spelling, phonetic, sentences
        case chineseMeaning = "chineseMeaning"
        case chineseMeaningSnake = "chinese_meaning"
        case meaning
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spelling = try container.decode(String.self, forKey: .spelling)
        phonetic = try container.decode(String.self, forKey: .phonetic)
        sentences = try container.decode([SentenceResult].self, forKey: .sentences)
        // Try multiple possible key names for Chinese meaning
        if let value = try? container.decode(String.self, forKey: .chineseMeaning) {
            chineseMeaning = value
        } else if let value = try? container.decode(String.self, forKey: .chineseMeaningSnake) {
            chineseMeaning = value
        } else if let value = try? container.decode(String.self, forKey: .meaning) {
            chineseMeaning = value
        } else {
            chineseMeaning = ""
        }
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String
    let content: String
}

final class ClaudeAPIService: Sendable {
    private let apiKey: String
    private let baseURL = Constants.claudeBaseURL
    private let apiVersion = Constants.claudeAPIVersion

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Get the user-selected model ID
    private var selectedModel: String {
        AppSettings.selectedModel.rawValue
    }

    /// Whether extended thinking is enabled
    private var isExtendedThinking: Bool {
        AppSettings.thinkingMode == .slow
    }

    // MARK: - OCR

    func recognizeWords(from image: UIImage) async throws -> [RecognizedWord] {
        // Resize image to max 1024px on longest side to reduce payload size
        let resized = resizeImage(image, maxDimension: 1024)
        guard let imageData = resized.jpegData(compressionQuality: 0.6) else {
            throw ClaudeError.invalidImage
        }
        let base64 = imageData.base64EncodedString()

        let systemPrompt = """
        你是一个小学英语老师。请从图片中识别适合小学4-6年级学生学习的英语单词。
        注意：
        - 忽略人名（如 Alex, Tom）、标点、数字
        - 忽略太简单的词（如 a, the, is, I, you, he, she, it, and, or, to, in, on, at, of, do, did, no, yes）
        - 只保留有学习价值的词汇（名词、动词、形容词、副词等）
        - 相同的词只出现一次
        为每个单词提供：
        1. spelling（拼写，全小写）
        2. phonetic（国际音标，用斜杠包裹如 /wɜːrd/）
        3. chinese（简短中文释义，适合小学生理解）
        只返回纯 JSON 数组，不要返回任何其他文字、解释或 markdown 格式。
        """

        let body = makeRequestBody(
            maxTokens: 4096,
            system: systemPrompt,
            messages: [
                .init(role: "user", content: [
                    .init(type: "image", source: .init(
                        type: "base64",
                        media_type: "image/jpeg",
                        data: base64
                    )),
                    .init(type: "text", text: "请识别图片中适合小学生学习的英语单词。")
                ])
            ]
        )

        let responseText = try await sendRequest(body: body, timeout: 60)
        return try parseJSON(responseText)
    }

    /// Resize image to fit within maxDimension while keeping aspect ratio
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return image }

        let scale = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Generate Sentences

    func generateSentences(for word: String, meaning: String) async throws -> [SentenceResult] {
        let systemPrompt = """
        你是一个小学四年级英语老师。请为以下单词生成3个适合小学生的简单英文例句。
        要求：
        1. 句子简短，使用常见词汇
        2. 每句不超过10个单词
        3. 内容贴近小学生生活
        4. 同时提供中文翻译
        只返回纯 JSON 数组：[{"english": "...", "chinese": "..."}]
        不要返回任何其他文字、解释或 markdown 格式。
        """

        let body = makeRequestBody(
            maxTokens: 1024,
            system: systemPrompt,
            messages: [
                .init(role: "user", content: [
                    .init(type: "text", text: "单词: \(word), 释义: \(meaning)")
                ])
            ]
        )

        let responseText = try await sendRequest(body: body)
        return try parseJSON(responseText)
    }

    // MARK: - Word Lookup

    func lookupWord(_ spelling: String) async throws -> WordLookupResult {
        let systemPrompt = """
        你是一个英语词典助手，服务对象是小学四年级学生。
        只返回纯 JSON，不要任何其他文字、解释或 markdown 格式。
        JSON 格式如下：
        {"spelling":"单词","phonetic":"/音标/","chineseMeaning":"中文释义","sentences":[{"english":"例句","chinese":"翻译"}]}
        提供3个适合小学生的简单例句。
        """

        let body = makeRequestBody(
            maxTokens: 1024,
            system: systemPrompt,
            messages: [
                .init(role: "user", content: [
                    .init(type: "text", text: "请查询单词: \(spelling)")
                ])
            ]
        )

        let responseText = try await sendRequest(body: body)
        return try parseJSON(responseText)
    }

    // MARK: - Chat (non-streaming)

    func chat(messages: [ChatMessage], systemPrompt: String) async throws -> String {
        let body = makeRequestBody(
            maxTokens: 1024,
            system: systemPrompt,
            messages: messages.map { msg in
                .init(role: msg.role, content: [
                    .init(type: "text", text: msg.content)
                ])
            }
        )

        return try await sendRequest(body: body)
    }

    // MARK: - Chat (streaming)

    func chatStream(messages: [ChatMessage], systemPrompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var bodyDict: [String: Any] = [
                        "model": selectedModel,
                        "max_tokens": 1024,
                        "system": systemPrompt,
                        "stream": true,
                        "messages": messages.map { msg in
                            ["role": msg.role, "content": msg.content]
                        }
                    ]

                    if isExtendedThinking {
                        bodyDict["thinking"] = ["type": "enabled", "budget_tokens": AppSettings.thinkingMode.budgetTokens]
                        bodyDict["temperature"] = 1
                    }

                    var request = URLRequest(url: URL(string: baseURL)!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
                    request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        throw ClaudeError.apiError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonStr = String(line.dropFirst(6))
                            if jsonStr == "[DONE]" { break }
                            if let data = jsonStr.data(using: .utf8),
                               let event = try? JSONDecoder().decode(StreamEvent.self, from: data) {
                                if event.type == "content_block_delta",
                                   let delta = event.delta,
                                   delta.type == "text_delta",
                                   let text = delta.text {
                                    continuation.yield(text)
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private: Build Request

    private func makeRequestBody(maxTokens: Int, system: String, messages: [ClaudeMessageBody]) -> [String: Any] {
        var body: [String: Any] = [
            "model": selectedModel,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages.map { msg in
                var msgDict: [String: Any] = ["role": msg.role]
                var contentArr: [[String: Any]] = []
                for block in msg.content {
                    var blockDict: [String: Any] = ["type": block.type]
                    if let text = block.text {
                        blockDict["text"] = text
                    }
                    if let source = block.source {
                        blockDict["source"] = [
                            "type": source.type,
                            "media_type": source.media_type,
                            "data": source.data
                        ]
                    }
                    contentArr.append(blockDict)
                }
                msgDict["content"] = contentArr
                return msgDict
            }
        ]

        if isExtendedThinking {
            let budget = AppSettings.thinkingMode.budgetTokens
            // max_tokens must be greater than budget_tokens when thinking is enabled
            let effectiveMaxTokens = max(maxTokens, budget + 1024)
            body["max_tokens"] = effectiveMaxTokens
            body["thinking"] = ["type": "enabled", "budget_tokens": budget]
            body["temperature"] = 1
        }

        return body
    }

    private func sendRequest(body: [String: Any], timeout: TimeInterval = 30) async throws -> String {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.networkError
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(ClaudeErrorResponse.self, from: data) {
                throw ClaudeError.apiError(errorResponse.error.message)
            }
            let bodyStr = String(data: data, encoding: .utf8) ?? "unknown"
            throw ClaudeError.apiError("HTTP \(httpResponse.statusCode): \(bodyStr.prefix(200))")
        }

        let apiResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let textContent = apiResponse.content.first(where: { $0.type == "text" }) else {
            throw ClaudeError.emptyResponse
        }
        return textContent.text ?? ""
    }

    private func parseJSON<T: Decodable>(_ text: String) throws -> T {
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences (handle various formats)
        // Remove ```json ... ``` or ``` ... ```
        if let fenceStart = jsonString.range(of: "```json") {
            jsonString = String(jsonString[fenceStart.upperBound...])
        } else if let fenceStart = jsonString.range(of: "```") {
            jsonString = String(jsonString[fenceStart.upperBound...])
        }
        if let fenceEnd = jsonString.range(of: "```", options: .backwards) {
            jsonString = String(jsonString[..<fenceEnd.lowerBound])
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to find JSON array or object in the text
        // Check which comes first: { or [ — to avoid extracting an inner array from an object
        let firstBrace = jsonString.firstIndex(of: "{")
        let firstBracket = jsonString.firstIndex(of: "[")

        if let brace = firstBrace, let bracket = firstBracket {
            if brace < bracket {
                if let objEnd = jsonString.lastIndex(of: "}") {
                    jsonString = String(jsonString[brace...objEnd])
                }
            } else {
                if let arrayEnd = jsonString.lastIndex(of: "]") {
                    jsonString = String(jsonString[bracket...arrayEnd])
                }
            }
        } else if let brace = firstBrace, let objEnd = jsonString.lastIndex(of: "}") {
            jsonString = String(jsonString[brace...objEnd])
        } else if let bracket = firstBracket, let arrayEnd = jsonString.lastIndex(of: "]") {
            jsonString = String(jsonString[bracket...arrayEnd])
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw ClaudeError.parseError("无法编码为 UTF-8。AI 原始回复: \(text.prefix(200))")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let decodingError {
            throw ClaudeError.parseError("JSON解析错误: \(decodingError)。AI 原始回复: \(text.prefix(500))")
        }
    }
}

// MARK: - Request/Response Types (kept for content block building)

struct ClaudeMessageBody {
    let role: String
    let content: [ClaudeContentBlock]
}

struct ClaudeContentBlock {
    let type: String
    var text: String?
    var source: ClaudeImageSource?

    init(type: String, text: String) {
        self.type = type
        self.text = text
    }

    init(type: String, source: ClaudeImageSource) {
        self.type = type
        self.source = source
    }
}

struct ClaudeImageSource {
    let type: String
    let media_type: String
    let data: String
}

struct ClaudeResponse: Decodable {
    let content: [ClaudeResponseContent]
}

struct ClaudeResponseContent: Decodable {
    let type: String
    let text: String?
}

struct ClaudeErrorResponse: Decodable {
    let error: ClaudeErrorDetail
}

struct ClaudeErrorDetail: Decodable {
    let message: String
}

struct StreamEvent: Decodable {
    let type: String
    let delta: StreamDelta?
}

struct StreamDelta: Decodable {
    let type: String
    let text: String?
}

enum ClaudeError: LocalizedError {
    case invalidImage
    case networkError
    case apiError(String)
    case emptyResponse
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "图片处理失败"
        case .networkError: return "网络连接失败"
        case .apiError(let msg): return "API 错误: \(msg)"
        case .emptyResponse: return "AI 返回内容为空"
        case .parseError(let detail): return "解析失败: \(detail)"
        }
    }
}
