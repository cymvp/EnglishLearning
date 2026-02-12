import Foundation
@preconcurrency import AVFoundation

@Observable
@MainActor
final class OpenAIRealtimeService: NSObject {

    // MARK: - Public State

    var isConnected = false
    var isAISpeaking = false
    var currentTranscript = ""   // AI response transcript (real-time)
    var userTranscript = ""      // User speech transcript
    var errorMessage = ""

    // MARK: - Callbacks

    var onAIResponseComplete: ((String) -> Void)?
    var onUserSpeechDetected: ((String) -> Void)?

    // MARK: - Private

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    // Audio engine (microphone input)
    private let audioEngine = AVAudioEngine()
    private nonisolated(unsafe) var inputConverter: AVAudioConverter?

    // Audio player (AI output)
    private let playerEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isPlayerSetup = false

    // Target format: 24kHz mono PCM16
    private let sampleRate: Double = 24000
    private var targetFormat: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)!
    }

    private var pendingAudioData = Data()
    private var currentResponseId: String?

    // MARK: - Connect

    func connect(systemPrompt: String) {
        guard !isConnected else { return }

        let model = AppSettings.chatRealtimeModel.rawValue
        guard let apiKey = KeychainService.getAPIKey(for: .openai), !apiKey.isEmpty else {
            errorMessage = "请先在设置中配置 OpenAI API Key"
            return
        }

        let urlString = "\(Constants.openAIRealtimeBaseURL)?model=\(model)"
        guard let url = URL(string: urlString) else {
            errorMessage = "无效的 Realtime URL"
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let session = URLSession(configuration: .default)
        urlSession = session
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        isConnected = true
        errorMessage = ""
        currentTranscript = ""
        userTranscript = ""

        // Send session config
        sendSessionUpdate(systemPrompt: systemPrompt)

        // Start reading messages
        receiveMessage()

        // Start audio capture
        startAudioCapture()
    }

    func disconnect() {
        stopAudioCapture()
        stopPlayback()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        isConnected = false
        isAISpeaking = false
        currentTranscript = ""
        userTranscript = ""
        currentResponseId = nil
    }

    // MARK: - Session Configuration

    private func sendSessionUpdate(systemPrompt: String) {
        let voice = AppSettings.chatVoice.rawValue
        let event: [String: Any] = [
            "type": "session.update",
            "session": [
                "modalities": ["text", "audio"],
                "voice": voice,
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "input_audio_transcription": [
                    "model": "whisper-1"
                ],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 500
                ],
                "instructions": systemPrompt
            ] as [String: Any]
        ]
        sendJSON(event)
    }

    // MARK: - Audio Capture (Microphone → WebSocket)

    private func startAudioCapture() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            errorMessage = "音频会话配置失败: \(error.localizedDescription)"
            return
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create converter from mic format to 24kHz PCM16
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            errorMessage = "无法创建音频转换器"
            return
        }
        inputConverter = converter

        // Calculate buffer size for ~100ms of audio at input sample rate
        let bufferSize = AVAudioFrameCount(inputFormat.sampleRate * 0.1)

        let capturedConverter = converter
        let capturedTargetFormat = targetFormat
        let capturedSampleRate = sampleRate

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            // All audio processing happens on the audio thread — no MainActor needed
            let ratio = capturedSampleRate / buffer.format.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: capturedTargetFormat, frameCapacity: outputFrameCount) else { return }

            var convError: NSError?
            var allConsumed = false
            capturedConverter.convert(to: outputBuffer, error: &convError) { _, outStatus in
                if allConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                allConsumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            guard convError == nil, outputBuffer.frameLength > 0 else { return }
            guard let int16Data = outputBuffer.int16ChannelData else { return }

            let byteCount = Int(outputBuffer.frameLength) * 2
            let data = Data(bytes: int16Data[0], count: byteCount)
            let base64 = data.base64EncodedString()

            let event: [String: Any] = [
                "type": "input_audio_buffer.append",
                "audio": base64
            ]

            Task { @MainActor [weak self] in
                self?.sendJSON(event)
            }
        }

        do {
            try audioEngine.start()
        } catch {
            errorMessage = "麦克风启动失败: \(error.localizedDescription)"
        }
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        inputConverter = nil
    }

    // MARK: - Audio Playback (WebSocket → Speaker)

    private func setupPlayerIfNeeded() {
        guard !isPlayerSetup else { return }

        // Use float format for player node
        playerEngine.attach(playerNode)
        let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        playerEngine.connect(playerNode, to: playerEngine.mainMixerNode, format: playbackFormat)

        do {
            try playerEngine.start()
            playerNode.play()
            isPlayerSetup = true
        } catch {
            errorMessage = "音频播放引擎启动失败"
        }
    }

    private func playAudioDelta(_ base64Audio: String) {
        guard let data = Data(base64Encoded: base64Audio), !data.isEmpty else { return }
        setupPlayerIfNeeded()

        let frameCount = AVAudioFrameCount(data.count / 2) // PCM16 = 2 bytes per sample
        let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        // Convert PCM16 to Float32
        guard let floatData = pcmBuffer.floatChannelData?[0] else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let int16Ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
            for i in 0..<Int(frameCount) {
                floatData[i] = Float(int16Ptr[i]) / 32768.0
            }
        }

        playerNode.scheduleBuffer(pcmBuffer)
        isAISpeaking = true
    }

    private func stopPlayback() {
        if isPlayerSetup {
            playerNode.stop()
            playerEngine.stop()
            playerEngine.detach(playerNode)
            isPlayerSetup = false
        }
        isAISpeaking = false
    }

    // MARK: - WebSocket Send

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(str)) { error in
            if let error = error {
                Task { @MainActor [weak self] in
                    self?.errorMessage = "发送失败: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - WebSocket Receive

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self, self.isConnected else { return }

                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleServerEvent(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleServerEvent(text)
                        }
                    @unknown default:
                        break
                    }
                    self.receiveMessage()

                case .failure(let error):
                    if self.isConnected {
                        self.errorMessage = "连接断开: \(error.localizedDescription)"
                        self.isConnected = false
                    }
                }
            }
        }
    }

    // MARK: - Event Handling

    private func handleServerEvent(_ jsonText: String) {
        guard let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "session.created", "session.updated":
            // Session ready
            break

        case "response.audio.delta":
            // AI audio chunk
            if let delta = json["delta"] as? String {
                playAudioDelta(delta)
            }

        case "response.audio_transcript.delta":
            // AI text transcript (real-time)
            if let delta = json["delta"] as? String {
                currentTranscript += delta
                isAISpeaking = true
            }

        case "response.audio_transcript.done":
            // Final AI transcript for this response item
            break

        case "response.done":
            // AI finished responding
            let transcript = currentTranscript
            isAISpeaking = false
            if !transcript.isEmpty {
                onAIResponseComplete?(transcript)
            }
            currentTranscript = ""
            currentResponseId = nil

        case "conversation.item.input_audio_transcription.completed":
            // User speech transcription done
            if let transcript = json["transcript"] as? String, !transcript.isEmpty {
                userTranscript = transcript
                onUserSpeechDetected?(transcript)
            }

        case "input_audio_buffer.speech_started":
            // User started speaking — interrupt AI if it's talking
            if isAISpeaking {
                cancelCurrentResponse()
                stopPlaybackForInterruption()
            }

        case "input_audio_buffer.speech_stopped":
            break

        case "error":
            if let errorData = json["error"] as? [String: Any],
               let message = errorData["message"] as? String {
                errorMessage = "Realtime 错误: \(message)"
            }

        default:
            break
        }
    }

    private func cancelCurrentResponse() {
        sendJSON(["type": "response.cancel"])
    }

    private func stopPlaybackForInterruption() {
        if isPlayerSetup {
            playerNode.stop()
            playerNode.play() // restart for next response
        }
        isAISpeaking = false
        currentTranscript = ""
    }
}
