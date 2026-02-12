import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? .red : .blue)
                    .frame(width: 70, height: 70)
                    .shadow(color: isRecording ? .red.opacity(0.4) : .blue.opacity(0.3), radius: 8)

                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
        }
        .scaleEffect(isRecording ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isRecording)
    }
}
