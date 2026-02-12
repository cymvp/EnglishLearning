import Foundation

// MARK: - AI Provider

enum AIProvider: String, CaseIterable, Identifiable {
    case claude = "claude"
    case openai = "openai"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .openai: return "OpenAI"
        }
    }
}

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

// MARK: - OpenAI Model Options

enum OpenAIModelOption: String, CaseIterable, Identifiable {
    case gpt52 = "gpt-5.2"
    case gpt5Mini = "gpt-5-mini"
    case gpt4o = "gpt-4o"
    case gpt4oMini = "gpt-4o-mini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt52: return "GPT-5.2 (最强)"
        case .gpt5Mini: return "GPT-5 mini (均衡)"
        case .gpt4o: return "GPT-4o (经典)"
        case .gpt4oMini: return "GPT-4o mini (快速)"
        }
    }
}

enum OpenAIRealtimeModel: String, CaseIterable, Identifiable {
    case gpt4oRealtime = "gpt-4o-realtime-preview"
    case gpt4oMiniRealtime = "gpt-4o-mini-realtime-preview"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt4oRealtime: return "GPT-4o Realtime (高质量)"
        case .gpt4oMiniRealtime: return "GPT-4o mini Realtime (快速)"
        }
    }
}

enum OpenAIVoice: String, CaseIterable, Identifiable {
    case alloy = "alloy"
    case echo = "echo"
    case shimmer = "shimmer"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .alloy: return "Alloy (中性)"
        case .echo: return "Echo (男声)"
        case .shimmer: return "Shimmer (女声)"
        }
    }
}

// MARK: - Thinking Mode

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

    // Legacy: keeps "selectedModel" key for backward compatibility
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

    // MARK: Learning Scenario
    static var learningProvider: AIProvider {
        get {
            guard let raw = defaults.string(forKey: "learningProvider"),
                  let p = AIProvider(rawValue: raw) else { return .claude }
            return p
        }
        set { defaults.set(newValue.rawValue, forKey: "learningProvider") }
    }

    /// Claude model for learning (reuses "selectedModel" key for backward compatibility)
    static var learningClaudeModel: ClaudeModelOption {
        get { selectedModel }
        set { selectedModel = newValue }
    }

    static var learningOpenAIModel: OpenAIModelOption {
        get {
            guard let raw = defaults.string(forKey: "learningOpenAIModel"),
                  let m = OpenAIModelOption(rawValue: raw) else { return .gpt5Mini }
            return m
        }
        set { defaults.set(newValue.rawValue, forKey: "learningOpenAIModel") }
    }

    // MARK: Chat Scenario
    static var chatProvider: AIProvider {
        get {
            guard let raw = defaults.string(forKey: "chatProvider"),
                  let p = AIProvider(rawValue: raw) else { return .claude }
            return p
        }
        set { defaults.set(newValue.rawValue, forKey: "chatProvider") }
    }

    static var chatClaudeModel: ClaudeModelOption {
        get {
            guard let raw = defaults.string(forKey: "chatClaudeModel"),
                  let m = ClaudeModelOption(rawValue: raw) else { return .sonnet }
            return m
        }
        set { defaults.set(newValue.rawValue, forKey: "chatClaudeModel") }
    }

    static var chatRealtimeModel: OpenAIRealtimeModel {
        get {
            guard let raw = defaults.string(forKey: "chatRealtimeModel"),
                  let m = OpenAIRealtimeModel(rawValue: raw) else { return .gpt4oMiniRealtime }
            return m
        }
        set { defaults.set(newValue.rawValue, forKey: "chatRealtimeModel") }
    }

    static var chatVoice: OpenAIVoice {
        get {
            guard let raw = defaults.string(forKey: "chatVoice"),
                  let v = OpenAIVoice(rawValue: raw) else { return .alloy }
            return v
        }
        set { defaults.set(newValue.rawValue, forKey: "chatVoice") }
    }
}

// MARK: - Constants

enum Constants {
    static let keychainServiceName = "com.englishword.apikey"
    static let keychainAccountName = "claude-api-key"
    static let keychainOpenAIAccountName = "openai-api-key"
    static let claudeBaseURL = "https://api.anthropic.com/v1/messages"
    static let claudeAPIVersion = "2023-06-01"
    static let openAIBaseURL = "https://api.openai.com/v1/chat/completions"
    static let openAIRealtimeBaseURL = "wss://api.openai.com/v1/realtime"

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
