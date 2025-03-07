//
//  CustomCalendarView.swift
//  WorkdayQ
//

import SwiftUI

// Move enums outside of the struct to make them accessible
enum SlideDirection {
    case none, left, right
}

enum CalendarViewMode {
    case days, months
}

struct CustomCalendarView: View {
    @Binding var selectedDate: Date
    let workDays: [WorkDay]
    @Environment(\.modelContext) private var modelContext
    
    // Add a language preference parameter
    var languagePreference: Int = 0
    
    // Add start of week preference parameter
    var startOfWeekPreference: Int = 0
    
    // Add show status opacity difference parameter
    var showStatusOpacityDifference: Bool = true
    
    // Add callbacks for actions
    var onToggleWorkStatus: ((Date) -> Void)?
    var onOpenNoteEditor: ((Date) -> Void)?
    
    @State private var currentMonth = Date()
    @State private var slideDirection: SlideDirection = .none
    @State private var yearSlideDirection: SlideDirection = .none // For year navigation
    
    // State for hierarchical date selection (simplified)
    @State private var calendarViewMode: CalendarViewMode = .days
    
    // Fixed sizes to prevent layout shifts - ensure both views are identical height
    private let calendarGridHeight: CGFloat = 300
    private let dayHeight: CGFloat = 42 // Fixed height for each day
    private let rowSpacing: CGFloat = 8 // Fixed spacing between rows
    
    // Helper to get localized day names based on language preference
    private var localizedWeekdaySymbols: [String] {
        let language = AppLanguage(rawValue: languagePreference) ?? .systemDefault
        let calendar = Calendar.current
        
        if language == .chinese {
            // Chinese weekday symbols
            let chineseSymbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            
            // Re-order based on start of week preference
            if startOfWeekPreference == 1 { // Monday start
                // Move Sunday to the end
                var mondayFirstSymbols = Array(chineseSymbols[1...]) // Monday to Saturday
                mondayFirstSymbols.append(chineseSymbols[0]) // Add Sunday at the end
                return mondayFirstSymbols
            } else {
                // Default Sunday start
                return chineseSymbols
            }
        } else {
            // Get system weekday symbols
            let symbols = calendar.shortWeekdaySymbols
            
            // Re-order based on start of week preference
            if startOfWeekPreference == 1 { // Monday start
                // Move Sunday to the end
                var mondayFirstSymbols = Array(symbols[1...]) // Monday to Saturday
                mondayFirstSymbols.append(symbols[0]) // Add Sunday at the end
                return mondayFirstSymbols
            } else {
                // Default Sunday start
                return symbols
            }
        }
    }
    
    // Helper to get localized month name
    private func localizedMonthYear() -> String {
        let language = AppLanguage(rawValue: languagePreference) ?? .systemDefault
        
        if language == .chinese {
            let calendar = Calendar.current
            let year = calendar.component(.year, from: currentMonth)
            let month = calendar.component(.month, from: currentMonth)
            return "\(year)年\(month)月"
        } else {
            return currentMonth.formatted(.dateTime.month().year())
        }
    }
    
    // Helper to determine if a date is a workday (using default rules if no explicit entry)
    /// Determine if a date is a work day using the three-tier priority system
    /// 1. First check explicit user-set entry (highest priority)
    /// 2. Then check holiday data (medium priority)
    /// 3. Finally fall back to default weekday rules (lowest priority)
    /// - Parameter date: The date to check
    /// - Returns: true if it's a work day, false if it's an off day
    private func isWorkDay(_ date: Date) -> Bool {
        // First check if we have an explicit entry
        let calendar = Calendar.current
        if let explicitDay = workDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            return explicitDay.isWorkDay
        }
        
        // Next check holiday data (medium priority)
        if let holidayStatus = HolidayManager.shared.isWorkDay(for: date) {
            return holidayStatus
        }
        
        // Fall back to default rules
        return isDefaultWorkDay(date)
    }
    
    // Helper method to check if a day has been explicitly set by the user
    // Now checks if the work status differs from what would be expected
    private func isExplicitlySetByUser(_ date: Date) -> Bool {
        let calendar = Calendar.current
        
        // Check if we have an entry for this date
        if let existingDay = workDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            // First determine what the status would be without this explicit entry
            // (using holiday data or default rules)
            
            // Check what the status would be from holiday data
            if let holidayStatus = HolidayManager.shared.isWorkDay(for: date) {
                return existingDay.isWorkDay != holidayStatus
            }
            
            // If no holiday data, use default weekday/weekend rules
            let defaultStatus = isDefaultWorkDay(date)
            return existingDay.isWorkDay != defaultStatus
        }
        
        // No entry means not user-edited
        return false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header changes based on view mode
            headerView
            
            // Content changes based on view mode
            switch calendarViewMode {
            case .days:
                dayOfWeekHeader
                    .frame(height: 25) // Fixed height for day headers
                daysGridView
            case .months:
                // Add invisible spacer with same height as day header for consistent layout
                Color.clear.frame(height: 25)
                monthsGridView
            }
        }
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.3), value: currentMonth)
        .animation(.easeInOut(duration: 0.25), value: calendarViewMode) // Faster animation for view mode changes
        .animation(.easeInOut(duration: 0.3), value: slideDirection) // Animation for slide direction changes
        .animation(.easeInOut(duration: 0.3), value: yearSlideDirection) // Animation for year navigation
    }
    
    // Create a computed property for each header type with its own transition
    private var headerView: some View {
        ZStack {
            // Only one of these will be visible at a time due to the if conditions
            if calendarViewMode == .days {
                monthYearHeader
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity), // Coming from months (moving down)
                        removal: .move(edge: .bottom).combined(with: .opacity)    // Going to months (moving up)
                    ))
                    .id("month-year-header")
            } else {
                yearHeader
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),    // Coming from days (moving up)
                        removal: .move(edge: .top).combined(with: .opacity)       // Going to days (moving down)
                    ))
                    .id("year-header")
            }
        }
        .frame(height: 50) // Fixed height for header to prevent shifts
    }
    
    // Header showing Month Year (e.g., "March 2025")
    private var monthYearHeader: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Month + Year title with slide transition
            ZStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) { // Faster transition for mode change
                        calendarViewMode = .months
                    }
                }) {
                    Text(localizedMonthYear())
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                .id("month-title-\(localizedMonthYear())")
                .transition(.asymmetric(
                    insertion: slideDirection == .left ? 
                        .move(edge: .trailing).combined(with: .opacity) :
                        .move(edge: .leading).combined(with: .opacity),
                    removal: slideDirection == .left ? 
                        .move(edge: .leading).combined(with: .opacity) :
                        .move(edge: .trailing).combined(with: .opacity)
                ))
            }
            
            Spacer()
            
            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.primary)
            }
        }
        .padding(.vertical)
    }
    
    // Header showing just Year (e.g., "2025")
    private var yearHeader: some View {
        HStack {
            Button(action: {
                yearSlideDirection = .right
                previousYear()
            }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Year title as a separate ZStack with transition
            ZStack {
                // Use localized year format
                let year = Calendar.current.component(.year, from: currentMonth)
                let yearText = AppLanguage(rawValue: languagePreference) == .chinese ? 
                    "\(year)年" : "\(year)"
                
                Text(yearText)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .id("year-\(year)")
                    .transition(.asymmetric(
                        insertion: yearSlideDirection == .left ? 
                            .move(edge: .trailing).combined(with: .opacity) :
                            .move(edge: .leading).combined(with: .opacity),
                        removal: yearSlideDirection == .left ? 
                            .move(edge: .leading).combined(with: .opacity) :
                            .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
            
            Spacer()
            
            Button(action: {
                yearSlideDirection = .left
                nextYear()
            }) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.primary)
            }
        }
        .padding(.vertical)
    }
    
    // Day of week header (Sun, Mon, Tue, etc.)
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
        .padding(.bottom, 8) // Add consistent spacing after headers
    }
    
    // Original days view now extracted to its own computed property
    private var daysGridView: some View {
        // Fixed height container
        ZStack(alignment: .top) {
            // Background to ensure fixed size
            Rectangle()
                .fill(Color.clear)
                .frame(height: calendarGridHeight)
            
            // Calendar grid with transition
            VStack(spacing: 0) {
                // Use a fixed number of rows (6) for consistency
                let weeks = daysInMonth().chunked(into: 7) // Group days into weeks
                
                ForEach(0..<6) { weekIndex in
                    if weekIndex < weeks.count {
                        HStack(spacing: 0) {
                            ForEach(0..<7) { dayIndex in
                                if dayIndex < weeks[weekIndex].count {
                                    let date = weeks[weekIndex][dayIndex]
                                    if date.monthInt != currentMonth.monthInt {
                                        // Days from other months - empty placeholder
                                        Color.clear
                                            .frame(height: dayHeight)
                                            .frame(maxWidth: .infinity)
                                    } else {
                                        // Days from current month
                                        dayView(for: date)
                                            .frame(height: dayHeight)
                                            .frame(maxWidth: .infinity)
                                    }
                                } else {
                                    Color.clear
                                        .frame(height: dayHeight)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        // Empty row to maintain fixed height
                        HStack {
                            ForEach(0..<7, id: \.self) { _ in
                                Color.clear
                                    .frame(height: dayHeight)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    
                    if weekIndex < 5 { // Don't add spacing after the last row
                        Spacer().frame(height: rowSpacing)
                    }
                }
            }
            .frame(height: calendarGridHeight)
            .id(currentMonth) // This forces view recreation when month changes
            // Different transitions based on whether we're changing months or view modes
            .modifier(ContentTransitionModifier(slideDirection: slideDirection))
        }
        .frame(height: calendarGridHeight)
        .clipped() // Prevent any content from overflowing
    }
    
    // Month selection grid
    private var monthsGridView: some View {
        let monthNames = Calendar.current.monthSymbols
        let columns = Array(repeating: GridItem(.flexible()), count: 3)
        let currentYear = Calendar.current.component(.year, from: currentMonth)
        
        return ZStack(alignment: .top) {
            // Background container to maintain consistent height
            Rectangle()
                .fill(Color.clear)
                .frame(height: calendarGridHeight)
                
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(0..<12) { monthIndex in
                    let month = monthIndex + 1
                    
                    Button(action: {
                        selectMonth(month)
                    }) {
                        ZStack {
                            // Style based on month state - only highlight current month with border
                            let style = getMonthStyle(month: month)
                            
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(style.borderColor, lineWidth: style.borderWidth)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.clear) // Always clear background
                                )
                                .frame(height: 60)
                            
                            Text(monthNames[monthIndex])
                                .fontWeight(style.fontWeight)
                                .foregroundColor(style.fontColor)
                        }
                        .padding(.horizontal, 4) // Add padding to prevent cutoff
                    }
                }
            }
            .padding(.horizontal, 4) // Add horizontal padding to avoid edge cutoff
            .padding(.vertical, 4) // Small vertical padding
            .frame(height: calendarGridHeight)
            .id("months-\(currentYear)")
            .modifier(MonthsGridTransitionModifier(slideDirection: yearSlideDirection))
        }
        .frame(height: calendarGridHeight)
        .clipped() // Prevent any content from overflowing
        .transition(.opacity) // Simple fade transition instead of slide
    }
    
    // Helper to determine the style for each month based on its state
    private func getMonthStyle(month: Int) -> (background: Color, fontWeight: Font.Weight, fontColor: Color, borderColor: Color, borderWidth: CGFloat) {
        let isCurrentMonthToday = isCurrentMonthInToday(month)
        
        if isCurrentMonthToday {
            // Current month (today's month) - border only, no fill
            return (Color.clear, .bold, .primary, .blue, 2)
        } else {
            // Regular month - no highlight
            return (Color.clear, .regular, .primary, .clear, 0)
        }
    }
    
    // Helper to check if month is the currently displayed month
    private func isCurrentMonth(_ month: Int) -> Bool {
        let calendar = Calendar.current
        return calendar.component(.month, from: currentMonth) == month
    }
    
    // Helper to check if month is the current real month (today's month)
    private func isCurrentMonthInToday(_ month: Int) -> Bool {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: currentMonth)
        let todayYear = calendar.component(.year, from: Date())
        let todayMonth = calendar.component(.month, from: Date())
        
        return month == todayMonth && currentYear == todayYear
    }
    
    // Action when a month is selected - going from months -> days
    private func selectMonth(_ month: Int) {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: currentMonth)
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = 1
        
        if let newDate = calendar.date(from: dateComponents) {
            currentMonth = newDate
        }
        
        // Go back to days view with animation
        withAnimation(.easeInOut(duration: 0.35)) { // Slightly longer for smoother effect
            slideDirection = .none // Reset slide direction to trigger vertical transition
            calendarViewMode = .days
        }
    }
    
    // Day view with completely simplified structure
    @ViewBuilder
    private func dayView(for date: Date) -> some View {
        let isToday = Calendar.current.isDate(date, inSameDayAs: Date())
        let isWorkDay = self.isWorkDay(date)
        let hasUserNote = dayHasNote(date)
        let hasSystemNote = HolidayManager.shared.getSystemNote(for: date) != nil
        let day = Calendar.current.component(.day, from: date)
        let isUserSet = isExplicitlySetByUser(date)
        
        // Determine opacity
        let opacity = showStatusOpacityDifference ? (isUserSet ? 0.8 : 0.5) : 0.8
        
        // Get colors
        let red = Color.red
        let green = Color.green
        
        // Create the view with basic components
        ZStack {
            // Background circle
            if isWorkDay {
                if isToday {
                    // Today's workday
                    TodayCircleView(color: red, opacity: opacity)
                } else {
                    // Regular workday
                    Circle()
                        .fill(red.opacity(opacity))
                        .frame(width: 36, height: 36)
                }
            } else {
                if isToday {
                    // Today's off day
                    TodayCircleView(color: green, opacity: opacity)
                } else {
                    // Regular off day
                    Circle()
                        .fill(green.opacity(opacity))
                        .frame(width: 36, height: 36)
                }
            }
            
            // Day number and note indicator
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
        .onTapGesture {
            selectedDate = date
            onToggleWorkStatus?(date)
        }
        .onLongPressGesture {
            selectedDate = date
            onOpenNoteEditor?(date)
        }
    }
    
    // Helper view for today's circle with outline
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
    
    private func getDayWorkStatus(_ date: Date) -> Bool {
        return isWorkDay(date)
    }
    
    private func dayHasNote(_ date: Date) -> Bool {
        let calendar = Calendar.current
        if let workDay = workDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            return workDay.note != nil && !workDay.note!.isEmpty
        }
        return false
    }
    
    // Navigation functions
    private func previousMonth() {
        slideDirection = .right // Slide to the right when going to previous month
        withAnimation {
            currentMonth = Calendar.current.date(
                byAdding: .month,
                value: -1,
                to: currentMonth
            ) ?? currentMonth
        }
    }
    
    private func nextMonth() {
        slideDirection = .left // Slide to the left when going to next month
        withAnimation {
            currentMonth = Calendar.current.date(
                byAdding: .month,
                value: 1,
                to: currentMonth
            ) ?? currentMonth
        }
    }
    
    private func previousYear() {
        withAnimation {
            currentMonth = Calendar.current.date(
                byAdding: .year,
                value: -1,
                to: currentMonth
            ) ?? currentMonth
        }
    }
    
    private func nextYear() {
        withAnimation {
            currentMonth = Calendar.current.date(
                byAdding: .year,
                value: 1,
                to: currentMonth
            ) ?? currentMonth
        }
    }
    
    private func daysInMonth() -> [Date] {
        let calendar = Calendar.current
        
        // Get the first day of the month
        let firstDayOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: currentMonth)
        )!
        
        // Get the first day of the week for the starting point
        let firstDayWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        
        // Calculate weekday index based on start of week preference
        var weekdayIndex: Int
        if startOfWeekPreference == 1 { // Monday start
            // Convert weekday to Monday-based index (Monday=0, Sunday=6)
            weekdayIndex = (firstDayWeekday + 5) % 7
        } else { // Sunday start
            weekdayIndex = firstDayWeekday - 1 // Standard 0-indexed weekday (Sunday=0)
        }
        
        // Calculate the start date (which might be in the previous month)
        let startDate = calendar.date(
            byAdding: .day,
            value: -weekdayIndex,
            to: firstDayOfMonth
        )!
        
        // Create date array (42 days for 6 weeks grid)
        var dates: [Date] = []
        for day in 0..<42 {
            if let date = calendar.date(byAdding: .day, value: day, to: startDate) {
                dates.append(date)
            }
        }
        
        return dates
    }
}

// Extension to split array into chunks
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

extension Date {
    var monthInt: Int {
        Calendar.current.component(.month, from: self)
    }
}

// Add a new modifier to handle both transitions
struct ContentTransitionModifier: ViewModifier {
    let slideDirection: SlideDirection
    
    func body(content: Content) -> some View {
        if slideDirection == .none {
            // For view mode transitions - simple fade in/out
            content.transition(.opacity)
        } else if slideDirection == .left {
            // Horizontal transition when changing months (left)
            content.transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        } else {
            // Horizontal transition when changing months (right)
            content.transition(.asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            ))
        }
    }
}

// Add a modifier for month grid transitions when changing years
struct MonthsGridTransitionModifier: ViewModifier {
    let slideDirection: SlideDirection
    
    func body(content: Content) -> some View {
        if slideDirection == .left {
            // Horizontal transition when changing years (left)
            content.transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        } else if slideDirection == .right {
            // Horizontal transition when changing years (right)
            content.transition(.asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            ))
        } else {
            // No horizontal transition
            content
        }
    }
}

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
            startOfWeekPreference: 0 // Sunday start for preview
        )
        .padding()
        .background(Color(UIColor.systemBackground))
        .previewLayout(.sizeThatFits)
    }
}