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
let holidayPreferenceKey = "holidayPreference" // Add holiday preference key
let holidayDataKey = "holidayData" // Add holiday data key
let showStatusOpacityDifferenceKey = "showStatusOpacityDifference" // Add opacity difference setting key
let weekPatternKey = "weekPattern" // Add key for custom week pattern storage
let defaultWorkdaySettingKey = "defaultWorkdaySetting" // Setting for workday pattern type (0,1,2)
let shiftPatternKey = "shiftPattern" // Key for shift work pattern storage
let shiftStartDateKey = "shiftStartDate" // Key for shift pattern start date
let numberOfShiftsKey = "numberOfShifts" // Key for number of shifts (2, 3, or 4)
let enablePartialDayFeatureKey = "enablePartialDayFeature" // Key for enabling partial day features
let partialDayPatternKey = "partialDayPattern" // Key for partial day shift patterns

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
            
            // Load holiday preference and data
            let holidayPref = sharedDefaults?.integer(forKey: holidayPreferenceKey) ?? 0
            var holidayData: [HolidayInfo] = []
            
            if holidayPref != 0 { // If a holiday calendar is selected
                if let holidayDataRaw = sharedDefaults?.data(forKey: holidayDataKey) {
                    do {
                        let decoder = JSONDecoder()
                        holidayData = try decoder.decode([HolidayInfo].self, from: holidayDataRaw)
                        print("Widget loaded \(holidayData.count) holiday items")
                    } catch {
                        print("Failed to decode holiday data in widget: \(error.localizedDescription)")
                    }
                }
            }
            
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
                startOfWeekPreference: startOfWeekPref,
                holidayData: holidayData
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
    let holidayData: [HolidayInfo] // Add holiday data
    
    // Use initializer with default parameters
    init(date: Date, workDays: [WorkDayStruct], lastUpdateTime: TimeInterval, preferredColorScheme: ColorScheme? = nil, startOfWeekPreference: Int = 0, holidayData: [HolidayInfo] = []) {
        self.date = date
        self.workDays = workDays
        self.lastUpdateTime = lastUpdateTime
        self.preferredColorScheme = preferredColorScheme
        self.startOfWeekPreference = startOfWeekPreference
        self.holidayData = holidayData
    }
    
    var todayWorkDay: WorkDayStruct? {
        let calendar = Calendar.current
        return workDays.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    // Get the work status for today with default rules
    var isTodayWorkDay: Bool {
        // Use the unified function for consistency
        return isWorkDay(forDate: date)
    }
    
    // Get note for a specific date without affecting work status
    func getNoteForDate(_ date: Date) -> String? {
        let calendar = Calendar.current
        return workDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) })?.note
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
                // Use the unified isWorkDay function to respect all three tiers
                let status = isWorkDay(forDate: targetDate)
                print("Looking for day at offset \(offset): \(targetDate), using calculated status: \(status)")
            }
        }
        return result
    }
    
    // Check if a specific date is a workday, using stored data or default rules
    /// Determine if a date is a work day using the three-tier priority system
    /// 1. First check explicit user-set entry (highest priority)
    /// 2. Then check holiday data (medium priority)
    /// 3. Finally fall back to default weekday rules (lowest priority)
    /// - Parameter date: The date to check
    /// - Returns: true if it's a work day, false if it's an off day
    func isWorkDay(forDate date: Date) -> Bool {
        let calendar = Calendar.current
        
        // First check if we have an explicit user record with dayStatus > 0 (highest priority)
        if let explicitDay = workDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            if explicitDay.dayStatus > 0 {
                return explicitDay.dayStatus > 1
            }
            // Otherwise, fall through for days with notes but default status
        }
        
        // Next check holiday data (medium priority)
        if let holidayInfo = holidayData.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            return holidayInfo.isWorkDay
        }
        
        // Force refresh the pattern manager from UserDefaults before using it
        WidgetPatternManager.shared.reloadFromUserDefaults()
        
        // Fall back to pattern rules (lowest priority)
        return isDefaultWorkDay(date)
    }
    
    // Add function to get holiday information for a specific date
    func getHolidayInfo(for date: Date) -> HolidayInfo? {
        let calendar = Calendar.current
        return holidayData.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    // Add function to get system note for a date (holiday name)
    func getSystemNote(for date: Date) -> String? {
        return getHolidayInfo(for: date)?.name
    }
    
    // Get partial day shifts for a particular date
    func getPartialDayShifts(forDate date: Date) -> [Int] {
        let calendar = Calendar.current
        
        // First check if we have an explicit user record
        if let workDay = workDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            if workDay.dayStatus == 3 && workDay.shifts != nil {
                // Return the user-specified shifts for this partial day
                return workDay.shifts!
            } else if workDay.dayStatus == 2 {
                // For a full work day, return all shifts based on the number of shifts
                return getFullDayShifts(for: WidgetPatternManager.shared.numberOfShifts)
            } else if workDay.dayStatus == 1 {
                // Off day, return empty array
                return []
            }
        }
        
        // Fall back to default pattern
        return getDefaultPartialDayShifts(date)
    }
    
    // Helper function to get all shifts for a full day
    private func getFullDayShifts(for numberOfShifts: Int) -> [Int] {
        switch numberOfShifts {
        case 2: return [2, 4]          // morning and night
        case 3: return [2, 3, 4]       // morning, noon, night
        case 4: return [1, 2, 3, 4]    // early morning, morning, noon, night
        default: return [2, 4]         // default to 2-shift
        }
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
    @Environment(\.widgetFamily) var family // Add widget family environment
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
        
        // Conditional date style based on widget size
        if family == .systemSmall {
            // For small widgets, show only month and day
            formatter.dateFormat = AppLanguage.shouldUseChineseText(userDefaults.integer(forKey: languagePreferenceKey)) ? 
                "M月d日" : "MMM d" // Chinese: "5月10日", English: "May 10"
        } else {
            // For medium widgets, keep the current medium date style
            formatter.dateStyle = .full
        }
        
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
        let isSmallWidget = family == .systemSmall // Check if this is a small widget
        
        // Debug output - this will appear in the console when widget updates
        print("Widget language preference: \(langPref), useChineseText: \(useChineseText)")
        print("Widget custom work term: \(customWorkTerm)")
        print("TodayWidgetView detected colorScheme: \(colorScheme == .dark ? "dark" : "light")")
        
        return VStack(alignment: .leading, spacing: 4) {
            Text(dateFormatter.string(from: Date()))
                .font(.headline)
                .padding(.bottom, 4)
                .padding(.top, 4)
            Spacer()
            
            // Use Chinese format or English format based on language preference
            if useChineseText {
                Text("今天")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .padding(.bottom, -6)
                    .fontWeight(.semibold)
            } else {
                // For English, use shorter text in small widget
                Text(isSmallWidget ? "Today" : "Today is a")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, -6)
                    .fontWeight(.semibold)
                    // Remove padding to match app styling
            }
            
            
            HStack {
                let isWorkDay = entry.isTodayWorkDay
                
                // Use different text format for Chinese
                if useChineseText {
                    HStack(alignment: .lastTextBaseline, spacing: 16) {
                        Text(customizeWorkTerm(isWorkDay ? "要上班" : "不上班"))
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(isWorkDay ? .red : .green)
                            .padding(.top, 0)
                        
                        // Add holiday note if available - but only in medium widget
                        if let holidayNote = entry.getSystemNote(for: entry.date), !isSmallWidget {
                            Text(holidayNote)
                                .font(.title3)
                                .foregroundColor(.gray)
                        }
                    }
                } else {
                    // Now make English layout match the app
                    HStack(alignment: .lastTextBaseline, spacing: 16) {
                        // For English, use shorter text in small widget
                        Text(isSmallWidget ? 
                             (isWorkDay ? "Work" : "Rest") : 
                             (isWorkDay ? "Workday" : "Day Off"))
                            .font(.largeTitle) // Update to match app
                            .fontWeight(.bold)
                            .foregroundColor(isWorkDay ? .red : .green)
                            
                        // Add holiday note if available - but only in medium widget
                        if let holidayNote = entry.getSystemNote(for: entry.date), !isSmallWidget {
                            Text(holidayNote)
                                .font(.title3)
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Spacer()
                
                // Only show the circle if NOT in a small widget
                if !isSmallWidget {
                    if WidgetPatternManager.shared.enablePartialDayFeature {
                        ShiftCircle(
                            shifts: entry.getPartialDayShifts(forDate: entry.date),
                            numberOfShifts: WidgetPatternManager.shared.numberOfShifts,
                            size: 50,
                            baseOpacity: 0.8,
                            dividerColor: colorScheme == .dark ? 
                                Color(UIColor.systemGray6) : Color.white.opacity(0.5)
                        )
                    } else {
                        Circle()
                            .fill(isWorkDay ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                            .frame(width: 50, height: 50)
                            .padding(.bottom, 2)
                    }
                }
            }
            
            if let note = entry.getNoteForDate(entry.date), !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.top, -5)
            } else if isSmallWidget, let holidayNote = entry.getSystemNote(for: entry.date) {
                // For small widgets, if no user note exists, show the holiday note as fallback
                Text(holidayNote)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.top, -5)
            } 
          
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 16)
        .frame(height: 155)
        .frame(maxWidth: .infinity)
        .containerBackground(for: .widget) {
            // Set explicit colors but respect the environment colorScheme
            if colorScheme == .dark {
                Color(red: 0.11, green: 0.11, blue: 0.12) // Custom dark mode color
            } else {
                Color.white // Light mode color
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
            } else {
                    Text(customizeWorkTerm("Working these days?"))
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
            // Set explicit colors but respect the environment colorScheme
            if colorScheme == .dark {
                Color(red: 0.11, green: 0.11, blue: 0.12) // Custom dark mode color
            } else {
                Color.white // Light mode color
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
                if WidgetPatternManager.shared.enablePartialDayFeature {
                    ShiftCircle(
                        shifts: entry.getPartialDayShifts(forDate: date),
                        numberOfShifts: WidgetPatternManager.shared.numberOfShifts,
                        size: isLarge ? 44 : 32,
                        baseOpacity: 0.8,
                        dividerColor: colorScheme == .dark ? 
                            Color(UIColor.systemGray6).opacity(0.5) : Color.white.opacity(0.5)
                    )
                } else {
                    Circle()
                        .fill(isWorkDay ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                        .frame(width: isLarge ? 44 : 32, height: isLarge ? 44 : 32)
                }
                
                Text("\(dayNum)")
                    .font(.system(size: isLarge ? 18 : 14, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .frame(height: isLarge ? 80 : 70) // Fixed height for better alignment
        .padding(.horizontal, 4)
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
            // if useChineseText {
            //     Text(customizeWorkTerm("上班吗？"))
            //         .font(.headline)
            //         .fontWeight(.medium)
            //         .foregroundColor(.secondary) // Make text gray
            //         .frame(maxWidth: .infinity, alignment: .leading) // Align to left
            //         .padding(.top, 8)
            //         .padding(.bottom, 4)
            //         .padding(.leading, 10) // Add left padding
            // }
            
            Spacer() // Push content to bottom
            
            HStack(alignment: .center, spacing: -20) { // Changed alignment from .bottom to .center
                // Today and tomorrow only
                ForEach(0...1, id: \.self) { offset in
                    dayView(offset: offset, useChineseText: useChineseText)
                        .frame(maxWidth: .infinity)
                        .offset(y: offset == 0 ? -60 : 0) // Apply negative offset to Today to position it higher
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .containerBackground(for: .widget) {
            // Set explicit colors but respect the environment colorScheme
            if colorScheme == .dark {
                Color(red: 0.11, green: 0.11, blue: 0.12) // Custom dark mode color
            } else {
                Color.white // Light mode color
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
        
        let dayOfWeek = calendar.component(.weekday, from: date)
        
        // Use localized day names based on language preference
        _ = useChineseText ? "今天" : "Today" // Replace with _ to ignore unused value
        
        let dayNum = calendar.component(.day, from: date)
        
        let isToday = offset == 0
        
        // Set sizes based on whether it's today or tomorrow
        let circleSize: CGFloat = isToday ? 90 : 60
        let fontSize: CGFloat = isToday ? 50 : 30
        _ = isToday ? Font.Weight.light : Font.Weight.regular // Now Swift knows which type these members belong to

        return VStack(spacing: 0) {
            // Text(dayName)
            //     .font(.system(size: isToday ? 14 : 13))
            //     .fontWeight(.medium)
            //     .foregroundColor(isToday ? .primary : .secondary)
            
            ZStack {
                if WidgetPatternManager.shared.enablePartialDayFeature {
                    ShiftCircle(
                        shifts: entry.getPartialDayShifts(forDate: date),
                        numberOfShifts: WidgetPatternManager.shared.numberOfShifts,
                        size: circleSize,
                        baseOpacity: 0.8,
                        dividerColor: colorScheme == .dark ? 
                            Color(UIColor.systemGray6) : Color.white.opacity(0.5)
                    )
                } else {
                    Circle()
                    .fill(isWorkDay ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                    .frame(width: circleSize, height: circleSize)
                }
                Text("\(dayNum)")
                    .font(.system(size: fontSize, weight: .light))
                    .foregroundColor(.white)
            }
        }
        .frame(height: 30) // Fixed height for better alignment
        .padding(.horizontal, 2)
        // .background(
        //     Group {
        //         if isToday {
        //             Rectangle()
        //                 .fill(Color(UIColor.systemGray6))
        //                 .cornerRadius(8)
        //         } else {
        //             Color.clear
        //         }
        //     }
        // )
    }
}

// Create two separate widgets
struct TodayStatusWidget: Widget {
    let kind: String = "TodayStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if let explicitColorScheme = entry.preferredColorScheme {
                // Only set explicitly if user chose light or dark mode
                TodayWidgetView(entry: entry)
                    .environment(\.colorScheme, explicitColorScheme)
            } else {
                // For "follow system", don't override the environment
                TodayWidgetView(entry: entry)
            }
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
            if let explicitColorScheme = entry.preferredColorScheme {
                // Only set explicitly if user chose light or dark mode
                WorkdayQWidgetEntryView(entry: entry)
                    .environment(\.colorScheme, explicitColorScheme)
            } else {
                // For "follow system", don't override the environment
                WorkdayQWidgetEntryView(entry: entry)
            }
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
    let dayStatus: Int
    let note: String?
    let shifts: [Int]?
    
    var isWorkDay: Bool {
        return dayStatus == 2 || dayStatus == 3
    }
    
    init(date: Date, dayStatus: Int = 0, note: String? = nil, shifts: [Int]? = nil, id: UUID = UUID()) {
        self.id = id
        self.date = date
        self.dayStatus = dayStatus
        self.note = note
        self.shifts = shifts
    }
    
    // For backward compatibility
    init(date: Date, isWorkDay: Bool = false, note: String? = nil, id: UUID = UUID()) {
        self.id = id
        self.date = date
        self.dayStatus = isWorkDay ? 2 : 1
        self.note = note
        self.shifts = nil
    }
}

// Define the actual SwiftData model for access
// IMPORTANT: Must EXACTLY match the name in the main app
@Model
final class WorkDay {
    @Attribute(.unique) var date: Date
    var dayStatus: Int
    var note: String?
    var shifts: [Int]?
    
    var isWorkDay: Bool {
        return dayStatus == 2
    }
    
    init(date: Date, dayStatus: Int = 0, note: String? = nil) {
        self.date = date
        self.dayStatus = dayStatus
        self.note = note
    }
    
    convenience init(date: Date, isWorkDay: Bool = false, note: String? = nil) {
        self.init(date: date, dayStatus: isWorkDay ? 2 : 1, note: note)
    }
}

// Function to convert from SwiftData model to our struct representation
fileprivate func convertToWorkDayStruct(_ workDayModel: WorkDay) -> WorkDayStruct {
    return WorkDayStruct(
        date: workDayModel.date,
        dayStatus: workDayModel.dayStatus,
        note: workDayModel.note,
        shifts: workDayModel.shifts
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
                       let dayStatus = dict["dayStatus"] as? Int {
                        let note = dict["note"] as? String
                        workDays.append(WorkDayStruct(
                            date: date,
                            dayStatus: dayStatus,
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

// Add HolidayInfo struct definition in the widget file
struct HolidayInfo: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let name: String
    let isWorkDay: Bool  // true for workday (调休 to work), false for rest day (holiday)
    let type: HolidayType
    
    enum CodingKeys: String, CodingKey {
        case date, name, isWorkDay, type
    }
}

enum HolidayType: String, Codable {
    case holiday = "holiday"      // Regular holiday (休)
    case adjustedRest = "rest"    // Regular rest day (周末)
    case adjustedWork = "work"    // Adjusted workday (调休 to work - 班)
}

// Add a simplified WorkdayPatternManager for the widget (read-only version)
class WidgetPatternManager {
    static let shared = WidgetPatternManager()
    
    // Properties to store pattern data
    var pattern: [Bool] = [false, true, true, true, true, true, false]
    var workdayMode: Int = 0 // 0=default, 1=custom, 2=shift
    var shiftPattern: [Bool] = [true, true, true, true, false, false, false] // Default 4-on, 3-off
    var shiftStartDate: Date = Calendar.current.startOfDay(for: Date()) // Default to today
    var numberOfShifts: Int = 2 // Default to 2 shifts
    
    // Add the partial day feature toggle
    var enablePartialDayFeature: Bool = false // Default to disabled
    
    // Add the partial day pattern property
    var partialDayPattern: [[Int]] = [[2, 4], [3], []]
    
    // Load the data from UserDefaults on initialization
    init() {
        reloadFromUserDefaults()
    }
    
    // Method to load pattern data from UserDefaults
    func reloadFromUserDefaults() {
        if let defaults = UserDefaults(suiteName: appGroupID) {
            // Load workday mode
            workdayMode = defaults.integer(forKey: defaultWorkdaySettingKey)
            
            // Load weekly pattern
            if let patternString = defaults.string(forKey: weekPatternKey) {
                pattern = patternString.map { $0 == "1" }
            } else {
                // Default pattern if none exists
                pattern = [false, true, true, true, true, true, false] // Sun-Sat (Sun/Sat off)
            }
            
            // Load shift pattern
            if let shiftPatternString = defaults.string(forKey: shiftPatternKey) {
                shiftPattern = shiftPatternString.map { $0 == "1" }
            } else {
                // Default shift pattern if none exists
                shiftPattern = [true, true, true, true, false, false, false] // 4 on, 3 off
            }
            
            // Load shift start date
            if let shiftStartTimestamp = defaults.object(forKey: shiftStartDateKey) as? TimeInterval {
                shiftStartDate = Date(timeIntervalSince1970: shiftStartTimestamp)
            } else {
                // Default to today if none exists
                shiftStartDate = Calendar.current.startOfDay(for: Date())
            }
            
            // Load number of shifts
            numberOfShifts = defaults.integer(forKey: numberOfShiftsKey)
            if numberOfShifts < 2 || numberOfShifts > 4 {
                numberOfShifts = 2 // Ensure valid range
            }
            
            // Load partial day feature setting
            enablePartialDayFeature = defaults.bool(forKey: enablePartialDayFeatureKey)
            
            // Load partial day pattern
            if let patternData = defaults.data(forKey: partialDayPatternKey),
               let decodedPattern = try? JSONDecoder().decode([[Int]].self, from: patternData) {
                partialDayPattern = decodedPattern
            }
        }
    }
    
    // Add a helper method to WidgetPatternManager to convert between patterns if needed
    func getValidShiftsForNumberOfShifts() -> [Int] {
        switch numberOfShifts {
        case 2: return [2, 4]          // morning and night
        case 3: return [2, 3, 4]       // morning, noon, night
        case 4: return [1, 2, 3, 4]    // early morning, morning, noon, night
        default: return [2, 4]         // default to 2-shift
        }
    }
}

// Helper to determine if a date is a workday by default
// Now checks if user wants to use custom pattern or standard pattern
func isDefaultWorkDay(_ date: Date) -> Bool {
    // Get the shared pattern manager
    let manager = WidgetPatternManager.shared
    
    switch manager.workdayMode {
    case 1:
        return isDefaultWorkDayWithUserDefineWeek(date, pattern: manager.pattern)
    case 2:
        return isDefaultWorkdayShift(date)
    case 0, _: // Default case
        return isDefaultWorkDayDefault(date)
    }
}

// Standard workday function (Monday-Friday)
func isDefaultWorkDayDefault(_ date: Date) -> Bool {
    let weekday = Calendar.current.component(.weekday, from: date)
    // 1 = Sunday, 2 = Monday, ..., 7 = Saturday
    return weekday >= 2 && weekday <= 6 // Monday to Friday
}

// Helper to determine if a date is a workday based on user-defined weekly pattern
func isDefaultWorkDayWithUserDefineWeek(_ date: Date, pattern: [Bool]? = nil) -> Bool {
    // If pattern is provided, use it
    if let pattern = pattern, pattern.count == 7 {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        // weekday is 1-based (1 = Sunday, 2 = Monday, ..., 7 = Saturday)
        return pattern[weekday - 1]
    }
    
    // Otherwise, use the existing function that reads from UserDefaults
    let weekPatternString = UserDefaults(suiteName: appGroupID)?.string(forKey: weekPatternKey) ?? "0111110"
    let weekPattern = weekPatternString.map { $0 == "1" }
    
    guard weekPattern.count == 7 else {
        return isDefaultWorkDayDefault(date)
    }
    
    let calendar = Calendar.current
    let weekday = calendar.component(.weekday, from: date)
    
    return weekPattern[weekday - 1]
}

// Function to determine workday status based on shift pattern
func isDefaultWorkdayShift(_ date: Date) -> Bool {
    // Get the shared pattern manager to access the shift pattern and start date
    let patternManager = WidgetPatternManager.shared
    let shiftPattern = patternManager.shiftPattern
    let shiftStartDate = patternManager.shiftStartDate
    
    // Ensure we have a valid pattern
    guard !shiftPattern.isEmpty else {
        return isDefaultWorkDayDefault(date) // Fallback to standard pattern if no shift pattern
    }
    
    // Calculate days since the shift pattern start date
    let calendar = Calendar.current
    let startDay = calendar.startOfDay(for: shiftStartDate)
    let targetDay = calendar.startOfDay(for: date)
    
    // Get days between the dates (could be negative if date is before start date)
    let components = calendar.dateComponents([.day], from: startDay, to: targetDay)
    guard let daysSinceStart = components.day else {
        return isDefaultWorkDayDefault(date) // Fallback if calculation fails
    }
    
    // Handle dates before the shift start date by working backwards
    if daysSinceStart < 0 {
        // For negative days, we need to carefully calculate the modulo
        // to ensure we wrap around correctly in the pattern
        let patternLength = shiftPattern.count
        let adjustedIndex = (patternLength - (abs(daysSinceStart) % patternLength)) % patternLength
        return shiftPattern[adjustedIndex]
    } else {
        // For dates on or after the shift start date, simple modulo works
        let patternIndex = daysSinceStart % shiftPattern.count
        return shiftPattern[patternIndex]
    }
}

// Add this function to match the one in ContentView
func getDefaultPartialDayShifts(_ date: Date) -> [Int] {
    let manager = WidgetPatternManager.shared
    let partialDayPattern = manager.partialDayPattern
    
    guard !partialDayPattern.isEmpty else {
        // If no pattern exists, return empty array (no shifts)
        return []
    }
    
    // The date when the pattern starts
    let startDate = manager.shiftStartDate
    
    // Calculate days between start date and target date
    let calendar = Calendar.current
    let startDay = calendar.startOfDay(for: startDate)
    let targetDay = calendar.startOfDay(for: date)
    
    // Get days between the dates
    let components = calendar.dateComponents([.day], from: startDay, to: targetDay)
    guard let days = components.day else {
        return [] // Fallback if calculation fails
    }
    
    // If days is negative, the date is before the start date
    if days < 0 {
        // For negative days, we need to calculate the modulo correctly
        let patternLength = partialDayPattern.count
        let adjustedIndex = (patternLength - (abs(days) % patternLength)) % patternLength
        return partialDayPattern[adjustedIndex]
    } else {
        // Calculate which day in the pattern this date represents
        let patternIndex = days % partialDayPattern.count
        // Return the shifts for this day from the pattern
        return partialDayPattern[patternIndex]
    }
}

///
///
///
///
///
///
///

//
//  ShiftComponents.swift
//  WorkdayQ
//
//  Components related to partial day shift visualization
//

import SwiftUI

/// Displays a circle with segments representing different shifts in a day
public struct ShiftCircle: View {
    let shifts: [Int]?
    let numberOfShifts: Int
    let size: CGFloat
    let baseOpacity: Double
    var dividerColor: Color = Color.primary.opacity(0.5)
    
    public var body: some View {
        ZStack {
            // Base circle - green for rest days (empty shifts), light red background otherwise
            Circle()
                .fill(shifts?.isEmpty ?? true ? Color.green.opacity(0.8) : Color.red.opacity(0.4))
                .frame(width: size, height: size)
            
            // Only show shift segments if there are shifts
            if let shifts = shifts, !shifts.isEmpty {
                // Parallel division view with rotation
                ParallelDividedCircle(
                    shifts: shifts,
                    numberOfShifts: numberOfShifts,
                    size: size,
                    baseOpacity: baseOpacity,
                    dividerColor: dividerColor
                )
                .rotationEffect(Angle(degrees: -30)) // Rotate the entire segment display
            }
        }
    }
}

/// Handles the division of circle into parallel segments based on shift count
struct ParallelDividedCircle: View {
    let shifts: [Int]?
    let numberOfShifts: Int
    let size: CGFloat
    let baseOpacity: Double
    var dividerColor: Color = Color.primary.opacity(0.5)
    
    // Get the valid shift numbers based on numberOfShifts
    var validShiftNumbers: [Int] {
        switch numberOfShifts {
        case 2:
            return [2, 4]          // morning and night
        case 3:
            return [2, 3, 4]       // morning, noon, night
        case 4:
            return [1, 2, 3, 4]    // early morning, morning, noon, night
        default:
            return [2, 4]          // default to 2-shift
        }
    }
    
    var body: some View {
        ZStack {
            // Create each slice based on active shifts
            ForEach(0..<validShiftNumbers.count, id: \.self) { index in
                let shiftNumber = validShiftNumbers[index]
                let isActive = shifts?.contains(shiftNumber) ?? false
                
                ParallelSlice(
                    sliceNumber: index,
                    totalSlices: validShiftNumbers.count,
                    isActive: isActive
                )
                .fill(isActive ? Color.red.opacity(baseOpacity) : Color.clear)
                .frame(width: size, height: size)
            }
            
            // Add divider lines between segments with the specified color
            ForEach(1..<validShiftNumbers.count, id: \.self) { index in
                // Calculate Y position for each divider
                let yOffset = (size / CGFloat(validShiftNumbers.count)) * CGFloat(index) - (size / 2)
                
                // Draw a horizontal line with the specified divider color
                Rectangle()
                    .fill(dividerColor)
                    .frame(width: size, height: 1.5)
                    .offset(y: yOffset)
            }
        }
    }
}

/// Individual slice shape for a segment of the shift circle
struct ParallelSlice: Shape {
    let sliceNumber: Int
    let totalSlices: Int
    let isActive: Bool
    
    func path(in rect: CGRect) -> Path {
        let diameter = min(rect.width, rect.height)
        let radius = diameter / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        
        // Calculate spacing between horizontal segments
        let sliceHeight = diameter / CGFloat(totalSlices)
        
        // Calculate the top position for this slice
        let topY = center.y - radius + (sliceHeight * CGFloat(sliceNumber))
        let bottomY = topY + sliceHeight
        
        // Create path for this slice
        var path = Path()
        
        // Create a horizontal slice across the circle
        let leftX = center.x - radius
        let rightX = center.x + radius
        
        path.move(to: CGPoint(x: leftX, y: topY))
        path.addLine(to: CGPoint(x: rightX, y: topY))
        path.addLine(to: CGPoint(x: rightX, y: bottomY))
        path.addLine(to: CGPoint(x: leftX, y: bottomY))
        path.closeSubpath()
        
        // Intersect with circle
        let circlePath = Path(ellipseIn: rect)
        return path.intersection(circlePath)
    }
}
