//
//  HolidayManager.swift
//  WorkdayQ
//
//  Created for holiday management functionality
//

import Foundation
import SwiftUI

// Constants for Holiday Manager
let holidayPreferenceKey = "holidayPreference"
let lastHolidayFetchKey = "lastHolidayFetch"
let holidayDataKey = "holidayData"

// Holiday data model
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

// Holiday preference options
enum HolidayPreference: Int, CaseIterable, Identifiable {
    case none = 0
    case chinese = 1
    case us = 2
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .chinese: return "Chinese Holidays"
        case .us: return "US Federal Holidays"
        }
    }
    
    var localizedName: (english: String, chinese: String) {
        switch self {
        case .none: return ("None", "无")
        case .chinese: return ("Chinese Holidays", "中国节假日")
        case .us: return ("US Federal Holidays", "美国联邦节假日")
        }
    }
    
    var calendarUrl: URL? {
        switch self {
        case .none:
            return nil
        case .chinese:
            return URL(string: "https://calendars.icloud.com/holidays/cn_zh.ics")
        case .us:
            // Using a reliable source for US Federal holidays
            return URL(string: "https://www.officeholidays.com/ics/usa")
        }
    }
}

class HolidayManager {
    static let shared = HolidayManager()
    
    private let userDefaults = UserDefaults.standard
    private let sharedDefaults = UserDefaults(suiteName: appGroupID)
    
    // In-memory cache of holiday data
    private var holidays: [HolidayInfo] = []
    
    private init() {
        // Load saved holidays when initialized
        loadHolidays()
    }
    
    // Get current holiday preference
    var currentPreference: HolidayPreference {
        let rawValue = userDefaults.integer(forKey: holidayPreferenceKey)
        return HolidayPreference(rawValue: rawValue) ?? .none
    }
    
    // Set holiday preference and sync to shared defaults
    func setHolidayPreference(_ preference: HolidayPreference) {
        userDefaults.set(preference.rawValue, forKey: holidayPreferenceKey)
        
        // Also save to shared defaults for widget access
        sharedDefaults?.set(preference.rawValue, forKey: holidayPreferenceKey)
        sharedDefaults?.synchronize()
        
        // If changing from or to .none, we should refresh holidays
        fetchHolidays()
    }
    
    // Fetch holidays based on current preference
    func fetchHolidays(completion: ((Bool) -> Void)? = nil) {
        let preference = currentPreference
        print("🔍 fetchHolidays started - preference: \(preference.displayName)")
        
        // If preference is none, clear holidays
        if preference == .none {
            print("❌ No holiday preference selected, clearing holidays")
            self.holidays = []
            self.saveHolidays()
            completion?(true)
            return
        }
        
        // Get URL for current preference
        guard let calendarUrl = preference.calendarUrl else {
            print("❌ No calendar URL available for preference: \(preference.displayName)")
            completion?(false)
            return
        }
        
        print("🌐 Attempting to fetch holiday data from: \(calendarUrl.absoluteString)")
        
        // Create URL session task to fetch holiday data
        let task = URLSession.shared.dataTask(with: calendarUrl) { [weak self] (data, response, error) in
            if let error = error {
                print("❌ Network error fetching holidays: \(error.localizedDescription)")
                print("❌ Error details: \(error)")
                DispatchQueue.main.async {
                    completion?(false)
                }
                return
            }
            
            // Log HTTP Response details
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 HTTP Response Status: \(httpResponse.statusCode)")
                print("📡 HTTP Response Headers: \(httpResponse.allHeaderFields)")
                
                if httpResponse.statusCode != 200 {
                    print("❌ Received non-success status code: \(httpResponse.statusCode)")
                    DispatchQueue.main.async {
                        completion?(false)
                    }
                    return
                }
            } else {
                print("⚠️ Response is not an HTTP response")
            }
            
            guard let self = self else {
                print("❌ Self reference lost in network completion")
                DispatchQueue.main.async {
                    completion?(false)
                }
                return
            }
            
            guard let data = data else {
                print("❌ No data received from holiday calendar URL")
                DispatchQueue.main.async {
                    completion?(false)
                }
                return
            }
            
            print("✅ Holiday data received - size: \(data.count) bytes")
            
            // Parse ICS data
            print("🔄 Beginning to parse holiday data...")
            let parsedHolidays = self.parseICSData(data, for: preference)
            print("✅ Parsing complete - found \(parsedHolidays.count) holiday events")
            
            self.holidays = parsedHolidays
            
            // Save to UserDefaults
            print("💾 Saving holiday data to UserDefaults...")
            self.saveHolidays()
            
            // Log identified holiday dates to console
            print("📊 Generating holiday summary report...")
            self.logHolidayInformation()
            
            // Update last fetch date
            let now = Date().timeIntervalSince1970
            UserDefaults.standard.set(now, forKey: lastHolidayFetchKey)
            print("🕒 Updated last fetch timestamp: \(Date(timeIntervalSince1970: now))")
            
            DispatchQueue.main.async {
                print("✅ Holiday fetch completed successfully")
                completion?(true)
            }
        }
        
        task.resume()
        print("🔄 Network request initiated for holiday data")
    }
    
    // New function to log holiday information to console
    private func logHolidayInformation() {
        print("⏳ Beginning holiday information logging...")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        
        print("=== Holiday Data Refresh Summary ===")
        print("Total holiday events identified: \(holidays.count)")
        
        // Filter and display work days
        let workDays = holidays.filter { $0.isWorkDay }
        print("\n🟥 WORK DAYS (\(workDays.count) days):")
        if workDays.isEmpty {
            print("- None found")
        } else {
            workDays.sorted(by: { $0.date < $1.date }).forEach { holiday in
                print("- \(dateFormatter.string(from: holiday.date)): \(holiday.name)")
            }
        }
        
        // Filter and display rest days
        let restDays = holidays.filter { !$0.isWorkDay }
        print("\n🟩 REST DAYS (\(restDays.count) days):")
        if restDays.isEmpty {
            print("- None found")
        } else {
            restDays.sorted(by: { $0.date < $1.date }).forEach { holiday in
                print("- \(dateFormatter.string(from: holiday.date)): \(holiday.name)")
            }
        }
        
        print("\n=== End of Holiday Data Summary ===")
        print("✅ Holiday information logging complete")
    }
    
    // Parse ICS data and extract holiday information
    private func parseICSData(_ data: Data, for preference: HolidayPreference) -> [HolidayInfo] {
        guard let icsString = String(data: data, encoding: .utf8) else {
            print("❌ Failed to decode ICS data as UTF-8 string")
            return []
        }
        
        print("📄 ICS data decoded, length: \(icsString.count) characters")
        
        var holidays: [HolidayInfo] = []
        
        // Split by events
        let events = icsString.components(separatedBy: "BEGIN:VEVENT")
        print("📄 Found \(events.count - 1) events in ICS data") // -1 because first component is header
        
        if preference == .chinese {
            // Filter events with special tags
            let workDayEvents = events.dropFirst().filter { 
                $0.contains("X-APPLE-SPECIAL-DAY:ALTERNATE-WORKDAY")
            }
            print("🔍 Found \(workDayEvents.count) events with ALTERNATE-WORKDAY tag")
            
            let restDayEvents = events.dropFirst().filter { 
                $0.contains("X-APPLE-SPECIAL-DAY:WORK-HOLIDAY")
            }
            print("🔍 Found \(restDayEvents.count) events with WORK-HOLIDAY tag")
            
            // Process work day events
            print("\n🔍 Processing work day events:")
            for event in workDayEvents {
                if let holiday = extractHoliday(from: event, isWorkDay: true) {
                    print("🟥 Added work day: \(holiday.date) - \(holiday.name)")
                    holidays.append(holiday)
                }
            }
            
            // Process rest day events
            print("\n🔍 Processing rest day events:")
            for event in restDayEvents {
                if let holiday = extractHoliday(from: event, isWorkDay: false) {
                    print("🟩 Added rest day: \(holiday.date) - \(holiday.name)")
                    holidays.append(holiday)
                }
            }
        } else {
            // For US holidays, all are rest days
            for event in events.dropFirst() {
                if let holiday = extractHoliday(from: event, isWorkDay: false) {
                    print("🟩 Added US holiday (rest day): \(holiday.date) - \(holiday.name)")
                    holidays.append(holiday)
                }
            }
        }
        
        print("✅ Finished parsing ICS data, found \(holidays.count) relevant holiday events")
        return holidays
    }
    
    // Helper function to extract a holiday from an event string
    private func extractHoliday(from event: String, isWorkDay: Bool) -> HolidayInfo? {
        print("📝 Extracting holiday info, isWorkDay: \(isWorkDay)")
        
        // Extract date
        var date: Date?
        if let dateRange = event.range(of: "DTSTART;VALUE=DATE:") {
            let startIndex = dateRange.upperBound
            let endIndex = event.index(startIndex, offsetBy: 8) // Date format: YYYYMMDD
            let dateString = String(event[startIndex..<endIndex])
            print("   Found date string: \(dateString)")
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            date = formatter.date(from: dateString)
            
            if let validDate = date {
                print("   Parsed date: \(validDate)")
            } else {
                print("❌ Failed to parse date from string: \(dateString)")
            }
        } else {
            print("❌ No DTSTART;VALUE=DATE: found in event")
        }
        
        // Extract summary/name - handle both formats
        var name = ""
        
        // Try to find the summary line with language info first
        if let summaryRange = event.range(of: "SUMMARY;LANGUAGE=zh_CN:") {
            print("   Found SUMMARY;LANGUAGE=zh_CN:")
            let startIndex = summaryRange.upperBound
            
            // Find where the summary line ends (look for the next line that starts with a different property)
            let summaryText = String(event[startIndex...])
            if let nextLineIndex = summaryText.range(of: "\n") ?? summaryText.range(of: "\r") {
                // Create a proper range from start to nextLineIndex
                let range = summaryText.startIndex..<nextLineIndex.lowerBound
                name = String(summaryText[range])
                name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                print("   Extracted name: \(name)")
            } else {
                // If no newline found, take the rest of the string but limit it
                name = summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
                if name.count > 50 { // Likely captured too much
                    name = String(name.prefix(50)) // Limit to reasonable length
                }
                print("   Extracted name (no newline found): \(name)")
            }
        } 
        // Try regular summary format if language version not found
        else if let summaryRange = event.range(of: "SUMMARY:") {
            print("   Found SUMMARY:")
            let startIndex = summaryRange.upperBound
            
            // Find where the summary line ends
            let summaryText = String(event[startIndex...])
            if let nextLineIndex = summaryText.range(of: "\n") ?? summaryText.range(of: "\r") {
                // Create a proper range from start to nextLineIndex
                let range = summaryText.startIndex..<nextLineIndex.lowerBound
                name = String(summaryText[range])
                name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                print("   Extracted name: \(name)")
            } else {
                // If no newline found, take the rest of the string but limit it
                name = summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
                if name.count > 50 { // Likely captured too much
                    name = String(name.prefix(50)) // Limit to reasonable length
                }
                print("   Extracted name (no newline found): \(name)")
            }
        } else {
            print("❌ No SUMMARY: or SUMMARY;LANGUAGE=zh_CN: found in event")
            // Debug the event content
            print("Event content preview: \(String(event.prefix(200)))")
        }
        
        // Additional cleanup to ensure no ICS metadata is included
        // Look for common metadata markers and remove everything after them
        let metadataMarkers = ["TRANSP:", "CATEGORIES:", "X-APPLE-"]
        for marker in metadataMarkers {
            if let markerRange = name.range(of: marker) {
                name = String(name[..<markerRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Skip if no date or name
        guard let validDate = date, !name.isEmpty else {
            print("❌ Skipping event due to missing date or name")
            return nil
        }
        
        // Create and return the holiday info
        print("✅ Successfully created holiday: \(validDate) - \(name)")
        return HolidayInfo(
            date: validDate,
            name: name,
            isWorkDay: isWorkDay,
            type: isWorkDay ? .adjustedWork : .holiday
        )
    }
    
    // Save holidays to UserDefaults
    private func saveHolidays() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(self.holidays)
            
            // Save to standard UserDefaults
            userDefaults.set(data, forKey: holidayDataKey)
            
            // Also save to shared UserDefaults for widget access
            sharedDefaults?.set(data, forKey: holidayDataKey)
            sharedDefaults?.synchronize()
        } catch {
            print("Failed to save holidays: \(error.localizedDescription)")
        }
    }
    
    // Load holidays from UserDefaults
    private func loadHolidays() {
        if let data = userDefaults.data(forKey: holidayDataKey) {
            do {
                let decoder = JSONDecoder()
                self.holidays = try decoder.decode([HolidayInfo].self, from: data)
            } catch {
                print("Failed to load holidays: \(error.localizedDescription)")
                self.holidays = []
            }
        } else {
            self.holidays = []
        }
    }
    
    // Get holiday information for a specific date
    func getHolidayInfo(for date: Date) -> HolidayInfo? {
        let calendar = Calendar.current
        return holidays.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    // Check if a date has holiday information
    func hasHolidayInfo(for date: Date) -> Bool {
        return getHolidayInfo(for: date) != nil
    }
    
    // Determine if a date is a workday based on holiday information
    func isWorkDay(for date: Date) -> Bool? {
        if let holidayInfo = getHolidayInfo(for: date) {
            return holidayInfo.isWorkDay
        }
        return nil
    }
    
    // Get system note for a date (holiday name)
    func getSystemNote(for date: Date) -> String? {
        return getHolidayInfo(for: date)?.name
    }
} 