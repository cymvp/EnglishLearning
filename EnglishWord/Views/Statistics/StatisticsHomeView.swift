import SwiftUI
import SwiftData

struct StatisticsHomeView: View {
    @Query(
        filter: #Predicate<Word> { $0.isMastered },
        sort: \Word.masteredAt, order: .reverse
    ) private var masteredWords: [Word]

    @Query(sort: \Exam.date, order: .reverse) private var allExams: [Exam]

    private var dailyWordGroups: [(date: String, words: [Word])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: masteredWords) { word -> String in
            guard let date = word.masteredAt else { return "未知" }
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return grouped
            .map { (date: $0.key, words: $0.value) }
            .sorted { a, b in
                // Sort by most recent first
                guard let dateA = a.words.first?.masteredAt,
                      let dateB = b.words.first?.masteredAt else { return false }
                return dateA > dateB
            }
    }

    private var dailyExamGroups: [(date: String, exams: [Exam])] {
        let grouped = Dictionary(grouping: allExams) { exam -> String in
            exam.date.formatted(date: .abbreviated, time: .omitted)
        }
        return grouped
            .map { (date: $0.key, exams: $0.value) }
            .sorted { a, b in
                guard let dateA = a.exams.first?.date,
                      let dateB = b.exams.first?.date else { return false }
                return dateA > dateB
            }
    }

    var body: some View {
        NavigationStack {
            List {
                // Summary
                Section("总览") {
                    HStack {
                        StatCard(title: "已学会", value: "\(masteredWords.count)", icon: "checkmark.seal.fill", color: .green)
                        StatCard(title: "考试次数", value: "\(allExams.count)", icon: "pencil.and.list.clipboard", color: .blue)
                        StatCard(title: "平均分", value: averageScore, icon: "chart.line.uptrend.xyaxis", color: .orange)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                // Daily learned words
                if !dailyWordGroups.isEmpty {
                    Section("每日学习") {
                        ForEach(dailyWordGroups, id: \.date) { group in
                            DisclosureGroup {
                                ForEach(group.words) { word in
                                    HStack {
                                        Text(word.spelling)
                                            .font(.body.bold())
                                        Spacer()
                                        Text(word.chineseMeaning)
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(group.date)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(group.words.count) 个单词")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // Daily exams
                if !dailyExamGroups.isEmpty {
                    Section("考试记录") {
                        ForEach(dailyExamGroups, id: \.date) { group in
                            DisclosureGroup {
                                ForEach(group.exams) { exam in
                                    NavigationLink {
                                        ExamResultView(exam: exam)
                                    } label: {
                                        HStack {
                                            Text(exam.date.formatted(date: .omitted, time: .shortened))
                                                .font(.body)
                                            Spacer()
                                            Text("\(exam.totalScore) 分")
                                                .font(.body.bold())
                                                .foregroundStyle(
                                                    exam.totalScore >= 80 ? .green :
                                                    exam.totalScore >= 60 ? .orange : .red
                                                )
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(group.date)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(group.exams.count) 次考试")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if masteredWords.isEmpty && allExams.isEmpty {
                    ContentUnavailableView {
                        Label("暂无数据", systemImage: "chart.bar")
                    } description: {
                        Text("开始学习和测评后，这里会显示你的进度")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("统计")
        }
    }

    private var averageScore: String {
        guard !allExams.isEmpty else { return "--" }
        let avg = allExams.reduce(0) { $0 + $1.totalScore } / allExams.count
        return "\(avg)"
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}
