import Foundation

/// Manages daily chat history persistence for FreeChatView.
/// Saves messages as JSON files keyed by date. Generates summaries for AI context.
enum ChatHistoryService {
    private static let fileManager = FileManager.default

    private static var chatDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ChatHistory", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static var todayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func fileURL(for dateKey: String) -> URL {
        chatDirectory.appendingPathComponent("\(dateKey).json")
    }

    // MARK: - Save / Load Messages

    static func saveTodayMessages(_ messages: [ChatMessage]) {
        let entries = messages.map { CodableChatMessage(role: $0.role, content: $0.content) }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL(for: todayKey), options: .atomic)
    }

    static func loadTodayMessages() -> [ChatMessage] {
        let url = fileURL(for: todayKey)
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([CodableChatMessage].self, from: data) else {
            return []
        }
        return entries.map { ChatMessage(role: $0.role, content: $0.content) }
    }

    // MARK: - Summary

    /// Build a short summary of today's earlier conversation for the AI system prompt.
    /// We include the last few exchanges (up to 10 messages) as a condensed recap.
    static func loadTodaySummary() -> String {
        let messages = loadTodayMessages()
        guard !messages.isEmpty else { return "" }

        // Take the last 10 messages for summary context
        let recent = messages.suffix(10)
        var lines: [String] = []
        for msg in recent {
            let prefix = msg.role == "user" ? "Student" : "Teacher"
            lines.append("\(prefix): \(msg.content)")
        }
        return lines.joined(separator: "\n")
    }
}

/// Codable wrapper for ChatMessage persistence
private struct CodableChatMessage: Codable {
    let role: String
    let content: String
}
