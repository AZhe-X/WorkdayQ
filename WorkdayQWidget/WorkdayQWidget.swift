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
let languagePreferenceKey = "languagePreference" // Add language preference key
let customWorkTermKey = "customWorkTerm" // Add custom work term key
let appearancePreferenceKey = "appearancePreference" // Add appearance preference key
let startOfWeekPreferenceKey = "startOfWeekPreference" // Add start of week preference key

// Helper to determine if a date is a workday by default
// (Monday-Friday = workday, Saturday-Sunday = off day)
func isDefaultWorkDay(_ date: Date) -> Bool {
    let weekday = Calendar.current.component(.weekday, from: date)
    // 1 = Sunday, 2 = Monday, ..., 7 = Saturday
    return weekday >= 2 && weekday <= 6 // Monday to Friday
}

// Language options enum (duplicated from main app)
enum AppLanguage: Int, CaseIterable {
    case systemDefault = 0
    case english = 1
    case chinese = 2
    
    // Helper to determine if we should use Chinese
    static func shouldUseChineseText(_ preferenceValue: Int) -> Bool {
        let language = AppLanguage(rawValue: preferenceValue) ?? .systemDefault
        
        switch language {
        case .english:
            return false
        case .chinese:
            return true
        case .systemDefault:
            // Try to detect system language
            let preferredLanguage = Locale.current.language.languageCode?.identifier ?? "en"
            return preferredLanguage.hasPrefix("zh")
        }
    }
}

// Add AppAppearance enum to help with ColorScheme conversion
enum AppAppearance: Int, CaseIterable {
    case systemDefault = 0
    case light = 1
    case dark = 2
    
    var colorScheme: ColorScheme? {
        switch self {
        case .systemDefault: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    static func colorSchemeFromPreference(_ preferenceValue: Int) -> ColorScheme? {
        return AppAppearance(rawValue: preferenceValue)?.colorScheme
    }
}

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
            
            // Get appearance preference
            let appearancePref = sharedDefaults?.integer(forKey: appearancePreferenceKey) ?? 0
            let preferredColorScheme = AppAppearance.colorSchemeFromPreference(appearancePref)
            
            // Get start of week preference
            let startOfWeekPref = sharedDefaults?.integer(forKey: startOfWeekPreferenceKey) ?? 0
            
            // DEBUG: Check language preference
            let langPref = sharedDefaults?.integer(forKey: languagePreferenceKey) ?? 0
            print("Provider timeline checking language preference: \(langPref)")
            print("Widget checking for updates, last update: \(Date(timeIntervalSince1970: lastUpdate))")
            
            // Get the current date normalized to start of day for consistency
            let currentDate = Calendar.current.startOfDay(for: Date())
            print("Widget timeline generating for date: \(currentDate)")
            
            var workDays: [WorkDayStruct] = []
            
            do {
                // Create a more resilient model configuration
                let schema = Schema([WorkDay.self])
                
                // Configure model with explicit migration options to avoid write attempts
                let modelConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    allowsSave: false, // Read-only access for widget
                    groupContainer: .identifier(appGroupID)
                )
                
                // Set extra options that might help with read-only access
                // We can't set async loading directly, but we can check the URL exists
                if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
                    let storeURL = containerURL.appendingPathComponent("default.store")
                    if FileManager.default.fileExists(atPath: storeURL.path) {
                        print("Widget found database at: \(storeURL.path)")
                    } else {
                        print("Widget: database not found at expected location")
                    }
                }
                
                // Try to create the container with error handling
                let modelContainer: ModelContainer
                do {
                    // First try with read-only configuration 
                    modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
                    print("Widget successfully created ModelContainer")
                } catch {
                    print("Widget error creating ModelContainer: \(error.localizedDescription)")
                    
                    // Attempt to create a container with more relaxed options
                    print("Widget trying alternative container configuration...")
                    let altConfig = ModelConfiguration(
                        schema: schema,
                        isStoredInMemoryOnly: true, // Use memory-only as fallback
                        groupContainer: .identifier(appGroupID)
                    )
                    
                    do {
                        modelContainer = try ModelContainer(for: schema, configurations: [altConfig])
                        print("Widget created memory-only ModelContainer as fallback")
                    } catch {
                        // If that still fails, just use a basic in-memory container
                        print("Widget falling back to basic memory container")
                        let fallbackConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                        modelContainer = try ModelContainer(for: schema, configurations: [fallbackConfig])
                        
                        // Re-throw the error to use the UserDefaults fallback data
                        throw error
                    }
                }
                
                // Create a fetch descriptor with error handling
                let descriptor = FetchDescriptor<WorkDay>(sortBy: [SortDescriptor(\.date)])
                
                // Fetch data with additional error handling
                let fetchedData: [WorkDay]
                do {
                    fetchedData = try modelContainer.mainContext.fetch(descriptor)
                } catch {
                    print("Widget error fetching data: \(error.localizedDescription)")
                    throw error
                }
                
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
                
                // Try to get data from UserDefaults as backup
                workDays = loadWorkDaysFromUserDefaults() ?? []
                
                // If no data in UserDefaults either, create sample fallback data
                if workDays.isEmpty {
                    print("Widget using fallback sample data")
                    let today = currentDate
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
                    
                    workDays = [
                        WorkDayStruct(date: today, isWorkDay: true, note: "Widget fallback: Database access error"),
                        WorkDayStruct(date: tomorrow, isWorkDay: false, note: "Try reopening the main app")
                    ]
                    
                    // Create a week of sample data
                    for i in 2...6 {
                        if let futureDate = Calendar.current.date(byAdding: .day, value: i, to: today) {
                            workDays.append(WorkDayStruct(
                                date: futureDate,
                                isWorkDay: i % 2 == 0, // Alternate work/off days
                                note: nil
                            ))
                        }
                    }
                }
            }
            
            // Create a timeline entry for now - use the normalized date
            let entry = DayEntry(
                date: currentDate, 
                workDays: workDays, 
                lastUpdateTime: lastUpdate,
                preferredColorScheme: preferredColorScheme,
                startOfWeekPreference: startOfWeekPref
            )
            
            // Update refresh strategy based on context
            let refreshInterval: TimeInterval
            switch context.family {
            case .systemSmall, .systemMedium:
                // Use shorter refresh for visible widgets
                refreshInterval = context.isPreview ? 3600 : 60 // 1 minute for real widgets for faster updates, 1 hour for previews
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
    let preferredColorScheme: ColorScheme?
    let startOfWeekPreference: Int // Sunday=0, Monday=1
    
    // Use initializer with default parameters
    init(date: Date, workDays: [WorkDayStruct], lastUpdateTime: TimeInterval, preferredColorScheme: ColorScheme? = nil, startOfWeekPreference: Int = 0) {
        self.date = date
        self.workDays = workDays
        self.lastUpdateTime = lastUpdateTime
        self.preferredColorScheme = preferredColorScheme
        self.startOfWeekPreference = startOfWeekPreference
    }
    
    var todayWorkDay: WorkDayStruct? {
        let calendar = Calendar.current
        return workDays.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    // Get the work status for today with default rules
    var isTodayWorkDay: Bool {
        // If we have an explicit entry for today, use it
        if let explicitDay = todayWorkDay {
            return explicitDay.isWorkDay
        }
        // Otherwise use default rules: weekdays = work, weekends = off
        return isDefaultWorkDay(date)
    }
    
    // Returns the work status for a day offset from today
    // If no record exists, use default rules (Mon-Fri = work, Sat-Sun = off)
    func workDayForOffset(_ offset: Int) -> WorkDayStruct? {
        let calendar = Calendar.current
        guard let targetDate = calendar.date(byAdding: .day, value: offset, to: date) else {
            return nil
        }
        
        // Look for an explicit entry first
        let result = workDays.first { calendar.isDate($0.date, inSameDayAs: targetDate) }
        
        if offset <= 1 {  // Log for debugging today and tomorrow
            if let explicitDay = result {
                print("Looking for day at offset \(offset): \(targetDate), found explicit record: \(explicitDay.isWorkDay)")
            } else {
                let defaultStatus = isDefaultWorkDay(targetDate)
                print("Looking for day at offset \(offset): \(targetDate), using default status: \(defaultStatus)")
            }
        }
        return result
    }
    
    // Check if a specific date is a workday, using stored data or default rules
    func isWorkDay(forDate date: Date) -> Bool {
        let calendar = Calendar.current
        // First check if we have an explicit record
        if let explicitDay = workDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            return explicitDay.isWorkDay
        }
        // Fall back to default rules
        return isDefaultWorkDay(date)
    }
}

struct WorkdayQWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme
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

// Ensure views are accessible to the Widget
struct TodayWidgetView: View {
    var entry: Provider.Entry
    @Environment(\.colorScheme) var colorScheme
    // Use direct UserDefaults access with a non-optional default
    private let userDefaults = UserDefaults(suiteName: appGroupID) ?? UserDefaults.standard
    
    // Get the custom work term from UserDefaults, or use default if not set
    private var customWorkTerm: String {
        userDefaults.string(forKey: customWorkTermKey) ?? "上班"
    }
    
    // Helper to replace "上班" with custom term
    private func customizeWorkTerm(_ text: String) -> String {
        if customWorkTerm == "上班" {
            return text
        }
        return text.replacingOccurrences(of: "上班", with: customWorkTerm)
    }
    
    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        
        // Try to respect the language preference for date format
        let langPref = userDefaults.integer(forKey: languagePreferenceKey)
        if AppLanguage.shouldUseChineseText(langPref) {
            formatter.locale = Locale(identifier: "zh-Hans")
        }
        
        return formatter
    }
    
    var body: some View {
        // Debug the language preference directly from UserDefaults
        let langPref = userDefaults.integer(forKey: languagePreferenceKey)
        let useChineseText = AppLanguage.shouldUseChineseText(langPref)
        
        // Debug output - this will appear in the console when widget updates
        print("Widget language preference: \(langPref), useChineseText: \(useChineseText)")
        print("Widget custom work term: \(customWorkTerm)")
        print("TodayWidgetView detected colorScheme: \(colorScheme == .dark ? "dark" : "light")")
        
        return VStack(alignment: .leading, spacing: 4) {
            Text(dateFormatter.string(from: entry.date))
                .font(.headline)
                .padding(.bottom, 4)
            
            // Use Chinese format or English format based on language preference
            if useChineseText {
                Text("今天")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .padding(.bottom, -4)
            } else {
                Text("Today is:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    // Remove padding to match app styling
            }
            
            HStack {
                let isWorkDay = entry.isTodayWorkDay
                
                // Use different text format for Chinese
                if useChineseText {
                    Text(customizeWorkTerm(isWorkDay ? "要上班" : "不上班"))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(isWorkDay ? .red : .green)
                        .padding(.top, -3)
                } else {
                    Text(isWorkDay ? "Workday" : "Off day")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(isWorkDay ? .red : .green)
                        // Remove minimumScaleFactor to match app styling
                }
                
                Spacer()
                
                // Match the circle size with the main app
                Circle()
                    .fill(isWorkDay ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                    .frame(width: 50, height: 50)
            }
            
            if let note = entry.todayWorkDay?.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
        .frame(height: 155)
        .frame(maxWidth: .infinity)
        .containerBackground(for: .widget) {
            // Use direct color scheme detection for the background
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.11, green: 0.11, blue: 0.12)) // iOS native dark background color
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
            }
        }
    }
}

struct WeekWidgetView: View {
    var entry: DayEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme
    // Use direct UserDefaults access with a non-optional default
    private let userDefaults = UserDefaults(suiteName: appGroupID) ?? UserDefaults.standard
    
    // Get the custom work term from UserDefaults, or use default if not set
    private var customWorkTerm: String {
        userDefaults.string(forKey: customWorkTermKey) ?? "上班"
    }
    
    // Helper to replace "上班" with custom term
    private func customizeWorkTerm(_ text: String) -> String {
        if customWorkTerm == "上班" {
            return text
        }
        return text.replacingOccurrences(of: "上班", with: customWorkTerm)
    }
    
    var body: some View {
        // Debug the language preference directly from UserDefaults
        let langPref = userDefaults.integer(forKey: languagePreferenceKey)
        let useChineseText = AppLanguage.shouldUseChineseText(langPref)
        
        // Debug output
        print("Week widget language preference: \(langPref), useChineseText: \(useChineseText)")
        print("Week widget custom work term: \(customWorkTerm)")
        print("WeekWidgetView detected colorScheme: \(colorScheme == .dark ? "dark" : "light")")
        
        return VStack(spacing: 0) {
            // Add the title at the top - only show in Chinese
            if useChineseText {
                Text(customizeWorkTerm("这几天上班吗？"))
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary) // Make text gray
                    .frame(maxWidth: .infinity, alignment: .leading) // Align to left
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .padding(.leading, 10) // Add left padding
            }
            
            Spacer() // Push content to bottom
            
            HStack(alignment: .bottom, spacing: 0) {
                // Today and the next 6 days
                ForEach(0...6, id: \.self) { offset in
                    dayView(offset: offset, isLarge: offset <= 1, useChineseText: useChineseText)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .containerBackground(for: .widget) {
            // Use direct color scheme detection for the background
            if colorScheme == .dark {
                Color(red: 0.11, green: 0.11, blue: 0.12) // iOS native dark background color
            } else {
                Color.white
            }
        }
    }
    
    // Changed function signature to use named parameters
    private func dayView(offset: Int, isLarge: Bool, useChineseText: Bool) -> some View {
        let calendar = Calendar.current
        
        // Use the entry's date (which is start of day) for consistency
        let date = calendar.date(byAdding: .day, value: offset, to: entry.date) ?? entry.date
        
        // Use the new isWorkDay method
        let isWorkDay = entry.isWorkDay(forDate: date)
        
        let dayOfWeek = calendar.component(.weekday, from: date)
        
        // Use localized day names based on language preference
        let dayName: String
        if offset == 0 {
            dayName = useChineseText ? "今天" : "Today"
        } else {
            // For other days use short weekday symbols
            if useChineseText {
                let chineseWeekdaySymbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
                dayName = chineseWeekdaySymbols[dayOfWeek - 1]
            } else {
                dayName = calendar.shortWeekdaySymbols[dayOfWeek - 1]
            }
        }
        
        let dayNum = calendar.component(.day, from: date)
        
        let isToday = offset == 0
        
        return VStack(spacing: 4) {
            Text(dayName)
                .font(.system(size: isLarge ? 13 : 10))
                .fontWeight(.medium)
                .foregroundColor(isToday ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            ZStack {
                Circle()
                    .fill(isWorkDay ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
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
    @Environment(\.colorScheme) var colorScheme
    // Use direct UserDefaults access with a non-optional default
    private let userDefaults = UserDefaults(suiteName: appGroupID) ?? UserDefaults.standard
    
    // Get the custom work term from UserDefaults, or use default if not set
    private var customWorkTerm: String {
        userDefaults.string(forKey: customWorkTermKey) ?? "上班"
    }
    
    // Helper to replace "上班" with custom term
    private func customizeWorkTerm(_ text: String) -> String {
        if customWorkTerm == "上班" {
            return text
        }
        return text.replacingOccurrences(of: "上班", with: customWorkTerm)
    }
    
    var body: some View {
        // Debug the language preference directly
        let langPref = userDefaults.integer(forKey: languagePreferenceKey)
        let useChineseText = AppLanguage.shouldUseChineseText(langPref)
        
        // Debug output
        print("Small week widget language preference: \(langPref), useChineseText: \(useChineseText)")
        print("Small week widget custom work term: \(customWorkTerm)")
        print("SmallWeekWidgetView detected colorScheme: \(colorScheme == .dark ? "dark" : "light")")
        
        return VStack(spacing: 0) {
            // Add the title at the top - only show in Chinese
            if useChineseText {
                Text(customizeWorkTerm("这几天上班吗？"))
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary) // Make text gray
                    .frame(maxWidth: .infinity, alignment: .leading) // Align to left
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .padding(.leading, 10) // Add left padding
            }
            
            Spacer() // Push content to bottom
            
            HStack(alignment: .bottom, spacing: 4) {
                // Today and tomorrow only
                ForEach(0...1, id: \.self) { offset in
                    dayView(offset: offset, useChineseText: useChineseText)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .containerBackground(for: .widget) {
            // Use direct color scheme detection for the background
            if colorScheme == .dark {
                Color(red: 0.11, green: 0.11, blue: 0.12) // iOS native dark background color
            } else {
                Color.white
            }
        }
    }
    
    // Changed function signature to use named parameters
    private func dayView(offset: Int, useChineseText: Bool) -> some View {
        let calendar = Calendar.current
        
        // Use the entry's date (which is start of day) for consistency
        let date = calendar.date(byAdding: .day, value: offset, to: entry.date) ?? entry.date
        
        // Use the new isWorkDay method
        let isWorkDay = entry.isWorkDay(forDate: date)
        
        // Use "Today" and "Tomorrow" for clarity - respect language
        let dayName: String
        if useChineseText {
            dayName = offset == 0 ? "今天" : "明天"
        } else {
            dayName = offset == 0 ? "Today" : "Tomorrow"
        }
        
        let dayNum = calendar.component(.day, from: date)
        
        let isToday = offset == 0
        
        return VStack(spacing: 8) {
            Text(dayName)
                .font(.system(size: 14))
                .fontWeight(.medium)
                .foregroundColor(isToday ? .primary : .secondary)
            
            ZStack {
                Circle()
                    .fill(isWorkDay ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
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
            // Log color scheme for debugging
            let colorScheme = entry.preferredColorScheme ?? .light
            print("TodayStatusWidget using color scheme: \(colorScheme == .dark ? "dark" : "light")")
            
            return TodayWidgetView(entry: entry)
                .environment(\.colorScheme, colorScheme)
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
            // Log color scheme for debugging
            let colorScheme = entry.preferredColorScheme ?? .light
            print("WeekOverviewWidget using color scheme: \(colorScheme == .dark ? "dark" : "light")")
            
            return WorkdayQWidgetEntryView(entry: entry)
                .environment(\.colorScheme, colorScheme)
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
    @Attribute(.unique) var date: Date
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

// Helper function to load data from UserDefaults as backup
private func loadWorkDaysFromUserDefaults() -> [WorkDayStruct]? {
    guard let sharedDefaults = UserDefaults(suiteName: appGroupID) else {
        return nil
    }
    
    // Try to load serialized work day data
    if let savedData = sharedDefaults.data(forKey: "cachedWorkDays") {
        do {
            // Attempt to decode the data
            if let decodedData = try NSKeyedUnarchiver.unarchivedObject(
                ofClasses: [NSArray.self, NSDate.self, NSNumber.self, NSString.self],
                from: savedData) as? [[String: Any]] {
                
                // Convert the dictionaries to WorkDayStruct objects
                var workDays: [WorkDayStruct] = []
                
                for dict in decodedData {
                    if let date = dict["date"] as? Date,
                       let isWorkDay = dict["isWorkDay"] as? Bool {
                        let note = dict["note"] as? String
                        workDays.append(WorkDayStruct(
                            date: date,
                            isWorkDay: isWorkDay,
                            note: note
                        ))
                    }
                }
                
                print("Widget loaded \(workDays.count) work days from UserDefaults")
                return workDays
            }
        } catch {
            print("Widget error decoding UserDefaults data: \(error)")
        }
    }
    
    return nil
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
