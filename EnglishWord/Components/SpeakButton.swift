import SwiftUI

struct SpeakButton: View {
    let text: String
    let tts: SpeechSynthesizerService

    var body: some View {
        Button {
            if tts.isSpeaking {
                tts.stop()
            } else {
                tts.speak(text)
            }
        } label: {
            Image(systemName: tts.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                .font(.title2)
                .symbolEffect(.variableColor.iterative, isActive: tts.isSpeaking)
        }
        .buttonStyle(.bordered)
        .tint(.blue)
    }
}
