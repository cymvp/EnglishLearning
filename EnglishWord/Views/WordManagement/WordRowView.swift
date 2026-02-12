import SwiftUI

struct WordRowView: View {
    let word: Word

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(word.spelling)
                        .font(.title3.bold())
                    if !word.phonetic.isEmpty {
                        Text(word.phonetic)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(word.chineseMeaning)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !word.source.isEmpty && word.source != "manual" && word.source != "ocr" {
                Text(word.source)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.blue.opacity(0.1)))
                    .foregroundStyle(.blue)
            }
            if word.isMastered {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }
}
