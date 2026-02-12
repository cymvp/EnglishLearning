import Speech
import AVFoundation

@Observable
final class SpeechRecognizerService {
    private var speechRecognizer: SFSpeechRecognizer
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    var recognizedText: String = ""
    var isRecording: Bool = false
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    /// Called whenever recognizedText changes (for silence detection)
    var onTextChanged: (() -> Void)?

    private var currentLocale: String

    init(locale: String = Constants.Speech.englishLocale) {
        self.currentLocale = locale
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))!
    }

    /// Switch recognition language: "en-US" for English, "zh-CN" for Chinese
    func setLocale(_ locale: String) {
        if currentLocale != locale {
            if isRecording { stopRecording() }
            currentLocale = locale
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))!
        }
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    self.authorizationStatus = status
                }
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startRecording() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizedText = ""

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            throw SpeechError.requestUnavailable
        }
        recognitionRequest.shouldReportPartialResults = true

        if speechRecognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.recognizedText = result.bestTranscription.formattedString
                self.onTextChanged?()
            }
            if error != nil || result?.isFinal == true {
                self.stopRecording()
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    func stopRecording() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }
}

enum SpeechError: LocalizedError {
    case requestUnavailable
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .requestUnavailable: return "语音识别不可用"
        case .notAuthorized: return "未授权语音识别"
        }
    }
}
