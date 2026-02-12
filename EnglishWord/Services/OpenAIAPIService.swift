import Foundation
#if canImport(UIKit)
import UIKit
#endif

final class OpenAIAPIService: AIServiceProtocol, Sendable {
    private let apiKey: String
    private let model: String
    private let baseURL = Constants.openAIBaseURL

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    // MARK: - OCR (always uses gpt-4o for vision)

    func recognizeWords(from image: UIImage) async throws -> [RecognizedWord] {
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

        let body: [String: Any] = [
            "model": "gpt-4o",
            "max_tokens": 4096,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]],
                    ["type": "text", "text": "请识别图片中适合小学生学习的英语单词。返回JSON对象，格式：{\"words\": [...]}"]
                ] as [[String: Any]]]
            ]
        ]

        let responseText = try await sendRequest(body: body, timeout: 60)
        // OpenAI with json_object mode may wrap in {"words": [...]}
        return try parseJSON(responseText)
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
        返回 JSON 对象：{"sentences": [{"english": "...", "chinese": "..."}]}
        不要返回任何其他文字、解释或 markdown 格式。
        """

        let body = makeRequestBody(
            maxTokens: 1024,
            system: systemPrompt,
            userMessage: "单词: \(word), 释义: \(meaning)",
            jsonMode: true
        )

        let responseText = try await sendRequest(body: body)
        return try parseJSON(responseText)
    }

    // MARK: - Word Lookup

    func lookupWord(_ spelling: String) async throws -> WordLookupResult {
        let systemPrompt = """
        你是一个英语词典助手，服务对象是小学四年级学生。
        返回 JSON 对象，不要任何其他文字、解释或 markdown 格式。
        JSON 格式如下：
        {"spelling":"单词","phonetic":"/音标/","chineseMeaning":"中文释义","sentences":[{"english":"例句","chinese":"翻译"}]}
        提供3个适合小学生的简单例句。
        """

        let body = makeRequestBody(
            maxTokens: 1024,
            system: systemPrompt,
            userMessage: "请查询单词: \(spelling)",
            jsonMode: true
        )

        let responseText = try await sendRequest(body: body)
        return try parseJSON(responseText)
    }

    // MARK: - Chat (non-streaming)

    func chat(messages: [ChatMessage], systemPrompt: String) async throws -> String {
        let body = makeChatRequestBody(
            maxTokens: 1024,
            system: systemPrompt,
            messages: messages
        )
        return try await sendRequest(body: body)
    }

    // MARK: - Chat (streaming)

    func chatStream(messages: [ChatMessage], systemPrompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var bodyDict = makeChatRequestBody(
                        maxTokens: 1024,
                        system: systemPrompt,
                        messages: messages
                    )
                    bodyDict["stream"] = true

                    var request = URLRequest(url: URL(string: baseURL)!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let delta = choices.first?["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
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

    private func makeRequestBody(maxTokens: Int, system: String, userMessage: String, jsonMode: Bool = false) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userMessage]
            ]
        ]
        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }
        return body
    }

    private func makeChatRequestBody(maxTokens: Int, system: String, messages: [ChatMessage]) -> [String: Any] {
        var msgs: [[String: Any]] = [["role": "system", "content": system]]
        for msg in messages {
            msgs.append(["role": msg.role, "content": msg.content])
        }
        return [
            "model": model,
            "max_tokens": maxTokens,
            "messages": msgs
        ]
    }

    private func sendRequest(body: [String: Any], timeout: TimeInterval = 30) async throws -> String {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.networkError
        }

        if httpResponse.statusCode != 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw ClaudeError.apiError(message)
            }
            let bodyStr = String(data: data, encoding: .utf8) ?? "unknown"
            throw ClaudeError.apiError("HTTP \(httpResponse.statusCode): \(bodyStr.prefix(200))")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ClaudeError.emptyResponse
        }

        return content
    }

    private func parseJSON<T: Decodable>(_ text: String) throws -> T {
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences
        if let fenceStart = jsonString.range(of: "```json") {
            jsonString = String(jsonString[fenceStart.upperBound...])
        } else if let fenceStart = jsonString.range(of: "```") {
            jsonString = String(jsonString[fenceStart.upperBound...])
        }
        if let fenceEnd = jsonString.range(of: "```", options: .backwards) {
            jsonString = String(jsonString[..<fenceEnd.lowerBound])
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        // OpenAI json_object mode may wrap arrays in an object like {"words": [...]} or {"sentences": [...]}
        // Try to extract the inner array if T is an array type
        if let data = jsonString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // If it's an object with a single key containing an array, try decoding the array directly
            if json.count == 1, let firstValue = json.values.first as? [[String: Any]] {
                let arrayData = try JSONSerialization.data(withJSONObject: firstValue)
                if let result = try? JSONDecoder().decode(T.self, from: arrayData) {
                    return result
                }
            }
            // Otherwise try decoding the whole object
            let objData = try JSONSerialization.data(withJSONObject: json)
            if let result = try? JSONDecoder().decode(T.self, from: objData) {
                return result
            }
        }

        // Fallback: find JSON array or object
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
}
