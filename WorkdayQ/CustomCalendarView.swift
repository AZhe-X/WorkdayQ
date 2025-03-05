//
//  CustomCalendarView.swift
//  WorkdayQ
//
//  A simplified calendar view that shows only day mode. The user can navigate
//  between months with < and >, but there is no separate month-picking screen.
//

import SwiftUI

// Simple direction enum, in case we ever want to track left/right. 
// Currently, we do not animate transitions.
enum SlideDirection {
    case none, left, right
}

// CustomCalendarView: a simplified calendar for showing days only
struct CustomCalendarView: View {
    @Binding var selectedDate: Date
    let workDays: [WorkDay]
    @Environment(\.modelContext) private var modelContext
    
    // Language preference, start-of-week, and status opacity difference
    var languagePreference: Int = 0
    var startOfWeekPreference: Int = 0
    var showStatusOpacityDifference: Bool = true
    
    // Callbacks for toggling (tap) and editing notes (long press)
    var onToggleWorkStatus: ((Date) -> Void)?
    var onOpenNoteEditor: ((Date) -> Void)?
    
    // Internal state for updating the displayed month
    @State private var currentMonth = Date()
    
    // Calendar layout constants
    private let calendarGridHeight: CGFloat = 300
    private let dayHeight: CGFloat = 42
    private let rowSpacing: CGFloat = 8

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            headerView
                .frame(height: 50)
            
            dayOfWeekHeader
                .frame(height: 25)
            
            daysGridView
        }
        .frame(maxWidth: .infinity) // Make the container use full width
    }
    
    // MARK: - Header
    /// Header with < Month Year > controls
    private var headerView: some View {
        HStack {
            // Left arrow to go to previous month
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.primary)
            }
            Spacer()
            
            // Display localized month and year
            Text(localizedMonthYear())
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Spacer()
            // Right arrow to go to next month
            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.primary)
            }
        }
        .padding(.vertical)
    }

    // MARK: - Day-of-week header
    /// (Sun / Mon / Tue / ...). The exact order depends on startOfWeekPreference
    private var dayOfWeekHeader: some View {
        HStack {
            ForEach(localizedWeekdaySymbols, id: \.self) { day in
                Text(day)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Grid of days
    /// Dynamically calculates the necessary rows, but keeps the container fixed height
    private var daysGridView: some View {
        let weeks = daysInMonth().chunked(into: 7)
        let numberOfWeeks = weeks.count
        
        // The content might need only 4, 5, or 6 rows
        let contentHeight = CGFloat(numberOfWeeks) * dayHeight + CGFloat(numberOfWeeks - 1) * rowSpacing
        
        return ZStack(alignment: .top) {
            // Fixed background rectangle to maintain consistent size
            Rectangle()
                .fill(Color.clear)
                .frame(height: calendarGridHeight)
            
            VStack(spacing: rowSpacing) {
                ForEach(0..<numberOfWeeks, id: \.self) { weekIndex in
                    HStack(spacing: 0) {
                        ForEach(0..<7) { dayIndex in
                            // Safely unwrap the date in this row & column
                            if dayIndex < weeks[weekIndex].count {
                                let date = weeks[weekIndex][dayIndex]
                                if date.monthInt != currentMonth.monthInt {
                                    // Adjacent month date (faded)
                                    dayView(for: date)
                                        .opacity(0.1)
                                        .allowsHitTesting(false) // No interaction
                                        .frame(height: dayHeight)
                                        .frame(maxWidth: .infinity)
                                } else {
                                    // Current month date
                                    dayView(for: date)
                                        .frame(height: dayHeight)
                                        .frame(maxWidth: .infinity)
                                }
                            } else {
                                // Empty cell if chunk is smaller than 7
                                Color.clear
                                    .frame(height: dayHeight)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: contentHeight) // Actual grid size
            .id(currentMonth) // Force refresh on month change
        }
        .frame(height: calendarGridHeight) // Keep container height fixed
        .clipped()
    }

    // MARK: - Single Day Cell
    @ViewBuilder
    private func dayView(for date: Date) -> some View {
        let isToday = Calendar.current.isDate(date, inSameDayAs: Date())
        let isWorkDay = self.isWorkDay(date)
        let hasUserNote = dayHasNote(date)
        let hasSystemNote = HolidayManager.shared.getSystemNote(for: date) != nil
        let day = Calendar.current.component(.day, from: date)
        
        // If user explicitly set a day, we show it more opaque if toggled
        let isUserSet = isExplicitlySetByUser(date)
        let baseOpacity = showStatusOpacityDifference ? (isUserSet ? 0.8 : 0.5) : 0.8
        
        // We'll color work days red, off days green
        let red = Color.red
        let green = Color.green
        
        ZStack {
            // Background circle depends on whether it's work/off day
            if isWorkDay {
                if isToday {
                    TodayCircleView(color: red, opacity: baseOpacity)
                } else {
                    Circle()
                        .fill(red.opacity(baseOpacity))
                        .frame(width: 36, height: 36)
                }
            } else {
                if isToday {
                    TodayCircleView(color: green, opacity: baseOpacity)
                } else {
                    Circle()
                        .fill(green.opacity(baseOpacity))
                        .frame(width: 36, height: 36)
                }
            }
            
            // Day number + note indicators
            VStack(spacing: 2) {
                Text("\(day)")
                    .font(.callout)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundColor(.white)
                
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(hasSystemNote ? 1 : 0), lineWidth: 1)
                        .frame(width: 5, height: 5)
                    
                    Circle()
                        .fill(Color.white.opacity(hasUserNote ? 1 : 0))
                        .frame(width: 3, height: 3)
                }
            }
        }
        .contentShape(Rectangle())
        // Tapping toggles the day's workday/off status
        .onTapGesture {
            selectedDate = date
            onToggleWorkStatus?(date)
        }
        // Long press to edit notes
        .onLongPressGesture {
            selectedDate = date
            onOpenNoteEditor?(date)
        }
    }

    // MARK: - Helper View for Today
    private struct TodayCircleView: View {
        let color: Color
        let opacity: Double
        
        var body: some View {
            ZStack {
                Circle()
                    .fill(color.opacity(opacity))
                    .frame(width: 36, height: 36)
                
                Circle()
                    .stroke(Color(UIColor.systemBackground), lineWidth: 4.5)
                    .frame(width: 36, height: 36)
                
                Circle()
                    .stroke(color.opacity(0.8), lineWidth: 1.5)
                    .frame(width: 36, height: 36)
            }
        }
    }
    
    // MARK: - Navigation
    private func previousMonth() {
        currentMonth = Calendar.current.date(
            byAdding: .month,
            value: -1,
            to: currentMonth
        ) ?? currentMonth
    }
    
    private func nextMonth() {
        currentMonth = Calendar.current.date(
            byAdding: .month,
            value: 1,
            to: currentMonth
        ) ?? currentMonth
    }
    
    // MARK: - Date/WorkDay Helpers
    private func daysInMonth() -> [Date] {
        let calendar = Calendar.current
        
        // First day of currentMonth
        guard let firstOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: currentMonth)
        ) else {
            return []
        }
        
        // Start-of-week offset
        let firstDayWeekday = calendar.component(.weekday, from: firstOfMonth)
        
        // Convert to Monday-based or Sunday-based index
        let offset = (startOfWeekPreference == 1) 
            ? (firstDayWeekday + 5) % 7  // Monday start
            : (firstDayWeekday - 1)      // Sunday start

        guard let startDate = calendar.date(byAdding: .day, value: -offset, to: firstOfMonth) else {
            return []
        }
        
        // Last day of the current month
        guard
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfMonth),
            let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: nextMonth)
        else {
            return []
        }
        
        // Calculate how many days we need after the last day
        let lastDayWeekday = calendar.component(.weekday, from: lastDayOfMonth)
        var daysAfter = (startOfWeekPreference == 1)
            ? (7 - ((lastDayWeekday + 5) % 7 + 1))  // Monday-based
            : (7 - lastDayWeekday)                  // Sunday-based
        
        if daysAfter == 7 {
            daysAfter = 0
        }
        
        let daysBefore = offset
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
        let totalDays = daysBefore + daysInMonth + daysAfter
        
        // Construct the needed date array
        var dates: [Date] = []
        for i in 0..<totalDays {
            if let date = calendar.date(byAdding: .day, value: i, to: startDate) {
                dates.append(date)
            }
        }
        return dates
    }
    
    private func isWorkDay(_ date: Date) -> Bool {
        let calendar = Calendar.current
        // Highest priority: user-set
        if let explicitDay = workDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            return explicitDay.isWorkDay
        }
        // Next: holiday data
        if let holidayStatus = HolidayManager.shared.isWorkDay(for: date) {
            return holidayStatus
        }
        // Finally: default rule (Mon-Fri are workdays)
        return isDefaultWorkDay(date)
    }
    
    private func isExplicitlySetByUser(_ date: Date) -> Bool {
        let calendar = Calendar.current
        if let existing = workDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            // Compare existing with holiday data or default rule
            if let holidayStatus = HolidayManager.shared.isWorkDay(for: date) {
                return holidayStatus != existing.isWorkDay
            }
            return isDefaultWorkDay(date) != existing.isWorkDay
        }
        return false
    }
    
    private func dayHasNote(_ date: Date) -> Bool {
        let calendar = Calendar.current
        if let workDay = workDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            return workDay.note?.isEmpty == false
        }
        return false
    }
    
    // MARK: - Localization Helpers
    private func localizedMonthYear() -> String {
        let language = AppLanguage(rawValue: languagePreference) ?? .systemDefault
        
        if language == .chinese {
            let cal = Calendar.current
            let y = cal.component(.year, from: currentMonth)
            let m = cal.component(.month, from: currentMonth)
            return "\(y)年\(m)月"
        } else {
            // e.g., "March 2025"
            return currentMonth.formatted(.dateTime.month().year())
        }
    }
    
    private var localizedWeekdaySymbols: [String] {
        let language = AppLanguage(rawValue: languagePreference) ?? .systemDefault
        let cal = Calendar.current
        
        // If Chinese
        if language == .chinese {
            let chineseSymbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            if startOfWeekPreference == 1 {
                // Monday as first day
                var monFirst = Array(chineseSymbols[1...])
                monFirst.append(chineseSymbols[0])
                return monFirst
            } else {
                return chineseSymbols
            }
        } else {
            // System short symbols
            let symbols = cal.shortWeekdaySymbols
            if startOfWeekPreference == 1 {
                // Monday as first
                var monFirst = Array(symbols[1...])
                monFirst.append(symbols[0])
                return monFirst
            } else {
                return symbols
            }
        }
    }
}

// MARK: - Extensions
extension Date {
    /// Quick helper to get month
    var monthInt: Int {
        Calendar.current.component(.month, from: self)
    }
}

extension Array {
    /// Splits an array into chunks of `size`.
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { i in
            Array(self[i ..< Swift.min(i + size, count)])
        }
    }
}

// MARK: - Preview
struct CustomCalendarView_Previews: PreviewProvider {
    @State static var selectedDate = Date()
    
    static var previews: some View {
        CustomCalendarView(
            selectedDate: $selectedDate,
            workDays: [
                WorkDay(date: Date(), isWorkDay: true),
                WorkDay(date: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, isWorkDay: false),
                WorkDay(date: Calendar.current.date(byAdding: .day, value: 2, to: Date())!, isWorkDay: true)
            ],
            languagePreference: AppLanguage.english.rawValue,
            startOfWeekPreference: 1,
            showStatusOpacityDifference: true
        )
        .padding()
        .background(Color(UIColor.systemBackground))
        .previewLayout(.sizeThatFits)
    }
}