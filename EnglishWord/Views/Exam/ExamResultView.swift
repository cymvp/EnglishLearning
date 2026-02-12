import SwiftUI

struct ExamResultView: View {
    let exam: Exam

    private var maxScore: Int {
        exam.questions.count * Constants.Exam.scorePerQuestion
    }

    private var scorePercent: Double {
        guard maxScore > 0 else { return 0 }
        return Double(exam.totalScore) / Double(maxScore) * 100
    }

    private var scoreColor: Color {
        scorePercent >= 80 ? .green : scorePercent >= 60 ? .orange : .red
    }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text(exam.date.formatted(date: .long, time: .shortened))
                            .font(.headline)
                        Text("\(exam.questions.count) 道题")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(exam.totalScore)/\(maxScore)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor)
                }
                .padding(.vertical, 8)
            }

            Section("答题详情") {
                ForEach(Array(exam.questions.enumerated()), id: \.offset) { idx, question in
                    HStack {
                        Image(systemName: question.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(question.isCorrect ? .green : .red)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(question.chineseMeaning)
                                .font(.body)
                            Text("正确答案：\(question.wordSpelling)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text(question.studentAnswer.isEmpty ? "未作答" : question.studentAnswer)
                                .font(.body)
                                .foregroundStyle(question.isCorrect ? .green : .red)
                            Text("\(question.score) 分")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("考试详情")
    }
}
