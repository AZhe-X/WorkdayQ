//
//  WorkdayQWidget.swift
//  WorkdayQWidget
//
//  Created by Xueqi Li on 3/3/25.
//

import WidgetKit
import SwiftUI
import SwiftData

// Constants shared with app
let appGroupID = "group.io.azhe.WorkdayQ"
let lastUpdateKey = "lastDatabaseUpdate"

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: Date(), workDays: [], lastUpdateTime: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> ()) {
        let entry = DayEntry(date: Date(), workDays: [], lastUpdateTime: 0)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        // Handle MainActor-isolation by dispatching to the main actor
        Task { @MainActor in
            // Get last update timestamp from shared UserDefaults
            let sharedDefaults = UserDefaults(suiteName: appGroupID)
            let lastUpdate = sharedDefaults?.double(forKey: lastUpdateKey) ?? 0
            print("Widget checking for updates, last update: \(Date(timeIntervalSince1970: lastUpdate))")
            
            // Access SwiftData container from AppGroup
            let modelConfiguration = ModelConfiguration(
                schema: Schema([WorkDay.self]),
                isStoredInMemoryOnly: false,
                groupContainer: .identifier(appGroupID)
            )
            
            // Get the current date normalized to start of day for consistency
            let currentDate = Calendar.current.startOfDay(for: Date())
            print("Widget timeline generating for date: \(currentDate)")
            
            var workDays: [WorkDayStruct] = []
            
            do {
                let modelContainer = try ModelContainer(for: WorkDay.self, configurations: modelConfiguration)
                
                let descriptor = FetchDescriptor<WorkDay>(sortBy: [SortDescriptor(\.date)])
                let fetchedData = try modelContainer.mainContext.fetch(descriptor)
                
                // Convert SwiftData models to our struct representation
                workDays = fetchedData.map { convertToWorkDayStruct($0) }
                
                print("Widget fetched \(workDays.count) work days")
                
                // For debugging
                for day in workDays.prefix(7) {
                    print("Fetched day: \(day.date), isWorkDay: \(day.isWorkDay)")
                }
                
                // Debug today's entry
                if let todayWorkDay = workDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: currentDate) }) {
                    print("TODAY: \(currentDate) status=\(todayWorkDay.isWorkDay)")
                } else {
                    print("TODAY: \(currentDate) not found in data")
                }
                
                // Debug tomorrow's entry
                if let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate),
                   let tomorrowWorkDay = workDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: tomorrowDate) }) {
                    print("TOMORROW: \(tomorrowDate) status=\(tomorrowWorkDay.isWorkDay)")
                } else {
                    print("TOMORROW not found in data")
                }
            } catch {
                print("Widget error loading data: \(error.localizedDescription)")
                // Create sample data for debugging
                workDays = [
                    WorkDayStruct(date: currentDate, isWorkDay: true),
                    WorkDayStruct(date: Calendar.current.date(byAdding: .day, value: 1, to: currentDate)!, isWorkDay: false)
                ]
            }
            
            // Create a timeline entry for now - use the normalized date
            let entry = DayEntry(date: currentDate, workDays: workDays, lastUpdateTime: lastUpdate)
            
            // Update refresh strategy based on context
            let refreshInterval: TimeInterval
            switch context.family {
            case .systemSmall, .systemMedium:
                // Use shorter refresh for visible widgets
                refreshInterval = context.isPreview ? 3600 : 300 // 5 minutes for real widgets, 1 hour for previews
            default:
                // Default to 15 minutes for other cases
                refreshInterval = 900
            }
            
            // Create timeline with refresh
            let currentTime = Date()
            let refreshDate = currentTime.addingTimeInterval(refreshInterval)
            
            let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
            completion(timeline)
        }
    }
}

struct DayEntry: TimelineEntry {
    let date: Date  // This should always be start of day
    let workDays: [WorkDayStruct]
    let lastUpdateTime: TimeInterval  // Track when data was last updated
    
    var todayWorkDay: WorkDayStruct? {
        let calendar = Calendar.current
        return workDays.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    // Returns the work status for a day offset from today
    // If no record exists, returns null but the display code should treat it as false (off day)
    func workDayForOffset(_ offset: Int) -> WorkDayStruct? {
        let calendar = Calendar.current
        guard let targetDate = calendar.date(byAdding: .day, value: offset, to: date) else {
            return nil
        }
        
        let result = workDays.first { calendar.isDate($0.date, inSameDayAs: targetDate) }
        if offset <= 1 {  // Log for debugging today and tomorrow
            print("Looking for day at offset \(offset): \(targetDate), found: \(result?.isWorkDay ?? false)")
        }
        return result
    }
}

struct WorkdayQWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry
    
    var body: some View {
        // This view is now only for the Week widget which adapts to size
        switch family {
        case .systemSmall:
            // Small size only shows today and tomorrow
            SmallWeekWidgetView(entry: entry)
        case .systemMedium:
            // Medium size shows the full week
            WeekWidgetView(entry: entry)
                .padding(0) // Remove any default padding
        default:
            WeekWidgetView(entry: entry)
                .padding(0)
        }
    }
}

struct TodayWidgetView: View {
    var entry: Provider.Entry
    
    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
    
    var body: some View {
        ZStack {
            // Use white background for consistency with other widgets
            Rectangle()
                .fill(Color.white)
                .edgesIgnoringSafeArea(.all)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(dateFormatter.string(from: entry.date))
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today is")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        let isWorkDay = entry.todayWorkDay?.isWorkDay ?? false
                        Text(isWorkDay ? "Workday" : "Off day")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(isWorkDay ? .red : .green)
                            .minimumScaleFactor(0.6)
                    }
                    
                    Spacer()
                    
                    // Match the circle size with other widgets for consistency
                    Circle()
                        .fill(entry.todayWorkDay?.isWorkDay ?? false ? Color.red : Color.green)
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                        .frame(width: 44, height: 44)
                }
                
                if let note = entry.todayWorkDay?.note, !note.isEmpty {
                    Text("Note: \(note)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            .padding()
        }
    }
}

struct WeekWidgetView: View {
    var entry: DayEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        // Fill the entire widget with a white background
        ZStack {
            Rectangle()
                .fill(Color.white)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                Spacer() // Push content to bottom
                
                HStack(alignment: .bottom, spacing: 0) {
                    // Today and the next 6 days
                    ForEach(0...6, id: \.self) { offset in
                        dayView(for: offset, isLarge: offset <= 1) // Make today and tomorrow larger
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
    }
    
    @ViewBuilder
    func dayView(for offset: Int, isLarge: Bool) -> some View {
        let calendar = Calendar.current
        
        // Use the entry's date (which is start of day) for consistency
        let date = calendar.date(byAdding: .day, value: offset, to: entry.date) ?? entry.date
        let workDay = entry.workDayForOffset(offset)
        let isWorkDay = workDay?.isWorkDay ?? false
        
        let dayOfWeek = calendar.component(.weekday, from: date)
        // Use "Today" for offset 0 and day name for other days
        let dayName = offset == 0 ? "Today" : calendar.shortWeekdaySymbols[dayOfWeek - 1]
        let dayNum = calendar.component(.day, from: date)
        
        let isToday = offset == 0
        
        VStack(spacing: 4) {
            Text(dayName)
                .font(.system(size: isLarge ? 13 : 10))
                .fontWeight(.medium)
                .foregroundColor(isToday ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            ZStack {
                Circle()
                    .fill(isWorkDay ? Color.red : Color.green)
                    .frame(width: isLarge ? 44 : 32, height: isLarge ? 44 : 32)
                
                Text("\(dayNum)")
                    .font(.system(size: isLarge ? 18 : 14, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .frame(height: isLarge ? 80 : 70) // Fixed height for better alignment
        .padding(.horizontal, 2)
        .background(
            Group {
                if isToday {
                    Rectangle()
                        .fill(Color(UIColor.systemGray6))
                        .cornerRadius(8)
                } else {
                    Color.clear
                }
            }
        )
    }
}

// New view for small widget with only today and tomorrow
struct SmallWeekWidgetView: View {
    var entry: DayEntry
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                Spacer() // Push content to bottom
                
                HStack(alignment: .bottom, spacing: 4) {
                    // Today and tomorrow only
                    ForEach(0...1, id: \.self) { offset in
                        dayView(for: offset)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
    }
    
    @ViewBuilder
    func dayView(for offset: Int) -> some View {
        let calendar = Calendar.current
        
        // Use the entry's date (which is start of day) for consistency
        let date = calendar.date(byAdding: .day, value: offset, to: entry.date) ?? entry.date
        let workDay = entry.workDayForOffset(offset)
        let isWorkDay = workDay?.isWorkDay ?? false
        
        // Use "Today" and "Tomorrow" for clarity
        let dayName = offset == 0 ? "Today" : "Tomorrow"
        let dayNum = calendar.component(.day, from: date)
        
        let isToday = offset == 0
        
        VStack(spacing: 8) {
            Text(dayName)
                .font(.system(size: 14))
                .fontWeight(.medium)
                .foregroundColor(isToday ? .primary : .secondary)
            
            ZStack {
                Circle()
                    .fill(isWorkDay ? Color.red : Color.green)
                    .frame(width: 50, height: 50)
                
                Text("\(dayNum)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .frame(height: 90) // Fixed height for better alignment
        .padding(.horizontal, 2)
        .background(
            Group {
                if isToday {
                    Rectangle()
                        .fill(Color(UIColor.systemGray6))
                        .cornerRadius(8)
                } else {
                    Color.clear
                }
            }
        )
    }
}

// Create two separate widgets
struct TodayStatusWidget: Widget {
    let kind: String = "TodayStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Status")
        .description("Shows if today is a work day or off day.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WeekOverviewWidget: Widget {
    let kind: String = "WeekOverviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WorkdayQWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Week Overview")
        .description("Shows your work/off day status for the week.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// Define WorkDay struct for widget access (to avoid SwiftData container issues)
struct WorkDayStruct: Identifiable {
    let id: UUID
    let date: Date
    let isWorkDay: Bool
    let note: String?
    
    init(date: Date, isWorkDay: Bool = false, note: String? = nil, id: UUID = UUID()) {
        self.id = id
        self.date = date
        self.isWorkDay = isWorkDay
        self.note = note
    }
}

// Define the actual SwiftData model for access
// IMPORTANT: Must EXACTLY match the name in the main app
@Model
final class WorkDay {
    var date: Date
    var isWorkDay: Bool
    var note: String?
    
    init(date: Date, isWorkDay: Bool = false, note: String? = nil) {
        self.date = date
        self.isWorkDay = isWorkDay
        self.note = note
    }
}

// Function to convert from SwiftData model to our struct representation
fileprivate func convertToWorkDayStruct(_ workDayModel: WorkDay) -> WorkDayStruct {
    return WorkDayStruct(
        date: workDayModel.date,
        isWorkDay: workDayModel.isWorkDay,
        note: workDayModel.note
    )
}

// Helper function to create test data for previews
fileprivate func createTestWorkDays() -> [WorkDayStruct] {
    let today = Date()
    let calendar = Calendar.current
    
    var testWorkDays: [WorkDayStruct] = []
    for i in 0..<7 {
        guard let date = calendar.date(byAdding: .day, value: i, to: calendar.startOfDay(for: today)) else {
            continue
        }
        // Alternate between work and off days
        let isWorkDay = i % 2 == 0 
        testWorkDays.append(WorkDayStruct(
            date: date,
            isWorkDay: isWorkDay,
            note: isWorkDay ? "Work day \(i)" : nil
        ))
    }
    
    return testWorkDays
}

#Preview(as: .systemSmall) {
    TodayStatusWidget()
} timeline: {
    DayEntry(date: Date(), workDays: [
        WorkDayStruct(date: Date(), isWorkDay: true, note: "Important meeting"),
        WorkDayStruct(date: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, isWorkDay: false)
    ], lastUpdateTime: 0)
}

#Preview(as: .systemMedium) {
    TodayStatusWidget()
} timeline: {
    DayEntry(date: Date(), workDays: createTestWorkDays(), lastUpdateTime: 0)
}

#Preview(as: .systemSmall) {
    WeekOverviewWidget()
} timeline: {
    DayEntry(date: Date(), workDays: createTestWorkDays(), lastUpdateTime: 0)
}

#Preview(as: .systemMedium) {
    WeekOverviewWidget()
} timeline: {
    DayEntry(date: Date(), workDays: createTestWorkDays(), lastUpdateTime: 0)
}
