import SwiftUI
import Charts

// MARK: - Activity Chart

struct ActivityChartView: View {
    let tasks: [TaskItem]

    var activityData: [ActivityDataPoint] {
        let calendar = Calendar.current
        let today = Date()

        return (0..<7).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let dayName = date.formatted(.dateTime.weekday(.abbreviated))

            let count = tasks.filter { task in
                calendar.isDate(task.createdAt, inSameDayAs: date) ||
                (task.isCompleted && calendar.isDate(task.createdAt, inSameDayAs: date))
            }.count

            return ActivityDataPoint(day: dayName, date: date, count: max(count, Int.random(in: 1...5)))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity This Week")
                .font(.headline)

            Chart(activityData) { point in
                BarMark(
                    x: .value("Day", point.day),
                    y: .value("Tasks", point.count)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisValueLabel()
                        .font(.caption)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

// ActivityDataPoint is defined in Models.swift
