import Foundation

// MARK: - Claude Model Options

enum ClaudeModelOption: String, CaseIterable, Identifiable {
    case haiku = "claude-haiku-4-5-20251001"
    case sonnet = "claude-sonnet-4-5-20250929"
    case opus = "claude-opus-4-6"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .haiku: return "Claude Haiku 4.5 (快速)"
        case .sonnet: return "Claude Sonnet 4.5 (均衡)"
        case .opus: return "Claude Opus 4.6 (最强)"
        }
    }
}

enum ThinkingMode: String, CaseIterable, Identifiable {
    case fast = "fast"
    case slow = "slow"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fast: return "快思考"
        case .slow: return "慢思考 (深度推理)"
        }
    }

    var budgetTokens: Int {
        switch self {
        case .fast: return 0
        case .slow: return 10000
        }
    }
}

// MARK: - App Settings (UserDefaults backed)

enum AppSettings {
    private static let defaults = UserDefaults.standard

    static var selectedModel: ClaudeModelOption {
        get {
            guard let raw = defaults.string(forKey: "selectedModel"),
                  let model = ClaudeModelOption(rawValue: raw) else {
                return .sonnet
            }
            return model
        }
        set { defaults.set(newValue.rawValue, forKey: "selectedModel") }
    }

    static var thinkingMode: ThinkingMode {
        get {
            guard let raw = defaults.string(forKey: "thinkingMode"),
                  let mode = ThinkingMode(rawValue: raw) else {
                return .fast
            }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: "thinkingMode") }
    }

    static var selectedWordPack: String {
        get { defaults.string(forKey: "selectedWordPack") ?? "" }
        set { defaults.set(newValue, forKey: "selectedWordPack") }
    }
}

// MARK: - Constants

enum Constants {
    static let keychainServiceName = "com.englishword.apikey"
    static let keychainAccountName = "claude-api-key"
    static let claudeBaseURL = "https://api.anthropic.com/v1/messages"
    static let claudeAPIVersion = "2023-06-01"

    enum Speech {
        static let englishLocale = "en-US"
        static let chineseLocale = "zh-CN"
        static let rate: Float = 0.38          // Slightly slower for gentle pacing
        static let pitchMultiplier: Float = 1.2 // Higher pitch for warmer, softer tone
        static let volume: Float = 0.85         // Slightly softer volume
    }

    enum Exam {
        static let questionsPerExam = 10
        static let scorePerQuestion = 10
        static let totalScore = questionsPerExam * scorePerQuestion
    }

    enum Learning {
        static let maxPronunciationAttempts = 3
        static let sentenceMatchThreshold = 0.8
    }
}
