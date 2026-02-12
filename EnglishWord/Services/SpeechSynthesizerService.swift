import AVFoundation

@Observable
final class SpeechSynthesizerService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    var isSpeaking: Bool = false
    private var completionHandler: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, rate: Float = Constants.Speech.rate) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)

        // Prefer a warm female voice (Samantha enhanced if available, otherwise default en-US)
        if let enhancedVoice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-US.Samantha") {
            utterance.voice = enhancedVoice
        } else if let compactVoice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.en-US.Samantha") {
            utterance.voice = compactVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: Constants.Speech.englishLocale)
        }

        utterance.rate = rate
        utterance.pitchMultiplier = Constants.Speech.pitchMultiplier
        utterance.volume = Constants.Speech.volume
        utterance.preUtteranceDelay = 0.2
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func speak(_ text: String, rate: Float = Constants.Speech.rate, completion: @escaping () -> Void) {
        completionHandler = completion
        speak(text, rate: rate)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        completionHandler = nil
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        let handler = completionHandler
        completionHandler = nil
        handler?()
    }
}
