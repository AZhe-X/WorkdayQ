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

// Add extension to dismiss keyboard (place after imports, before constants)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// Helper to determine if a date is a workday by default
// (Monday-Friday = workday, Saturday-Sunday = off day)
func isDefaultWorkDay(_ date: Date) -> Bool {
    let weekday = Calendar.current.component(.weekday, from: date)
    // 1 = Sunday, 2 = Monday, ..., 7 = Saturday
    return weekday >= 2 && weekday <= 6 // Monday to Friday
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
    @AppStorage(showStatusOpacityDifferenceKey) private var showStatusOpacityDifference = true // Default: true
    @FocusState private var isCustomTermFieldFocused: Bool // Add focus state
    
    // Holiday-related state
    @AppStorage(holidayPreferenceKey) private var holidayPreference = 0 // Default: none
    @State private var isRefreshingHolidays = false
    @State private var lastRefreshStatus: Bool? = nil
    
    // Add explicit app group UserDefaults access for direct writes
    private let sharedDefaults = UserDefaults(suiteName: appGroupID)
    
    /// UNIFIED FUNCTION: Determine if a date is a work day using the three-tier priority system
    /// 1. First check explicit user-set entry (highest priority)
    /// 2. Then check holiday data (medium priority)
    /// 3. Finally fall back to default weekday rules (lowest priority)
    /// - Parameter date: The date to check
    /// - Returns: true if it's a work day, false if it's an off day
    func isWorkDay(forDate date: Date) -> Bool {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        
        // First check if we have an explicit user record (highest priority)
        if let explicitDay = workDays.first(where: { calendar.isDate($0.date, inSameDayAs: dayStart) }) {
            return explicitDay.isWorkDay
        }
        
        // Next check holiday data (medium priority)
        if let holidayStatus = HolidayManager.shared.isWorkDay(for: dayStart) {
            return holidayStatus
        }
        
        // Fall back to default rules (lowest priority)
        return isDefaultWorkDay(dayStart)
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
                    showStatusOpacityDifference: showStatusOpacityDifference,
                    onToggleWorkStatus: { date in
                        toggleWorkStatus(for: date)
                    },
                    onOpenNoteEditor: { date in
                        // Set up note editor for the selected date
                        if let selectedDay = workDays.first(where: { 
                            Calendar.current.isDate($0.date, inSameDayAs: date)
                        }) {
                            noteText = selectedDay.note ?? ""
                        } else {
                            noteText = ""
                        }
                        showingNoteEditor = true
                    }
                )
                
                // Instructions for interactions
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(localizedText("Tap a day to toggle work/off status", 
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
                    Spacer()
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
            }
            .sheet(isPresented: $showingSettings) {
                settingsView
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                // Always update selectedDate to today when view appears
                selectedDate = Date()
                
                checkAndCreateTodayEntry()
                // Always reload widget when view appears
                reloadWidgets()
                // Make sure shared defaults has the current language preference
                syncLanguagePreference()
                // Also sync appearance preference
                syncAppearancePreference()
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
            
            // Show "Today is:" or "今天" based on language
            if languagePreference == AppLanguage.chinese.rawValue {
                Text("今天")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .padding(.bottom, -6)
                    .fontWeight(.semibold)
            } else {
                Text(localizedText("Today is", chineseText: "今天是"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, -6)
                    .fontWeight(.semibold)
            }
            
            HStack {
                let isWorkDay = isWorkDay(forDate: Date()) // Use unified function
                
                // Use different text format for Chinese
                if languagePreference == AppLanguage.chinese.rawValue {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(customizeWorkTerm(isWorkDay ? "要上班" : "不上班"))
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(isWorkDay ? .red : .green)
                        
                        // Add holiday note if available
                        if let holidayNote = HolidayManager.shared.getSystemNote(for: Date()) {
                            Text(holidayNote)
                                .font(.title3)
                                .foregroundColor(.gray)
                        }
                    }
                } else {
                    // Now make English layout match Chinese layout
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(isWorkDay ? 
                             localizedText("Workday", chineseText: "工作日") : 
                             localizedText("Off day", chineseText: "休息日"))
                            .font(.largeTitle) // Changed from .title2 to match Chinese
                            .fontWeight(.bold)
                            .foregroundColor(isWorkDay ? .red : .green)
                        
                        // Add holiday note if available - same as Chinese version
                        if let holidayNote = HolidayManager.shared.getSystemNote(for: Date()) {
                            Text(holidayNote)
                                .font(.title3)
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Spacer()
                
                Circle()
                    .fill(isWorkDay ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                    .frame(width: 50, height: 50)
                    .padding(.bottom, 1)
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
                // User note input with 15 character limit
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizedText("Your Not:", chineseText: "您的备注:"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField(localizedText("Enter note", chineseText: "输入备注"), 
                              text: $noteText)
                        .padding()
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: noteText) { oldValue, newValue in
                            // Limit to 15 characters
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
                
                // Display system note (holiday) if available
                if let systemNote = HolidayManager.shared.getSystemNote(for: selectedDate) {
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
    
    private func toggleWorkStatus(for date: Date) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        
        // If an entry already exists, toggle its status
        if let existingDay = workDays.first(where: { calendar.isDate($0.date, inSameDayAs: dayStart) }) {
            // Toggle the work status (only changing the work status, not touching the note)
            existingDay.isWorkDay.toggle()
            
            // Save the updated entry - we never delete entries when toggling work status
            // This ensures that user-set work statuses are always preserved
        } else {
            // No entry exists - create a new one with toggled status (opposite of the expected status)
            let expectedStatus = isWorkDay(forDate: dayStart) // Use unified function
            let newStatus = !expectedStatus  // Toggle from whatever would be expected (default or holiday)
            
            // Create new entry with the toggled status and empty note
            let newWorkDay = WorkDay(date: dayStart, isWorkDay: newStatus)
            modelContext.insert(newWorkDay)
        }
        
        // Save data and notify widget
        do {
            try modelContext.save()
            notifyWidgetDataChanged()
        } catch {
            print("Error saving work status change: \(error.localizedDescription)")
        }
    }
    
    private func saveNote() {
        let calendar = Calendar.current
        let selectedDayStart = calendar.startOfDay(for: selectedDate)
        
        if let existingDay = workDays.first(where: { calendar.isDate($0.date, inSameDayAs: selectedDayStart) }) {
            // Just update the note, don't touch the work status
            existingDay.note = noteText.isEmpty ? nil : noteText
            
            // If the note is now empty, and we have an explicit record just for a note,
            // we can delete it (but ONLY if the work status is already the expected one)
            if (existingDay.note == nil || existingDay.note!.isEmpty) {
                // This is the expected status without our explicit entry
                let expectedStatus = isWorkDay(forDate: selectedDayStart) // Use unified function
                
                // Only delete if the entry has the same work status as expected
                // AND the note is empty - this means the entry isn't providing any value
                if existingDay.isWorkDay == expectedStatus {
                    modelContext.delete(existingDay)
                }
            }
        } else {
            // Only create a new entry if there is a note to add
            if !noteText.isEmpty {
                // Get the expected work status but don't modify it
                // This honors any holiday or default status
                let expectedStatus = isWorkDay(forDate: selectedDayStart) // Use unified function
                
                // Create new entry with the expected status and the note
                let newWorkDay = WorkDay(date: selectedDayStart, isWorkDay: expectedStatus, note: noteText)
                modelContext.insert(newWorkDay)
            }
            // If note is empty, we don't create a database entry at all
        }
        
        // Save data and notify widget
        do {
            try modelContext.save()
            notifyWidgetDataChanged()
        } catch {
            print("Error saving note: \(error.localizedDescription)")
        }
    }
    
    // Force reload of all widgets
    private func reloadWidgets() {
        // First, update the timestamp in UserDefaults to signal change
        if let sharedDefaults = UserDefaults(suiteName: appGroupID) {
            let timestamp = Date().timeIntervalSince1970
            sharedDefaults.set(timestamp, forKey: lastUpdateKey)
            
            // Make sure language preference is also synced
            sharedDefaults.set(languagePreference, forKey: languagePreferenceKey)
            
            // Make sure custom work term is also synced
            sharedDefaults.set(customWorkTerm, forKey: customWorkTermKey)
            
            // Make sure appearance preference is also synced
            sharedDefaults.set(appearancePreference, forKey: appearancePreferenceKey)
            
            // Make sure start of week preference is also synced
            sharedDefaults.set(startOfWeekPreference, forKey: startOfWeekPreferenceKey)
            
            // Make sure show status opacity difference preference is also synced
            sharedDefaults.set(showStatusOpacityDifference, forKey: showStatusOpacityDifferenceKey)
            
            // Force write
            sharedDefaults.synchronize()
            
            // Cache the work days data for widget fallback access
            cacheWorkDaysToUserDefaults(workDays)
        }
        
        // Tell WidgetKit to reload
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
                "isWorkDay": workDay.isWorkDay
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
                Section(header: Text(localizedText("Holidays", chineseText: "节假日"))) {
                    Picker(localizedText("Holiday Calendar", chineseText: "节假日日历"), selection: $holidayPreference) {
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

                // Customization Settings
                Section(header: Text(localizedText("Customization", chineseText: "自定义"))) {
                    ZStack {
                        Color.clear
                            .contentShape(Rectangle()) // Make the entire area tappable
                            .onTapGesture {
                                // Dismiss keyboard when tapping outside the TextField
                                isCustomTermFieldFocused = false
                                hideKeyboard() // Add direct keyboard dismissal
                            }
                        
                        VStack(alignment: .leading) {
                            Text(localizedText("Customize work term (Chinese)", chineseText: "自定义工作用语"))
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
                                    // Sync to UserDefaults for widget access
                                    syncCustomWorkTerm()
                                    // Reload widgets to show new term
                                    reloadWidgets()
                                }
                            
                            Text(localizedText("Examples: 上课 (class), 上学 (school)", chineseText: "例如：上课、上学、值班"))
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
                    
                    // Add new toggle for opacity differentiation
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
                }
                
                Section(header: Text(localizedText("About", chineseText: "关于"))) {
                    HStack {
                        Text(localizedText("Version", chineseText: "版本"))
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://example.com/privacy")!) {
                        Label(localizedText("Privacy Policy", chineseText: "隐私政策"), systemImage: "lock.shield")
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
}

#Preview {
    ContentView()
        .modelContainer(for: WorkDay.self, inMemory: true)
}

