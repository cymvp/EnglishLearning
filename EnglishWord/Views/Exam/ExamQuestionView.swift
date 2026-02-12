import SwiftUI

struct ExamQuestionView: View {
    @Bindable var vm: ExamViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if vm.isFinished {
                examFinishedView
            } else if let question = vm.currentQuestion {
                VStack(spacing: 32) {
                    // Progress
                    HStack {
                        Text("第 \(vm.currentIndex + 1) / \(vm.questions.count) 题")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("当前得分：\(vm.totalScore)")
                            .font(.headline)
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal)

                    ProgressView(value: Double(vm.currentIndex), total: Double(vm.questions.count))
                        .padding(.horizontal)

                    Spacer()

                    // Question
                    VStack(spacing: 20) {
                        Text(question.chineseMeaning)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.blue)

                        Button {
                            vm.speakCurrentWord()
                        } label: {
                            Label("听发音", systemImage: "speaker.wave.2.fill")
                                .font(.title3)
                                .padding()
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }

                    // Input
                    TextField("请输入单词", text: $vm.spellingInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 28, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.blue, lineWidth: 2)
                        )
                        .padding(.horizontal, 40)

                    Button {
                        vm.submitAnswer()
                    } label: {
                        Text(vm.currentIndex < vm.questions.count - 1 ? "下一题" : "提交")
                            .font(.title3)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.spellingInput.isEmpty)

                    Spacer()
                }
                .padding()
            }
        }
    }

    private var examFinishedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: vm.totalScore >= 80 ? "star.fill" : "flag.fill")
                .font(.system(size: 60))
                .foregroundStyle(vm.totalScore >= 80 ? .yellow : .orange)

            Text("测评完成!")
                .font(.largeTitle.bold())

            Text("\(vm.totalScore) 分")
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundStyle(vm.totalScore >= 80 ? .green : vm.totalScore >= 60 ? .orange : .red)

            // Results breakdown
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(vm.questions.enumerated()), id: \.offset) { idx, q in
                    HStack {
                        Image(systemName: q.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(q.isCorrect ? .green : .red)
                        Text(q.chineseMeaning)
                            .font(.body)
                        Spacer()
                        if q.isCorrect {
                            Text(q.wordSpelling)
                                .font(.body.bold())
                                .foregroundStyle(.green)
                        } else {
                            VStack(alignment: .trailing) {
                                Text(q.studentAnswer.isEmpty ? "未作答" : q.studentAnswer)
                                    .font(.body)
                                    .foregroundStyle(.red)
                                    .strikethrough()
                                Text(q.wordSpelling)
                                    .font(.body.bold())
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
            .padding(.horizontal)

            Button {
                dismiss()
            } label: {
                Text("完成")
                    .font(.title3)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
    }
}
