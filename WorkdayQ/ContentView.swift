//
//  ContentView.swift
//  WorkdayQ
//
//  Created by Xueqi Li on 3/3/25.
//

import SwiftUI
import SwiftData
import WidgetKit
import UIKit  // Add UIKit import
// Import the HolidayManager module
import Foundation

// Constants for app group synchronization
let appGroupID = "group.io.azhe.WorkdayQ"
let lastUpdateKey = "lastDatabaseUpdate"
let languagePreferenceKey = "languagePreference"
let customWorkTermKey = "customWorkTerm" // Add key for custom work term storage
let appearancePreferenceKey = "appearancePreference" // Add key for dark mode preference
let startOfWeekPreferenceKey = "startOfWeekPreference" // Add key for week start preference
let showStatusOpacityDifferenceKey = "showStatusOpacityDifference" // Add key for opacity difference setting
let weekPatternKey = "weekPattern" // Add key for custom week pattern storage
let defaultWorkdaySettingKey = "defaultWorkdaySetting" // Setting for workday pattern type (0,1,2)
let appVersion = "0.7"
let useDarkIconPreferenceKey = "useDarkIconPreference" // Add key for dark icon preference
let shiftPatternKey = "shiftPattern" // Key for shift work pattern storage
let shiftStartDateKey = "shiftStartDate" // Key for shift pattern start date
let numberOfShiftsKey = "numberOfShifts" // Key for number of shifts (2, 3, or 4)
let enablePartialDayFeatureKey = "enablePartialDayFeature" // Key for enabling partial day features
let partialDayPatternKey = "partialDayPattern" // Key for partial day shift patterns

// Add extension to dismiss keyboard (place after imports, before constants)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// Helper to determine if a date is a workday by default
// Now checks if user wants to use custom pattern or standard pattern
func isDefaultWorkDay(_ date: Date, patternManager: WorkdayPatternManager? = nil) -> Bool {
    // Use the passed manager or get the shared instance
    let manager = patternManager ?? WorkdayPatternManager.shared
    
    switch manager.workdayMode {
    case 1:
        return isDefaultWorkDayWithUserDefineWeek(date, pattern: manager.pattern)
    case 2:
        return isDefaultWorkdayShift(date)
    case 0, _: // Default case
        return isDefaultWorkDayDefault(date)
    }
}

func isDefaultWorkDayDefault(_ date: Date) -> Bool {
    let weekday = Calendar.current.component(.weekday, from: date)
    // 1 = Sunday, 2 = Monday, ..., 7 = Saturday
    return weekday >= 2 && weekday <= 6 // Monday to Friday
}

// Helper to determine if a date is a workday based on user-defined weekly pattern
// Uses the weekPattern saved in UserDefaults
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
        return isDefaultWorkDay(date)
    }
    
    let calendar = Calendar.current
    let weekday = calendar.component(.weekday, from: date)
    
    return weekPattern[weekday - 1]
}

// Add this improved shift function to replace the placeholder
func isDefaultWorkdayShift(_ date: Date) -> Bool {
    // Get the shared pattern manager to access the shift pattern and start date
    let patternManager = WorkdayPatternManager.shared
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

/// Returns the default shifts for a specific date based on the partial day pattern
func getDefaultPartialDayShifts(_ date: Date) -> [Int] {
    let manager = WorkdayPatternManager.shared
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
        // For negative days, we need to carefully calculate the modulo
        // to ensure we wrap around correctly in the pattern
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

// Updated helper function to determine if a date has a specific shift
func hasShift(_ date: Date, shift: Int, workDays: [WorkDay] = []) -> Bool {
    // This references the non-existent global function, which is causing the error
    // let shifts = getPartialDayShifts(for: date, workDays: workDays)
    
    // We need to use the default pattern function directly instead
    let shifts = getDefaultPartialDayShifts(date)
    
    // Check if the requested shift is included
    return shifts.contains(shift)
}

// Language options enum
enum AppLanguage: Int, CaseIterable, Identifiable {
    case systemDefault = 0
    case english = 1
    case chinese = 2
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .systemDefault: return "Default (System)"
        case .english: return "English"
        case .chinese: return "中文 (Chinese)"
        }
    }
    
    var localeIdentifier: String? {
        switch self {
        case .systemDefault: return nil
        case .english: return "en"
        case .chinese: return "zh-Hans"
        }
    }
}

// Add an enum for appearance options after the AppLanguage enum
enum AppAppearance: Int, CaseIterable, Identifiable {
    case systemDefault = 0
    case light = 1
    case dark = 2
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .systemDefault: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .systemDefault: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// Add this class near the top of your file, after imports
class WorkdayPatternManager: ObservableObject {
    static let shared = WorkdayPatternManager()
    
    @Published var pattern: [Bool] = [false, true, true, true, true, true, false]
    @Published var workdayMode: Int = 0 // 0=default, 1=custom, 2=shift
    
    // Add shift pattern properties
    @Published var shiftPattern: [Bool] = [true, true, true, true, false, false, false] // Default 4-on, 3-off
    @Published var shiftStartDate: Date = Calendar.current.startOfDay(for: Date()) // Default to today
    
    // Add the numberOfShifts property
    @Published var numberOfShifts: Int = 2 // Default to 2 shifts
    
    // Add the partial day feature toggle
    @Published var enablePartialDayFeature: Bool = false // Default to disabled
    
    // Add the partial day pattern property
    // This is an array of arrays, where each inner array contains the shifts for a day in the pattern
    @Published var partialDayPattern: [[Int]] = [
        [2, 4], // Default pattern: Day 1 - morning and night shifts
        [3],    // Day 2 - noon shift only
        []      // Day 3 - rest day (no shifts)
    ]
    
    // Load the data from UserDefaults on initialization
    init() {
        if let defaults = UserDefaults(suiteName: appGroupID) {
            // Load workday mode
            workdayMode = defaults.integer(forKey: defaultWorkdaySettingKey)
            
            // Load weekly pattern
            if let patternString = defaults.string(forKey: weekPatternKey) {
                pattern = patternString.map { $0 == "1" }
            }
            
            // Load shift pattern
            if let shiftPatternString = defaults.string(forKey: shiftPatternKey) {
                shiftPattern = shiftPatternString.map { $0 == "1" }
            }
            
            // Load shift start date
            if let shiftStartTimestamp = defaults.object(forKey: shiftStartDateKey) as? TimeInterval {
                shiftStartDate = Date(timeIntervalSince1970: shiftStartTimestamp)
            }
            
            // Load number of shifts (default to 2 if not set)
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
    
    // Update pattern and save to UserDefaults
    func updatePattern(_ newPattern: [Bool]) {
        guard newPattern.count == 7 else { return }
        pattern = newPattern
        saveToUserDefaults()
    }
    
    // Update mode and save to UserDefaults
    func updateMode(_ newMode: Int) {
        guard (0...2).contains(newMode) else { return }
        workdayMode = newMode
        saveToUserDefaults()
    }
    
    // Reset pattern to default
    func resetToDefault() {
        pattern = [false, true, true, true, true, true, false]
        saveToUserDefaults()
    }
    
    // Update shift pattern and save to UserDefaults
    func updateShiftPattern(_ newPattern: [Bool]) {
        guard !newPattern.isEmpty else { return }
        shiftPattern = newPattern
        saveToUserDefaults()
    }
    
    // Update shift start date and save to UserDefaults
    func updateShiftStartDate(_ newDate: Date) {
        shiftStartDate = Calendar.current.startOfDay(for: newDate)
        saveToUserDefaults()
    }
    
    // Save current state to UserDefaults
    func saveToUserDefaults() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        
        // Save workday mode
        defaults.set(workdayMode, forKey: defaultWorkdaySettingKey)
        
        // Save weekly pattern
        let patternString = pattern.map { $0 ? "1" : "0" }.joined()
        defaults.set(patternString, forKey: weekPatternKey)
        
        // Save shift pattern
        let shiftPatternString = shiftPattern.map { $0 ? "1" : "0" }.joined()
        defaults.set(shiftPatternString, forKey: shiftPatternKey)
        
        // Save shift start date
        defaults.set(shiftStartDate.timeIntervalSince1970, forKey: shiftStartDateKey)
        
        // Save number of shifts
        defaults.set(numberOfShifts, forKey: numberOfShiftsKey)
        
        // Save partial day feature setting
        defaults.set(enablePartialDayFeature, forKey: enablePartialDayFeatureKey)
        
        // Save partial day pattern
        if let encodedPattern = try? JSONEncoder().encode(partialDayPattern) {
            defaults.set(encodedPattern, forKey: partialDayPatternKey)
        }
        
        // Force synchronize to ensure immediate write to disk
        defaults.synchronize()
        
        // Reload widgets immediately
        WidgetCenter.shared.reloadAllTimelines()
        
        print("WorkdayPatternManager: Saved all pattern data")
    }
    
    // Add a method to explicitly reload from UserDefaults
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
            
            // Load number of shifts (default to 2 if not set)
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
            } else {
                // Default pattern if none exists
                partialDayPattern = [[2, 4], [2, 4],[2, 4],[2, 4], [],[],[]]
            }
            
            // Save defaults if they didn't exist
            saveToUserDefaults()
        }
    }
    
    // Add a method to toggle the partial day feature
    func togglePartialDayFeature() {
        enablePartialDayFeature.toggle()
        saveToUserDefaults()
    }

    // Convert from shift pattern (Boolean array) to partial day pattern (array of Int arrays)
    func convertShiftToPartialDayPattern() {
        // Create a new partial day pattern based on the shift pattern
        var newPartialDayPattern: [[Int]] = []
        
        // Get the valid shift numbers based on numberOfShifts
        let validShifts: [Int] = {
            switch numberOfShifts {
            case 2: return [2, 4]          // morning and night
            case 3: return [2, 3, 4]       // morning, noon, night
            case 4: return [1, 2, 3, 4]    // early morning, morning, noon, night
            default: return [2, 4]         // default to 2-shift
            }
        }()
        
        // For each day in the shift pattern
        for isWorkDay in shiftPattern {
            if isWorkDay {
                // If it's a work day, assign all available shifts by default
                newPartialDayPattern.append(validShifts)
            } else {
                // If it's a rest day, create an empty array
                newPartialDayPattern.append([])
            }
        }
        
        // Update the partial day pattern
        partialDayPattern = newPartialDayPattern
    }

    // Convert from partial day pattern (array of Int arrays) to shift pattern (Boolean array)
    func convertPartialDayToShiftPattern() {
        // Create a new shift pattern based on the partial day pattern
        var newShiftPattern: [Bool] = []
        
        // For each day in the partial day pattern
        for dayShifts in partialDayPattern {
            // If the day has any shifts, it's a work day
            newShiftPattern.append(!dayShifts.isEmpty)
        }
        
        // If the partial day pattern is empty or of different length, maintain the current shift pattern
        if newShiftPattern.isEmpty || newShiftPattern.count != shiftPattern.count {
            return
        }
        
        // Update the shift pattern
        shiftPattern = newShiftPattern
    }

    // Update the partial day feature toggle to trigger conversions
    func updatePartialDayFeature(enabled: Bool) {
        // If the feature is being enabled
        if enabled && !enablePartialDayFeature {
            // Convert from shift pattern to partial day pattern
            convertShiftToPartialDayPattern()
        }
        // If the feature is being disabled
        else if !enabled && enablePartialDayFeature {
            // Convert from partial day pattern to shift pattern
            convertPartialDayToShiftPattern()
        }
        
        // Update the setting
        enablePartialDayFeature = enabled
        
        // Save changes
        saveToUserDefaults()
    }

    // Add this method to the WorkdayPatternManager class
    func updatePartialDayPattern(_ newPattern: [[Int]]) {
        // Update the partial day pattern
        partialDayPattern = newPattern
        
        // Also update the shift pattern to keep them in sync
        // A day is a work day if it has any shifts
        var newShiftPattern = [Bool]()
        for dayShifts in newPattern {
            newShiftPattern.append(!dayShifts.isEmpty)
        }
        
        // Only update if the length matches to avoid corrupting existing pattern
        if newShiftPattern.count == shiftPattern.count {
            shiftPattern = newShiftPattern
        }
        
        // Save changes to UserDefaults
        saveToUserDefaults()


    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systemColorScheme // Add system color scheme environment
    @Query private var workDays: [WorkDay]
    
    @State private var selectedDate: Date = Date()
    @State private var showingNoteEditor = false
    @State private var noteText = ""
    @State private var showingSettings = false
    @AppStorage(languagePreferenceKey) private var languagePreference = 0 // Default: system
    @AppStorage(customWorkTermKey) private var customWorkTerm = "上班" // Default work term
    @AppStorage(appearancePreferenceKey) private var appearancePreference = 0 // Default: system
    @AppStorage(startOfWeekPreferenceKey) private var startOfWeekPreference = 0 // Default: Sunday (0)
    @AppStorage(showStatusOpacityDifferenceKey) private var showStatusOpacityDifference = false // Default: false
    @FocusState private var isCustomTermFieldFocused: Bool // Add focus state
    
    // Holiday-related state
    @AppStorage(holidayPreferenceKey) private var holidayPreference = 0 // Default: none
    @State private var isRefreshingHolidays = false
    @State private var lastRefreshStatus: Bool? = nil
    
    // Add explicit app group UserDefaults access for direct writes
    private let sharedDefaults = UserDefaults(suiteName: appGroupID)
    
    // Keep the pattern manager as our single source of truth
    @StateObject private var patternManager = WorkdayPatternManager.shared
    
    // Add this to ContentView properties section
    @AppStorage(useDarkIconPreferenceKey) private var useDarkIconPreference = false // Default: off
    
    // 1. Add a local state to hold the holiday note (used only while note editor is open).
    @State private var holidayNote: String? = nil
    
    // Add these properties to ContentView struct alongside other @State variables
    @State private var showingShiftDatePicker = false
    @State private var editingShiftLength = false
    @FocusState private var isShiftLengthFieldFocused: Bool // Add dedicated focus state
    
    // Add this to your ContentView properties
    @State private var confirmClearCustomDays = false
    
    // Add this state variable to ContentView struct with other @State properties
    @State private var isEraserModeActive = false
    
    /// UNIFIED FUNCTION: Determine if a date is a work day using the three-tier priority system
    /// 1. First check explicit user-set entry (highest priority)
    /// 2. Then check holiday data (medium priority)
    /// 3. Finally fall back to default weekday rules (lowest priority)
    /// - Parameter date: The date to check
    /// - Returns: true if it's a work day, false if it's an off day
    func isWorkDay(forDate date: Date) -> Bool {
        // First check if we have an explicit user record (highest priority)
        if let existingWorkDay = workDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            // Only use the stored status if user explicitly set it
            if existingWorkDay.dayStatus > 0 {
                return existingWorkDay.dayStatus > 1
            }
            // Otherwise, fall through to use default pattern (for days with notes but default status)
        }
        
        // Next check holiday data (medium priority)
        if let holidayInfo = HolidayManager.shared.getHolidayInfo(for: date) {
            return holidayInfo.isWorkDay
        }
        
        // Fall back to default rules (lowest priority)
        return isDefaultWorkDay(date, patternManager: patternManager)
    }
    
    var todayWorkDay: WorkDay? {
        let calendar = Calendar.current
        return workDays.first { calendar.isDate($0.date, inSameDayAs: Date()) }
    }
    
    // Use unified isWorkDay function for today
    var isTodayWorkDay: Bool {
        return isWorkDay(forDate: Date())
    }
    
    var selectedWorkDay: WorkDay? {
        let calendar = Calendar.current
        return workDays.first { calendar.isDate($0.date, inSameDayAs: selectedDate) }
    }
    
    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.locale = currentLocale()
        return formatter
    }
    
    // Helper to get localized text based on current language preference
    func localizedText(_ englishText: String, chineseText: String) -> String {
        let language = AppLanguage(rawValue: languagePreference) ?? .systemDefault
        
        switch language {
        case .english:
            return englishText
        case .chinese:
            return chineseText
        case .systemDefault:
            // Try to detect system language
            let preferredLanguage = Locale.current.language.languageCode?.identifier ?? "en"
            return preferredLanguage.hasPrefix("zh") ? chineseText : englishText
        }
    }
    
    // Replace occurrences of "上班" with the custom term in Chinese texts
    func customizeWorkTerm(_ text: String) -> String {
        if customWorkTerm == "上班" {
            return text
        }
        return text.replacingOccurrences(of: "上班", with: customWorkTerm)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Today's Status Card
                todayStatusCard
                
                // Custom Calendar with callbacks
                CustomCalendarView(
                    selectedDate: $selectedDate,
                    workDays: workDays,
                    languagePreference: languagePreference,
                    startOfWeekPreference: startOfWeekPreference,
                    showStatusOpacityDifference: showStatusOpacityDifference || isEraserModeActive, // Force show in eraser mode
                    patternManager: patternManager,
                    isEraserModeActive: isEraserModeActive,
                    isWorkDayFunction: { date in
                        // Remove [weak self] - not needed for structs
                        isWorkDay(forDate: date)
                    },
                    getPartialDayShiftsFunction: { date in
                        getPartialDayShifts(forDate: date)
                    },
                    onToggleWorkStatus: { date in
                        // Revert to the original implementation
                        if isEraserModeActive {
                            resetDayStatus(date)
                        } else {
                            toggleWorkDay(date)
                        }
                    },
                    onOpenNoteEditor: { date in
                        // Revert to the original implementation
                        selectedDate = date
                        
                        // Get existing note if any
                        if let existingDay = workDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                            noteText = existingDay.note ?? ""
                        } else {
                            noteText = ""
                        }
                        
                        showingNoteEditor = true
                    },
                    onCycleShifts: { date in
                    if isEraserModeActive {
                            resetDayStatus(date)
                        } else {
                            updateDayShifts2Ver(date: date)
                        }
                        
                    },
                    onToggleShift: { date, shiftNumber in
                        // Get current shifts for this date
                        var currentShifts = getPartialDayShifts(forDate: date)
                        
                        // Toggle the shift
                        if currentShifts.contains(shiftNumber) {
                            currentShifts.removeAll { $0 == shiftNumber }
                        } else {
                            currentShifts.append(shiftNumber)
                            currentShifts.sort()
                        }
                        
                        // Update the WorkDay with new shifts
                        updateDayShifts(date, shifts: currentShifts)
                    }
                )
                
                // Instructions for interactions
                HStack(alignment: .top) {
                    if isEraserModeActive {
                        // Single line text for eraser mode
                        Label(localizedText("Tap a day to reset to default workday", 
                                          chineseText: "点击日期以移除工作日更改"), 
                                  systemImage: "hand.tap")
                                .font(.caption)
                                .foregroundColor(.secondary)

                    } else {
                        // Original VStack with separate labels for tap and long-press
                        VStack(alignment: .leading, spacing: 4) {
                            Label(localizedText("Tap a day to toggle work/rest status", 
                                               chineseText: "点击日期切换工作/休息状态"), 
                                  systemImage: "hand.tap")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Label(localizedText("Long-press to add or edit notes", 
                                               chineseText: "长按添加或编辑备注"), 
                                  systemImage: "hand.tap.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Eraser button remains the same
                    Button(action: {
                        withAnimation {
                            isEraserModeActive.toggle()
                        }
                    }) {
                        Image(systemName: "eraser\(isEraserModeActive ? ".fill" : "")")
                            .foregroundColor(isEraserModeActive ? .blue : .secondary)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(isEraserModeActive ? Color.blue.opacity(0.2) : Color.clear)
                            )
                    }
                    .accessibilityLabel(isEraserModeActive 
                        ? localizedText("Exit eraser mode", chineseText: "退出橡皮擦模式") 
                        : localizedText("Enter eraser mode", chineseText: "进入橡皮擦模式"))
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .toolbar(.hidden, for: .navigationBar) // Hide default navigation bar
            .safeAreaInset(edge: .top) {
                HStack {
                    Text(localizedText("WorkdayQ", chineseText: "今天上班吗？"))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gear")
                            .font(.title2)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(Color(UIColor.systemBackground))
            }
            .sheet(isPresented: $showingNoteEditor) {
                noteEditorView
                    // 2. Load the holiday note when this sheet appears.
                    .onAppear {
                        holidayNote = HolidayManager.shared.getSystemNote(for: selectedDate)
                    }
            }
            .sheet(isPresented: $showingSettings, onDismiss: {
                // Force UI refresh when settings are closed
                // This will ensure any week pattern changes are reflected in the calendar
                
                // Force update of selectedDate to trigger UI refresh
                let currentDate = selectedDate
                selectedDate = Date.distantPast
                DispatchQueue.main.async {
                    selectedDate = currentDate
                }
                
                // Also reload widgets to ensure they're up to date
                reloadWidgets()
            }) {
                settingsView
                    .preferredColorScheme(AppAppearance(rawValue: appearancePreference)?.colorScheme ?? systemColorScheme)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                // Always update selectedDate to today when view appears
                selectedDate = Date()
                
                checkAndCreateTodayEntry()
                
                // Also make sure patternManager is synced with latest UserDefaults
                patternManager.reloadFromUserDefaults()
                
                // Always reload widget when view appears
                reloadWidgets()
                
                // Make sure other preferences are synced
                syncLanguagePreference()
                syncAppearancePreference()
                
                // Still update app icon initially
                updateAppIcon()
            }
            .onChange(of: languagePreference) { oldValue, newValue in
                // When language changes, sync it immediately and reload widgets
                print("Language preference changed from \(oldValue) to \(newValue)")
                syncLanguagePreference()
                reloadWidgets() // Force widgets to refresh
            }
            .onChange(of: appearancePreference) { oldValue, newValue in
                // When appearance changes, sync it immediately and reload widgets
                print("Appearance preference changed from \(oldValue) to \(newValue)")
                syncAppearancePreference()
                reloadWidgets() // Force widgets to refresh
            }
            .onChange(of: workDays) { _, _ in
                // Reload widgets when workdays change 
                reloadWidgets()
            }
            // Add scene phase monitoring to refresh date when app becomes active
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    // App has become active again
                    isEraserModeActive = false // Reset eraser mode when app becomes active
                    
                    print("ContentView: App became active - refreshing data")
                    // Reset selected date to today in case date changed while app was inactive
                    let calendar = Calendar.current
                    if !calendar.isDateInToday(selectedDate) {
                        print("Date changed since last active - updating to today")
                        selectedDate = Date()
                    }
                    
                    // Refresh our data
                    checkAndCreateTodayEntry()
                    reloadWidgets()
                    
                    // Make sure patternManager has latest data
                    patternManager.reloadFromUserDefaults()
                } else if newPhase == .background {
                    // App has moved to background
                    isEraserModeActive = false // Also reset when app goes to background
                    
                    // Rest of your existing code...
                }
            }
            // Apply the preferred color scheme
            .preferredColorScheme(AppAppearance(rawValue: appearancePreference)?.colorScheme)
        }
    }
    
    var todayStatusCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateFormatter.string(from: Date()))
                .font(.headline)
                .padding(.bottom, 4)
                .padding(.top, 4)
            
            Spacer()
            
            // Use localizedText consistently, not direct language checks
            Text(localizedText("Today is a", chineseText: "今天"))
                .font(languagePreference == AppLanguage.chinese.rawValue ? .title3 : .subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, -6)
                .fontWeight(.semibold)
            
            HStack {
                let isWorkDay = isWorkDay(forDate: Date()) // Use unified function
                
                // Use localizedText consistently for all text
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(isWorkDay ? 
                         customizeWorkTerm(localizedText("Workday", chineseText: "要上班")) : 
                         localizedText("Day Off", chineseText: "不上班"))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(isWorkDay ? .red : .green)
                    
                    // Store today's holiday note in a property to ensure consistency
                    if let holidayNote = HolidayManager.shared.getSystemNote(for: Date()) {
                        Text(holidayNote)
                            .font(.title3)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                if patternManager.enablePartialDayFeature {
                    // Use the original ShiftCircle from CustomCalendarView instead of AppCardShiftCircle
                    ShiftCircle(
                        shifts: getPartialDayShifts(forDate: Date()),  // Use this method instead
                        numberOfShifts: patternManager.numberOfShifts,
                        size: 50,
                        baseOpacity: 0.8,
                        dividerColor: AppAppearance(rawValue: appearancePreference)?.colorScheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.5) : Color.white.opacity(0.5)
                    )
                } else {
                    Circle()
                        .fill(isWorkDay ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                        .frame(width: 50, height: 50)
                        .padding(.bottom, 1)
                }
            }
            
            if let note = todayWorkDay?.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.top, -5)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(height: 155)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20) // iOS widget corner radius
                .fill(
                    // Determine background color based on appearance mode
                    {
                        let appearance = AppAppearance(rawValue: appearancePreference)
                        
                        // If explicitly set to light mode
                        if appearance?.colorScheme == .light {
                            return Color.white
                        }
                        // If explicitly set to dark mode
                        else if appearance?.colorScheme == .dark {
                            return Color(red: 0.11, green: 0.11, blue: 0.12)
                        }
                        // If following system (appearance?.colorScheme is nil)
                        else {
                            return systemColorScheme == .light ? 
                                Color.white : 
                                Color(red: 0.11, green: 0.11, blue: 0.12)
                        }
                    }()
                )
                .shadow(color: Color(UIColor { traitCollection in
                    traitCollection.userInterfaceStyle == .dark ? .black : .black
                }).opacity(0.2), radius: 5, x: 0, y: 2)
        )
    }
    
    var noteEditorView: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                // Add date display at the top
                Text(dateFormatter.string(from: selectedDate))
                    .font(.headline)
                    .padding(.bottom, 8)
                
                // User note input with 15 character limit
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizedText("Your Note:", chineseText: "您的备注:"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField(localizedText("Enter note", chineseText: "输入备注"), 
                              text: $noteText)
                        .padding()
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: noteText) { _, newValue in
                            // Only truncate if text exceeds limit, don't modify during deletion
                            if newValue.count > 15 {
                                noteText = String(newValue.prefix(15))
                            }
                        }
                    
                    Text("\(noteText.count)/15")
                        .font(.caption)
                        .foregroundColor(noteText.count >= 15 ? .red : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                }
                
                // 3. Use the cached holidayNote here instead of calling 
                // HolidayManager.shared.getSystemNote(for: selectedDate) again.
                if let systemNote = holidayNote {
                    Divider()
                        .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedText("Holiday Information:", chineseText: "节假日信息:"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(systemNote)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle(localizedText("Date Note", chineseText: "日期备注"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localizedText("Cancel", chineseText: "取消")) {
                        showingNoteEditor = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localizedText("Save", chineseText: "保存")) {
                        saveNote()
                        showingNoteEditor = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private func checkAndCreateTodayEntry() {
        // This method has been simplified to not create an entry for today
        // unless it's explicitly set by the user. This allows the app to
        // use default rules or holiday data for today's display.
        //
        // Creating an entry for today automatically causes it to appear as
        // user-edited in the UI, which isn't the intended behavior.
        
        // We don't need to create any entry for today by default
        // The app will use:
        // 1. Existing entry if the user has set one
        // 2. Holiday data if available
        // 3. Default rules (weekday = work, weekend = off) as fallback
    }
    
    private func toggleWorkDay(_ date: Date) {
        // Check if this date already exists in our store
        if let existingWorkDay = workDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            // Handle differently based on current status
            if existingWorkDay.dayStatus == 0 {
                // If currently unmodified, set to opposite of what would be determined
                // by the full priority system (holiday and pattern)
                let naturalStatus = isWorkDay(forDate: date)
                existingWorkDay.dayStatus = naturalStatus ? 1 : 2
            } else {
                // If already explicitly set (1 or 2), just toggle between those states
                existingWorkDay.dayStatus = existingWorkDay.dayStatus == 2 ? 1 : 2
            }
        } else {
            // If not, create a new entry with the opposite of natural status
            // (considering holiday data and patterns)
            let naturalStatus = isWorkDay(forDate: date)
            
            // New workday with status opposite of natural (explicit user choice)
            let newWorkDay = WorkDay(
                date: date,
                dayStatus: naturalStatus ? 1 : 2, // The opposite of the natural status
                note: nil
            )
            modelContext.insert(newWorkDay)
        }
        
        // Try to save changes immediately
        do {
            try modelContext.save()
            
            // Update widget data
            if let sharedDefaults = UserDefaults(suiteName: appGroupID) {
                sharedDefaults.set(Date().timeIntervalSince1970, forKey: lastUpdateKey)
                sharedDefaults.synchronize()
            }
            
            // Force widgets to refresh
            reloadWidgets()
        } catch {
            print("Error saving day status: \(error.localizedDescription)")
        }
    }
    
    private func saveNote() {
        // Check if we already have an entry for this date
        if let existingWorkDay = workDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
            // Just update the note, preserve the status
            existingWorkDay.note = noteText.isEmpty ? nil : noteText
        } else {
            // Create new entry with default status
            let newWorkDay = WorkDay(
                date: selectedDate,
                dayStatus: 0, // Unmodified - follow pattern
                note: noteText.isEmpty ? nil : noteText
            )
            modelContext.insert(newWorkDay)
        }
        
        // Try to save changes
        do {
            try modelContext.save()
            
            // Update the timestamp for widget sync
            if let sharedDefaults = UserDefaults(suiteName: appGroupID) {
                sharedDefaults.set(Date().timeIntervalSince1970, forKey: lastUpdateKey)
                sharedDefaults.synchronize()
            }
            
            // Hide the note editor and reset state
            showingNoteEditor = false
            noteText = ""
            
            // Force widgets to refresh
            reloadWidgets()
        } catch {
            print("Failed to save note: \(error.localizedDescription)")
        }
    }
    
    // Force reload of all widgets
    private func reloadWidgets() {
        if let sharedDefaults = UserDefaults(suiteName: appGroupID) {
            let timestamp = Date().timeIntervalSince1970
            sharedDefaults.set(timestamp, forKey: lastUpdateKey)
            
            // Sync other preferences
            sharedDefaults.set(languagePreference, forKey: languagePreferenceKey)
            sharedDefaults.set(customWorkTerm, forKey: customWorkTermKey)
            sharedDefaults.set(appearancePreference, forKey: appearancePreferenceKey)
            sharedDefaults.set(startOfWeekPreference, forKey: startOfWeekPreferenceKey)
            sharedDefaults.set(showStatusOpacityDifference, forKey: showStatusOpacityDifferenceKey)
            
            // Get pattern data from patternManager (instead of local properties)
            let patternString = patternManager.pattern.map { $0 ? "1" : "0" }.joined()
            sharedDefaults.set(patternString, forKey: weekPatternKey)
            sharedDefaults.set(patternManager.workdayMode, forKey: defaultWorkdaySettingKey)
            
            // Get shift pattern data from patternManager (instead of local properties)
            let shiftPatternString = patternManager.shiftPattern.map { $0 ? "1" : "0" }.joined()
            sharedDefaults.set(shiftPatternString, forKey: shiftPatternKey)
            
            // Get shift start date from patternManager (instead of local properties)
            sharedDefaults.set(patternManager.shiftStartDate.timeIntervalSince1970, forKey: shiftStartDateKey)
            
            // Get number of shifts from patternManager (instead of local properties)
            sharedDefaults.set(patternManager.numberOfShifts, forKey: numberOfShiftsKey)
            
            // Get partial day feature setting
            sharedDefaults.set(patternManager.enablePartialDayFeature, forKey: enablePartialDayFeatureKey)
            
            // Get partial day pattern
            if let encodedPattern = try? JSONEncoder().encode(patternManager.partialDayPattern) {
                sharedDefaults.set(encodedPattern, forKey: partialDayPatternKey)
            }
            
            sharedDefaults.synchronize()
            
            // Cache the work days data for widget fallback access
            cacheWorkDaysToUserDefaults(workDays)
        }
        
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    // Cache work days to UserDefaults for widget fallback access
    private func cacheWorkDaysToUserDefaults(_ workDays: [WorkDay]) {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID) else {
            print("Failed to access shared UserDefaults")
            return
        }
        
        // Convert WorkDay models to dictionaries
        let workDayDicts = workDays.map { workDay -> [String: Any] in
            var dict: [String: Any] = [
                "date": workDay.date,
                "dayStatus": workDay.dayStatus
            ]
            
            if let note = workDay.note {
                dict["note"] = note
            }
            
            return dict
        }
        
        do {
            // Serialize and save the data
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: workDayDicts,
                requiringSecureCoding: false
            )
            
            sharedDefaults.set(data, forKey: "cachedWorkDays")
            print("Cached \(workDays.count) work days to UserDefaults for widget access")
        } catch {
            print("Error caching work days to UserDefaults: \(error)")
        }
    }
    
    // Notify widgets of data changes via UserDefaults
    private func notifyWidgetDataChanged() {
        // Update timestamp in shared UserDefaults to signal widget
        let sharedDefaults = UserDefaults(suiteName: appGroupID)
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: lastUpdateKey)
        sharedDefaults?.synchronize()
        
        // Also trigger immediate reload
        reloadWidgets()
    }
    
    // Settings view that appears from bottom
    var settingsView: some View {
        NavigationStack {
            List {

                // holidays Sync Settings
                Section(header: Text(localizedText("Holidays", chineseText: "节假日和调休"))) {
                    Picker(localizedText("Setting Holiday", chineseText: "设置节假日和调休"), selection: $holidayPreference) {
                        ForEach(HolidayPreference.allCases) { preference in
                            Text(localizedText(preference.localizedName.english, chineseText: preference.localizedName.chinese)).tag(preference.rawValue)
                        }
                    }
                    .onChange(of: holidayPreference) { oldValue, newValue in
                        if oldValue != newValue {
                            // Update the holiday preference in HolidayManager
                            HolidayManager.shared.setHolidayPreference(HolidayPreference(rawValue: newValue) ?? .none)
                            
                            // Force widgets to reload
                            reloadWidgets()
                        }
                    }
                    
                    Button(action: {
                        // Show loading indicator
                        isRefreshingHolidays = true
                        lastRefreshStatus = nil
                        
                        // Refresh holidays
                        HolidayManager.shared.fetchHolidays { success in
                            isRefreshingHolidays = false
                            lastRefreshStatus = success
                            
                            // Force widgets to reload with new holiday data
                            reloadWidgets()
                        }
                    }) {
                        HStack {
                            Text(localizedText("Refresh Holiday Data", chineseText: "刷新节假日数据"))
                            
                            Spacer()
                            
                            if isRefreshingHolidays {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else if let status = lastRefreshStatus {
                                Image(systemName: status ? "checkmark.circle" : "xmark.circle")
                                    .foregroundColor(status ? .green : .red)
                            }
                        }
                    }
                    .disabled(holidayPreference == HolidayPreference.none.rawValue || isRefreshingHolidays)
                    
                    if let lastFetchTime = UserDefaults.standard.object(forKey: lastHolidayFetchKey) as? TimeInterval {
                        HStack {
                            Text(localizedText("Last Updated", chineseText: "上次更新"))
                            Spacer()
                            Text(Date(timeIntervalSince1970: lastFetchTime).formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Add this to your settingsView after the Default Workday Pattern section
                Section(header: Text(localizedText("Default Workday Pattern", chineseText: "默认工作日模式"))) {
                    Picker(localizedText("Workday Pattern Mode", chineseText: "工作日模式"), selection: Binding(
                        get: { patternManager.workdayMode },
                        set: { newMode in
                            // If switching to shift mode, reset to defaults
                            if newMode == 2 && patternManager.workdayMode != 2 {
                                // Reset shift pattern to default 4-on, 3-off
                                patternManager.updateShiftPattern([true, true, true, true, false, false, false])
                                // Reset shift start date to today
                                patternManager.updateShiftStartDate(Calendar.current.startOfDay(for: Date()))
                            }
                            patternManager.updateMode(newMode)
                        }
                    )) {
                        Text(localizedText("Default", chineseText: "默认")).tag(0)
                        Text(localizedText("User Defined Week", chineseText: "自定义周")).tag(1)
                        Text(localizedText("Shift Work", chineseText: "轮班")).tag(2)
                    }
                    .pickerStyle(.segmented)
                    
                    // Show week pattern editor only if User Defined Week is selected
                    if patternManager.workdayMode == 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            WeekPatternEditorView(
                                weekPattern: Binding(
                                    get: { patternManager.pattern },
                                    set: { patternManager.updatePattern($0) }
                                ),
                                startOfWeek: startOfWeekPreference,
                                languagePreference: languagePreference
                            )
                        }
                        .padding(.top, 8)
                    }
                    
                    // Show shift pattern editor only if Shift Work is selected
                    if patternManager.workdayMode == 2 {
                        // No state variables here, just use the ones from the struct

                            // First row: Shift start date button and pattern length picker
                            DatePicker(
                                    localizedText("Shift start date", chineseText: "轮班开始日期"),
                                    selection: Binding(
                                        get: { patternManager.shiftStartDate },
                                        set: { newDate in
                                            patternManager.updateShiftStartDate(newDate)
                                            // Auto-close the picker after selection
                                            showingShiftDatePicker = false
                                        }
                                    ),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)

                            HStack(spacing: 4) {
                                    // Use Picker instead of nested HStack + Menu
                                    Picker(localizedText("Length:", chineseText: "周期:"), selection: Binding(
                                        get: { patternManager.shiftPattern.count },
                                        set: { newLength in
                                            var newShiftPattern = patternManager.shiftPattern
                                            var newPartialDayPattern = patternManager.partialDayPattern
                                            
                                            // Update shift pattern length
                                            if newLength > newShiftPattern.count {
                                                // Add new days as rest days (false)
                                                newShiftPattern.append(contentsOf: Array(repeating: false, count: newLength - newShiftPattern.count))
                                            } else if newLength < newShiftPattern.count {
                                                // Remove days from the end
                                                newShiftPattern = Array(newShiftPattern.prefix(newLength))
                                            }
                                            
                                            // Update partial day pattern length to match
                                            if newLength > newPartialDayPattern.count {
                                                // Add new days as rest days (empty arrays)
                                                newPartialDayPattern.append(contentsOf: Array(repeating: [], count: newLength - newPartialDayPattern.count))
                                            } else if newLength < newPartialDayPattern.count {
                                                // Remove days from the end
                                                newPartialDayPattern = Array(newPartialDayPattern.prefix(newLength))
                                            }
                                            
                                            // Update both patterns
                                            patternManager.updateShiftPattern(newShiftPattern)
                                            patternManager.updatePartialDayPattern(newPartialDayPattern)
                                        }
                                    )) {
                                        ForEach(1...9, id: \.self) { length in
                                            Text("\(length)").tag(length)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                            
                            // Date picker (shown/hidden based on state)

                            
                            // Shift pattern editor
                            if patternManager.enablePartialDayFeature {
                                PartialDayPatternEditorView(
                                    partialDayPattern: Binding(
                                        get: { patternManager.partialDayPattern },
                                        set: { patternManager.updatePartialDayPattern($0) }
                                    ),
                                    numberOfShifts: patternManager.numberOfShifts
                                )
                                .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                ShiftPatternEditorView(
                                    shiftPattern: Binding(
                                        get: { patternManager.shiftPattern },
                                        set: { patternManager.updateShiftPattern($0) }
                                    ),
                                    languagePreference: languagePreference,
                                    workText: localizedText("Work", chineseText: "工作"),
                                    offText: localizedText("Off", chineseText: "休息")
                                )
                                .frame(maxWidth: .infinity, alignment: .center)
                            }
                                

                            // After the ShiftPatternEditorView, add:
                            Toggle(isOn: Binding(
                                get: { patternManager.enablePartialDayFeature },
                                set: { patternManager.updatePartialDayFeature(enabled: $0) }
                            )) {
                                Text(localizedText("Enable Partial Day Shifts", chineseText: "启用分段工作日"))
                            }

                            // Only show the shift count picker when partial day is enabled and in shift mode
                            if patternManager.enablePartialDayFeature && patternManager.workdayMode == 2 {
                                Picker(selection: $patternManager.numberOfShifts) {
                                    Text("2 \(localizedText("Shifts", chineseText: "班次"))").tag(2)
                                    Text("3 \(localizedText("Shifts", chineseText: "班次"))").tag(3)
                                    Text("4 \(localizedText("Shifts", chineseText: "班次"))").tag(4)
                                } label: {
                                    Text(localizedText("Number of Shifts", chineseText: "每日班次数量"))
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: patternManager.numberOfShifts) { _, _ in
                                    patternManager.saveToUserDefaults()
                                }
                            }
                    }
                }



                // Customization Settings
                Section(header: Text(localizedText("Customization", chineseText: "自定义"))) {
                    
                    // Start of Week
                    Picker(localizedText("Start of Week", chineseText: "每周开始日"), selection: $startOfWeekPreference) {
                        Text(localizedText("Sunday", chineseText: "周日")).tag(0)
                        Text(localizedText("Monday", chineseText: "周一")).tag(1)
                    }
                    .onChange(of: startOfWeekPreference) { oldValue, newValue in
                        // Sync the start of week preference to UserDefaults for widget access
                        syncStartOfWeekPreference()
                        // Force widgets to reload with new start of week
                        reloadWidgets()
                    }


                    // Only show the work term customization if language is set to Chinese
                    if languagePreference == AppLanguage.chinese.rawValue {
                        ZStack {
                            Color.clear
                                .contentShape(Rectangle()) // Make the entire area tappable
                                .onTapGesture {
                                    // Dismiss keyboard when tapping outside the TextField
                                    isCustomTermFieldFocused = false
                                    hideKeyboard() // Add direct keyboard dismissal
                                }
                            
                            VStack(alignment: .leading) {
                                Text(localizedText("Customize work term", chineseText: "自定义工作用语"))
                                    .font(.subheadline)
                                
                                TextField("上班", text: $customWorkTerm)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .focused($isCustomTermFieldFocused) // Keep focused modifier
                                    .onTapGesture {
                                        // This is redundant with the focused modifier but ensures focus
                                        isCustomTermFieldFocused = true
                                    }
                                    .submitLabel(.done) // Set the keyboard return key to "Done"
                                    .toolbar {
                                        ToolbarItemGroup(placement: .keyboard) {
                                            Spacer() // Push button to the right
                                            Button(localizedText("Done", chineseText: "完成")) {
                                                isCustomTermFieldFocused = false
                                                hideKeyboard() // Add direct keyboard dismissal
                                            }
                                        }
                                    }
                                    
                                    .onSubmit {
                                        // Hide keyboard when user presses "Done" on keyboard
                                        isCustomTermFieldFocused = false
                                        hideKeyboard() // Add direct keyboard dismissal
                                    }
                                    .onChange(of: customWorkTerm) { oldValue, newValue in
                                        // If user clears the field, set back to default
                                        if newValue.isEmpty {
                                            customWorkTerm = "上班"
                                        } 
                                        // Limit to 2 Chinese characters maximum
                                        else if newValue.count > 2 {
                                            customWorkTerm = String(newValue.prefix(2))
                                        }
                                        
                                        // Sync to UserDefaults for widget access
                                        syncCustomWorkTerm()
                                        // Reload widgets to show new term
                                        reloadWidgets()
                                    }
                                
                                Text(localizedText("Examples: School day", chineseText: "例如：上课、上学、值班"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if customWorkTerm != "上班" {
                                    Button(localizedText("Reset to Default", chineseText: "重置为默认")) {
                                        customWorkTerm = "上班"
                                        syncCustomWorkTerm()
                                        reloadWidgets()
                                    }
                                    .foregroundColor(.blue)
                                    .padding(.top, 2)
                                }
                            }
                        }
                    }
                    
                    // Add new toggle for opacity differentiation
                    VStack(alignment: .leading) {
                        Toggle(
                        localizedText("Highlight user-edited days", chineseText: "高亮自定义日期"),
                        isOn: $showStatusOpacityDifference
                    )
                    .onChange(of: showStatusOpacityDifference) { oldValue, newValue in
                        // When toggled, sync to shared defaults and reload widgets
                        syncOpacityDifferencePreference()
                        reloadWidgets()
                    }
                    
                    Text(localizedText("When on, days edited by you will appear more vibrant", 
                         chineseText: "开启时，自定义日期将会更明显。"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                }

                
                

                // Appearance Settings

                Section(header: Text(localizedText("Appearance", chineseText: "外观"))) {
                    Picker(localizedText("Appearance Mode", chineseText: "外观模式"), selection: $appearancePreference) {
                        Text(localizedText("System", chineseText: "跟随系统")).tag(AppAppearance.systemDefault.rawValue)
                        Text(localizedText("Light", chineseText: "浅色模式")).tag(AppAppearance.light.rawValue)
                        Text(localizedText("Dark", chineseText: "深色模式")).tag(AppAppearance.dark.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: appearancePreference) { oldValue, newValue in
                        // Sync the appearance preference to UserDefaults for widget access
                        syncAppearancePreference()
                        // Force widgets to reload with new appearance
                        reloadWidgets()
                    }
                    
                    // Add the dark icon toggle here
                    Toggle(
                        localizedText("Use dark app icon", chineseText: "使用深色应用图标"),
                        isOn: $useDarkIconPreference
                    )
                    .onChange(of: useDarkIconPreference) { oldValue, newValue in
                        // Update app icon when preference changes
                        updateAppIcon()
                        
                        // Sync to shared UserDefaults
                        if let sharedDefaults = UserDefaults(suiteName: appGroupID) {
                            sharedDefaults.set(newValue, forKey: useDarkIconPreferenceKey)
                            sharedDefaults.synchronize()
                        }
                    }
                    
                    
                }

                // Language Settings
                Section(header: Text(localizedText("Language", chineseText: "语言"))) {
                    Picker(localizedText("App Language", chineseText: "应用语言"), selection: $languagePreference) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language.rawValue)
                        }
                    }
                    .onChange(of: languagePreference) { oldValue, newValue in
                        if oldValue != newValue {
                            // Show alert about needing to restart
                            // In a real implementation, we might actually restart the app
                            // or apply the language change immediately
                            print("Language changed to: \(AppLanguage(rawValue: newValue)?.displayName ?? "Unknown")")
                            // Ensure we sync this change to the shared UserDefaults
                            syncLanguagePreference()
                            // Force widgets to reload
                            reloadWidgets()
                        }
                    }
                    
                    if languagePreference != AppLanguage.systemDefault.rawValue {
                        Button(localizedText("Reset to System Default", chineseText: "重置为系统默认设置")) {
                            languagePreference = AppLanguage.systemDefault.rawValue
                        }
                        .foregroundColor(.blue)
                    }
                }
                
                
                
                Section(header: Text(localizedText("Data", chineseText: "数据"))) {
                    Button(action: {
                        // Placeholder for backup functionality
                    }) {
                        Label(localizedText("Backup Data", chineseText: "备份数据"), systemImage: "arrow.down.doc")
                    }
                    
                    Button(action: {
                        // Placeholder for restore functionality
                    }) {
                        Label(localizedText("Restore Data", chineseText: "恢复数据"), systemImage: "arrow.up.doc")
                    }
                    
                    Button(action: {
                        // Show confirmation alert before clearing data
                        confirmClearCustomDays = true
                    }) {
                        Label(localizedText("Clear All Custom Days", chineseText: "清除所有自定义日期"), 
                              systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    .alert(localizedText("Clear All Custom Days?", chineseText: "清除所有自定义日期？"), 
                           isPresented: $confirmClearCustomDays) {
                        Button(localizedText("Cancel", chineseText: "取消"), role: .cancel) {}
                        Button(localizedText("Clear", chineseText: "清除"), role: .destructive) {
                            clearAllCustomDays()
                        }
                    } message: {
                        Text(localizedText(
                            "This will remove all your custom day settings. Default patterns will still apply.", 
                            chineseText: "这将删除您所有的自定义日期设置。默认模式仍将适用。"))
                    }
                }
                
                Section(header: Text(localizedText("About", chineseText: "关于"))) {
                    HStack {
                        Text(localizedText("Version", chineseText: "版本"))
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }

                }
                
                
            }
            .navigationTitle(localizedText("Settings", chineseText: "设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localizedText("Done", chineseText: "完成")) {
                        showingSettings = false
                    }
                }
            }
        }
    }
    
    // Function to get current locale based on language preference
    func currentLocale() -> Locale {
        let language = AppLanguage(rawValue: languagePreference) ?? .systemDefault
        if let localeID = language.localeIdentifier {
            return Locale(identifier: localeID)
        } else {
            return Locale.current
        }
    }
    
    // New function to explicitly synchronize language preference to shared UserDefaults
    private func syncLanguagePreference() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID) else {
            print("Failed to access shared UserDefaults")
            return
        }
        
        // Set the language preference in shared UserDefaults
        sharedDefaults.set(languagePreference, forKey: languagePreferenceKey)
        sharedDefaults.synchronize() // Force immediate write
        
        print("Synced language preference to UserDefaults: \(languagePreference)")
    }
    
    // New function to sync custom work term to shared UserDefaults
    private func syncCustomWorkTerm() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID) else {
            print("Failed to access shared UserDefaults")
            return
        }
        
        // Set the custom work term in shared UserDefaults
        sharedDefaults.set(customWorkTerm, forKey: customWorkTermKey)
        sharedDefaults.synchronize() // Force immediate write
        
        print("Synced custom work term to UserDefaults: \(customWorkTerm)")
    }

    // Add function to sync appearance preference to shared UserDefaults
    private func syncAppearancePreference() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID) else {
            print("Failed to access shared UserDefaults")
            return
        }
        
        // Set the appearance preference in shared UserDefaults
        sharedDefaults.set(appearancePreference, forKey: appearancePreferenceKey)
        sharedDefaults.synchronize() // Force immediate write
        
        print("Synced appearance preference to UserDefaults: \(appearancePreference)")
    }

    // Add function to sync start of week preference to shared UserDefaults
    private func syncStartOfWeekPreference() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID) else {
            print("Failed to access shared UserDefaults")
            return
        }
        
        // Set the start of week preference in shared UserDefaults
        sharedDefaults.set(startOfWeekPreference, forKey: startOfWeekPreferenceKey)
        sharedDefaults.synchronize() // Force immediate write
        
        print("Synced start of week preference to UserDefaults: \(startOfWeekPreference)")
    }

    // Add function to sync opacity difference preference to shared UserDefaults
    private func syncOpacityDifferencePreference() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID) else {
            print("Failed to access shared UserDefaults")
            return
        }
        
        // Set the opacity difference preference in shared UserDefaults
        sharedDefaults.set(showStatusOpacityDifference, forKey: showStatusOpacityDifferenceKey)
        sharedDefaults.synchronize() // Force immediate write
        
        print("Synced opacity difference preference to UserDefaults: \(showStatusOpacityDifference)")
    }

    // Modify the updateAppIcon function
    private func updateAppIcon() {
        // Instead of checking appearance, just use the direct preference
        let iconName = useDarkIconPreference ? "AppIconDark" : nil // nil = default icon
        
        // Only change if needed
        if UIApplication.shared.alternateIconName != iconName {
            UIApplication.shared.setAlternateIconName(iconName) { error in
                if let error = error {
                    print("Error changing app icon: \(error.localizedDescription)")
                } else {
                    print("App icon changed successfully to \(useDarkIconPreference ? "dark" : "light")")
                }
            }
        }
    }

    // Add this function to your ContentView struct
    private func clearAllCustomDays() {
        var modifiedCount = 0
        
        // Update all day statuses to unmodified (0)
        for workDay in workDays {
            if workDay.dayStatus > 0 {
                workDay.dayStatus = 0
                modifiedCount += 1
            }
        }
        
        // Only save if we made changes
        if modifiedCount > 0 {
            do {
                try modelContext.save()
                print("Successfully reset \(modifiedCount) custom day states to follow default patterns")
                
                // Set last update time for widget syncing
                if let sharedDefaults = UserDefaults(suiteName: appGroupID) {
                    sharedDefaults.set(Date().timeIntervalSince1970, forKey: lastUpdateKey)
                    sharedDefaults.synchronize()
                }
                
                // Force widgets to reload
                reloadWidgets()
            } catch {
                print("Failed to save after clearing custom days: \(error.localizedDescription)")
            }
        } else {
            print("No custom day states needed to be reset")
        }
    }

    // Add this function to ContentView struct
    private func resetDayStatus(_ date: Date) {
        // Check if this date already exists in our store
        if let existingWorkDay = workDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            // Reset the status to 0 (follow default pattern)
            existingWorkDay.dayStatus = 0
            
            // Also reset any partial day shifts if that feature is enabled
            if patternManager.enablePartialDayFeature {
                existingWorkDay.shifts = [] // Clear all shifts
            }
            
            // Try to save changes
            do {
                try modelContext.save()
                
                // Update widget data
                if let sharedDefaults = UserDefaults(suiteName: appGroupID) {
                    sharedDefaults.set(Date().timeIntervalSince1970, forKey: lastUpdateKey)
                    sharedDefaults.synchronize()
                }
                
                // Force widgets to refresh
                reloadWidgets()
            } catch {
                print("Error resetting day status: \(error.localizedDescription)")
            }
        }
    }

    // Move the global getPartialDayShifts function to be a method inside ContentView
    func getPartialDayShifts(forDate date: Date) -> [Int] {
        // First check if this date has been manually set in the database
        if let workDay = workDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            // If this day was explicitly set by user
            if workDay.dayStatus > 0 {
                if workDay.dayStatus == 3 && workDay.shifts != nil {
                    // Return the user-specified shifts for this partial day
                    return workDay.shifts!
                } else if workDay.dayStatus == 2 {
                    // For a full work day, return all shifts based on the number of shifts
                    return getFullDayShifts(for: patternManager.numberOfShifts)
                } else {
                    // Off day, return empty array
                    return []
                }
            }
        }
        
        // If no user-edited data found, fall back to default pattern
        return getDefaultPartialDayShifts(date)
    }
    
    // Helper function for getPartialDayShifts
    private func getFullDayShifts(for numberOfShifts: Int) -> [Int] {
        switch numberOfShifts {
        case 2: return [2, 4]          // morning and night
        case 3: return [2, 3, 4]       // morning, noon, night
        case 4: return [1, 2, 3, 4]    // early morning, morning, noon, night
        default: return [2, 4]         // default to 2-shift
        }
    }
    
    // Updated hasShift function to match the pattern
    func hasShift(forDate date: Date, shift: Int) -> Bool {
        let shifts = getPartialDayShifts(forDate: date)
        return shifts.contains(shift)
    }

    // Add this function to ContentView
    func updateDayShifts(_ date: Date, shifts: [Int]) {
        // Get the start of the day to ensure consistent date comparison
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        // Look for existing WorkDay object
        if let existingWorkDay = workDays.first(where: { calendar.isDate($0.date, inSameDayAs: startOfDay) }) {
            // Update existing WorkDay
            existingWorkDay.date = startOfDay
            existingWorkDay.dayStatus = shifts.isEmpty ? 1 : 3 // 1 = not workday, 3 = partial day
            existingWorkDay.shifts = shifts.isEmpty ? nil : shifts
            
            // If an off day has no shifts, convert it to a regular off day
            if shifts.isEmpty {
                existingWorkDay.dayStatus = 1
                existingWorkDay.shifts = nil
            }
        } else {
            // Create new WorkDay
            let newWorkDay = WorkDay(date: startOfDay)
            newWorkDay.dayStatus = shifts.isEmpty ? 1 : 3 // 1 = not workday, 3 = partial day
            newWorkDay.shifts = shifts.isEmpty ? nil : shifts
            
            // Add to model context
            modelContext.insert(newWorkDay)
        }
        
        // Save changes
        do {
            try modelContext.save()
            
            // Update the shared UserDefaults for widget refresh
            if let sharedDefaults = UserDefaults(suiteName: appGroupID) {
                sharedDefaults.set(Date().timeIntervalSince1970, forKey: lastUpdateKey)
                sharedDefaults.synchronize()
            }
            
            // Force widgets to refresh
            reloadWidgets()
        } catch {
            print("Error updating day shifts: \(error.localizedDescription)")
        }
    }

    // Add this function to cycle shifts for 2-shift system in calendar view
    func updateDayShifts2Ver(date: Date) {
        // Get current shifts for this date
        let currentShifts = getPartialDayShifts(forDate: date)
        
        // Determine current state and cycle to next state (similar to cycleDayState logic)
        let validShifts = [2, 4] // 2-shift system: morning (2) and night (4)
        
        var newShifts: [Int] = []
        
        if currentShifts.isEmpty {
            // From rest -> full day (all shifts)
            newShifts = validShifts
        } else if currentShifts.count == validShifts.count {
            // From full day -> morning only
            newShifts = [2] // Morning shift only
        } else if currentShifts.contains(2) && !currentShifts.contains(4) {
            // From morning only -> night only
            newShifts = [4] // Night shift only
        } else {
            // From night only (or any other state) -> rest
            newShifts = []
        }
        
        // Update the day with new shifts
        updateDayShifts(date, shifts: newShifts)
    }
}

// Modified WeekPatternEditorView with improved spacing
struct WeekPatternEditorView: View {
    @Binding var weekPattern: [Bool]
    let startOfWeek: Int
    let languagePreference: Int
    
    var body: some View {
        // Use GeometryReader to get full width of container
        GeometryReader { geometry in
            // Calculate equal spacing based on container width
            let availableWidth = geometry.size.width
            let buttonSize: CGFloat = 36
            let spacing = (availableWidth - (buttonSize * 7)) / 6
            
            HStack(spacing: spacing) {
                ForEach(0..<7, id: \.self) { index in
                    let adjustedIndex = (index + startOfWeek) % 7
                    
                    Button {
                        var newPattern = weekPattern
                        newPattern[adjustedIndex] = !newPattern[adjustedIndex]
                        weekPattern = newPattern
                    } label: {
                        ZStack {
                            Circle()
                                .fill(weekPattern[adjustedIndex] ? Color.red : Color.green)
                                .opacity(0.8)
                                .frame(width: buttonSize, height: buttonSize)
                            
                            Text(dayAbbreviation(for: adjustedIndex))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contentShape(Circle())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
        }
        .frame(height: 50) // Fixed height for the GeometryReader
        .padding(.vertical, 4)
    }
    
    // Helper function to get appropriate day abbreviation based on language
    private func dayAbbreviation(for dayIndex: Int) -> String {
        let language = AppLanguage(rawValue: languagePreference) ?? .systemDefault
        
        // Use system language if set to default
        let systemLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        let useChineseChars = (language == .chinese) || 
                              (language == .systemDefault && systemLanguage.hasPrefix("zh"))
        
        if useChineseChars {
            // Use Chinese characters
            let chineseDays = ["日", "一", "二", "三", "四", "五", "六"]
            return chineseDays[dayIndex]
        } else {
            // Use English abbreviations
            let englishDays = ["S", "M", "T", "W", "T", "F", "S"]
            return englishDays[dayIndex]
        }
    }
}

// Modified ShiftPatternEditorView with fixed spacing
struct ShiftPatternEditorView: View {
    @Binding var shiftPattern: [Bool]
    let languagePreference: Int
    let workText: String
    let offText: String
    
    var body: some View {

        let buttonSize: CGFloat = 36
        let cirSpace: CGFloat = shiftPattern.count > 8 ? 2 : 5

        HStack(alignment: .center, spacing: cirSpace) { // Fixed spacing of 2 points
            ForEach(0..<shiftPattern.count, id: \.self) { index in
                Button {
                    var newPattern = shiftPattern
                    newPattern[index] = !newPattern[index]
                    shiftPattern = newPattern
                } label: {
                    ZStack {
                        Circle()
                            .fill(shiftPattern[index] ? Color.red : Color.green)
                            .opacity(0.8)
                            .frame(width: buttonSize, height: buttonSize)
                        
                        // Day number (1-based)
                        Text("\(index + 1)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Circle())
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 36)
        .padding(.vertical, 4)

    .frame(height: 50) // Fixed height for the container
    }
}

// Add this struct after ShiftPatternEditorView
struct PartialDayPatternEditorView: View {
    @Binding var partialDayPattern: [[Int]]
    let numberOfShifts: Int
    @Environment(\.colorScheme) private var colorScheme // Add this line
    
    var body: some View {
        HStack(alignment: .center, spacing: partialDayPattern.count > 8 ? 2 : 5) {
            ForEach(0..<partialDayPattern.count, id: \.self) { index in
                if numberOfShifts == 2 {
                    // 2-shift version: ShiftCircle with cycling states
                    VStack(spacing: 2) {
                        // Day number (1-based)
                        Text("\(index + 1)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Button {
                            cycleDayState(for: index)
                        } label: {
                            ShiftCircle(
                                shifts: partialDayPattern[index],
                                numberOfShifts: numberOfShifts,
                                size: 36,
                                baseOpacity: 0.8,
                                dividerColor: colorScheme == .dark ? Color.black.opacity(0.5) : Color.white.opacity(0.5)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                } else {
                    // 3 or 4 shift version: Enhanced ShiftRectangle with tappable segments
                    VStack(spacing: 2) {
                        // Day number (1-based)
                        Text("\(index + 1)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        ShiftRectangle(
                            shifts: partialDayPattern[index],
                            numberOfShifts: numberOfShifts,
                            width: 36, 
                            height: 100,
                            baseOpacity: 0.8,
                            onShiftToggle: { shiftNumber in
                                toggleShift(for: index, shift: shiftNumber)
                            },
                            cornerRadius: 8,
                            dividerColor: colorScheme == .dark ? Color.black.opacity(0.8) : Color.white.opacity(0.8)
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: numberOfShifts > 2 ? 130 : 60)
        .padding(.vertical, 4)
    }
    
    // Get the valid shift numbers based on numberOfShifts
    var validShiftNumbers: [Int] {
        switch numberOfShifts {
        case 2: return [2, 4]          // morning and night
        case 3: return [2, 3, 4]       // morning, noon, night
        case 4: return [1, 2, 3, 4]    // early morning, morning, noon, night
        default: return [2, 4]         // default to 2-shift
        }
    }
    
    // Function to cycle through states for 2-shift mode
    private func cycleDayState(for index: Int) {
        var currentShifts = partialDayPattern[index]
        
        // Determine current state and cycle to next state
        if currentShifts.isEmpty {
            // From rest -> full day (all shifts)
            currentShifts = validShiftNumbers
        } else if currentShifts.count == validShiftNumbers.count {
            // From full day -> morning only
            currentShifts = [2] // Morning shift only
        } else if currentShifts.contains(2) && !currentShifts.contains(4) {
            // From morning only -> night only
            currentShifts = [4] // Night shift only
        } else {
            // From night only (or any other state) -> rest
            currentShifts = []
        }
        
        // Update the pattern
        var newPattern = partialDayPattern
        newPattern[index] = currentShifts
        partialDayPattern = newPattern
    }
    
    // Function to toggle specific shift for 3 or 4 shift mode
    private func toggleShift(for index: Int, shift: Int) {
        var currentShifts = partialDayPattern[index]
        
        if currentShifts.contains(shift) {
            // Remove the shift if already present
            currentShifts.removeAll { $0 == shift }
        } else {
            // Add the shift if not present
            currentShifts.append(shift)
            currentShifts.sort() // Keep sorted for consistency
        }
        
        // Update the pattern
        var newPattern = partialDayPattern
        newPattern[index] = currentShifts
        partialDayPattern = newPattern
    }
}

#Preview {
    ContentView()
        .modelContainer(for: WorkDay.self, inMemory: true)
}

