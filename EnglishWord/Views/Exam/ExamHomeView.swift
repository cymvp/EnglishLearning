import SwiftUI
import SwiftData

struct ExamHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Word.spelling) private var allWords: [Word]
    @Query(sort: \Exam.date, order: .reverse) private var exams: [Exam]
    @State private var showExam = false
    @State private var vm = ExamViewModel()
    var examWordCount: Int {
        min(allWords.count, Constants.Exam.questionsPerExam)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        vm.generateExam(from: allWords, modelContext: modelContext)
                        showExam = true
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("开始测评")
                                    .font(.title3.bold())
                                Text("从词库随机选 \(examWordCount) 个单词")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "pencil.and.list.clipboard")
                                .font(.title2)
                                .foregroundStyle(.blue)
                        }
                        .padding(.vertical, 8)
                    }
                    .disabled(allWords.isEmpty)
                }

                if !exams.isEmpty {
                    Section("历史成绩") {
                        ForEach(exams) { exam in
                            NavigationLink {
                                ExamResultView(exam: exam)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(exam.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.body)
                                        Text("\(exam.questions.count) 题")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    let maxScore = exam.questions.count * Constants.Exam.scorePerQuestion
                                    let pct = maxScore > 0 ? Double(exam.totalScore) / Double(maxScore) * 100 : 0
                                    Text("\(exam.totalScore)/\(maxScore)")
                                        .font(.title3.bold())
                                        .foregroundStyle(pct >= 80 ? .green : pct >= 60 ? .orange : .red)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("测评")
            .sheet(isPresented: $showExam) {
                ExamQuestionView(vm: vm)
            }
        }
    }
}
