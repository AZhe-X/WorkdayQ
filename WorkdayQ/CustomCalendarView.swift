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
    @Environment(\.colorScheme) private var colorScheme
    
    // Language preference, start-of-week, and status opacity difference
    var languagePreference: Int = 0
    var startOfWeekPreference: Int = 0
    var showStatusOpacityDifference: Bool = true
    var patternManager: WorkdayPatternManager = WorkdayPatternManager.shared
    var isEraserModeActive: Bool = false
    var isCalendarLocked: Bool = false // Add calendar lock parameter
    
    // Function parameters
    var isWorkDayFunction: ((Date) -> Bool)?
    var getPartialDayShiftsFunction: ((Date) -> [Int])?
    
    // Callbacks for toggling (tap) and editing notes (long press)
    var onToggleWorkStatus: ((Date) -> Void)?
    var onOpenNoteEditor: ((Date) -> Void)?
    var onCycleShifts: ((Date) -> Void)?
    var onToggleShift: ((Date, Int) -> Void)?
    
    // Internal state for updating the displayed month
    @State private var currentMonth = Date()
    
    // Add this to keep track of slide direction for animations
    @State private var slideDirection: SlideDirection = .none
    
    // Calendar layout constants
    private let calendarGridHeight: CGFloat = 300
    private let dayHeight: CGFloat = 42
    private let rowSpacing: CGFloat = 8

    // Add to top of CustomCalendarView struct
    @State private var isShowingMonthSelection = false  // Track if we're showing month selection
    @State private var yearForMonthSelection = Date()   // The year we're viewing in month selection
    @State private var yearSlideDirection: SlideDirection = .none  // For year navigation

    // Add these state variables to the CustomCalendarView struct
    @State private var showingShiftEditor = false
    @State private var dateForShiftEditor: Date?
    @State private var isPopoverStable = true // Add this to track popover stability

    // Now accept a month Date parameter so we can show different months
    private func calendarContent(for displayMonth: Date) -> some View {
        VStack(spacing: 0) {
            headerView(for: displayMonth)
                .frame(height: 50)
            
            dayOfWeekHeader
                .frame(height: 25)
            
            daysGridView
        }
        .frame(maxWidth: .infinity)
    }

    // Now call that function inside body
    var body: some View {
        if isShowingMonthSelection {
            monthSelectionView
                .animation(.easeInOut(duration: 0.3), value: yearForMonthSelection)
        } else {
            calendarContent(for: currentMonth)
                .animation(.easeInOut(duration: 0.3), value: currentMonth)
        }
    }
    
    // MARK: - Header
    /// Header with < Month Year > controls
    private func headerView(for displayMonth: Date) -> some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.primary)
            }
            Spacer()
            
            // Make the month title tappable to show month selection
            Button(action: {
                yearForMonthSelection = displayMonth  // Save the current year for selection
                withAnimation(.easeInOut(duration: 0.25)) {
                    isShowingMonthSelection = true
                }
            }) {
                Text(localizedMonthYear(for: displayMonth))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .transition(.asymmetric(
                insertion: .move(edge: slideDirection == .left ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: slideDirection == .left ? .leading : .trailing).combined(with: .opacity)
            ))
            .id("month-title-\(displayMonth.timeIntervalSince1970)")
            
            Spacer()
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
        .transition(.asymmetric(
            insertion: .move(edge: slideDirection == .left ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: slideDirection == .left ? .leading : .trailing).combined(with: .opacity)
        ))
        .id("day-headers-\(currentMonth.timeIntervalSince1970)") // Force regeneration
    }
    
    // MARK: - Grid of days
    /// Dynamically calculates the necessary rows, but keeps the container fixed height
    private var daysGridView: some View {
        let weeks = daysInMonth(for: currentMonth).chunked(into: 7)
        let numberOfWeeks = weeks.count
        
        // The content might need only 4, 5, or 6 rows
        let contentHeight = CGFloat(numberOfWeeks) * dayHeight + CGFloat(numberOfWeeks - 1) * rowSpacing
        
        return ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.clear)
                .frame(height: calendarGridHeight)
            
            VStack(spacing: rowSpacing) {
                ForEach(0..<numberOfWeeks, id: \.self) { weekIndex in
                    HStack(spacing: 0) {
                        ForEach(0..<7) { dayIndex in
                            if dayIndex < weeks[weekIndex].count {
                                let date = weeks[weekIndex][dayIndex]
                                if date.monthInt != currentMonth.monthInt {
                                    // Adjacent month date (faded)
                                    dayView(for: date)
                                        .opacity(0.3)
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
            .transition(.asymmetric(
                insertion: .move(edge: slideDirection == .left ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: slideDirection == .left ? .leading : .trailing).combined(with: .opacity)
            ))
            .id("month-grid-\(currentMonth.timeIntervalSince1970)") // Force regeneration
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
        let opacity = showStatusOpacityDifference ? (isUserSet ? 0.8 : 0.5) : 0.8
        
        // We'll color work days red, off days green
        let red = Color.red
        let green = Color.green
        
        // Check if the day is in the currently displayed month
        let isInCurrentMonth = date.monthInt == currentMonth.monthInt
        
        // Move this here so we can trigger the popover from this specific date
        let isCurrentDateForEditor = dateForShiftEditor != nil && Calendar.current.isDate(date, inSameDayAs: dateForShiftEditor!)

        let workDay = workDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })
        
        ZStack {

            // Background circle
            if isWorkDay {
                if isToday {TodayCircleView(color: red).zIndex(100)}
                    // Regular workday
                    if patternManager.enablePartialDayFeature {
                        let shifts = getPartialDayShiftsFunction?(date) ?? getDefaultPartialDayShifts(date)
                        ShiftCircle(
                            shifts: shifts,
                            numberOfShifts: patternManager.numberOfShifts,
                            size: 36,
                            baseOpacity: opacity,
                            dividerColor: colorScheme == .dark ? Color.black.opacity(0.5) : Color.white.opacity(0.5)
                        )
                    } else {
                        Circle()
                        .fill(red.opacity(opacity))
                        .frame(width: 36, height: 36)
                    }

                    

            } else {
                if isToday {TodayCircleView(color: green).zIndex(100)}
                    // Regular off day
                    Circle()
                        .fill(green.opacity(opacity))
                        .frame(width: 36, height: 36)

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
        // Only add the work status toggle tap gesture for current month days
        .onTapGesture {
            if isInCurrentMonth {
                if patternManager.enablePartialDayFeature {
                    // First check if calendar is locked
                    if isCalendarLocked {
                        return
                    }
                    
                    if patternManager.numberOfShifts == 2 {
                        selectedDate = date
                        onCycleShifts?(date)
                    } else {
                        // For 3+ shifts: check if eraser mode is active
                        selectedDate = date
                        
                        if isEraserModeActive {
                            // In eraser mode, directly trigger the reset function
                            onCycleShifts?(date) // This will call resetDayStatus in ContentView
                        } else {
                            // Normal mode: show popover for editing
                            // First ensure any existing popover is dismissed
                            if showingShiftEditor {
                                showingShiftEditor = false
                                
                                // Use a short delay before showing the new popover
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    dateForShiftEditor = date
                                    isPopoverStable = true
                                    showingShiftEditor = true
                                }
                            } else {
                                dateForShiftEditor = date
                                isPopoverStable = true
                                showingShiftEditor = true
                            }
                        }
                    }
                } else {
                    selectedDate = date
                    onToggleWorkStatus?(date)
                }
            } else {
                // For days not in the current month, navigate to that month
                navigateToAdjacentDay(date)
            }
        }
        // Only add long press for current month days with haptic feedback
        .onLongPressGesture {
            if isInCurrentMonth {
                // Generate haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.prepare()
                impactFeedback.impactOccurred()
                
                selectedDate = date
                onOpenNoteEditor?(date)
            }
        }
        // Move the popover to be triggered for this specific day only
        .popover(isPresented: Binding<Bool>(
            get: { isCurrentDateForEditor && showingShiftEditor },
            set: { showingShiftEditor = $0 }
        ), arrowEdge: .bottom) {
            if let dateToEdit = dateForShiftEditor {
                if let shifts = getPartialDayShiftsFunction?(dateToEdit) {
                    ShiftRectangle(
                        shifts: shifts,
                        numberOfShifts: patternManager.numberOfShifts,
                        width: 85,
                        height: 150,
                        baseOpacity: 0.8,
                        onShiftToggle: { shiftNumber in
                            // Disable animation when toggling shifts
                            withAnimation(.none) {
                                onToggleShift?(dateToEdit, shiftNumber)
                            }
                        },
                        cornerRadius: 12,
                        dividerColor: colorScheme == .dark ? Color.black.opacity(0.8) : Color.white.opacity(0.8)
                    )
                    // Force it to always show as a popover, not a sheet
                    .environment(\.horizontalSizeClass, .regular)
                    // Set fixed size to prevent adaptive behavior
                    .frame(width: 85, height: 150)
                    // Ensure proper presentation style
                    .presentationCompactAdaptation(.none)
                    // Explicitly set detent to prevent full screen
                    .presentationDetents([.height(160)])
                    // Remove any system padding
                    .padding(0)
                }
            }
        }
    }

    // MARK: - Helper View for Today
    private struct TodayCircleView: View {
        let color: Color
        
        var body: some View {
            ZStack {
                // Circle()
                //     .fill(color.opacity(opacity))
                //     .frame(width: 36, height: 36)
                
                Circle()
                    .stroke(Color(UIColor.systemBackground), lineWidth: 4.5)
                    .frame(width: 36, height: 36)
                    .zIndex(99)
                
                Circle()
                    .stroke(color.opacity(0.8), lineWidth: 1.5)
                    .frame(width: 36, height: 36)
                    .zIndex(100)
            }
        }
    }
    
    // MARK: - Navigation
    private func previousMonth() {
        slideDirection = .right // Going backward = content slides right
        withAnimation(.easeInOut(duration: 0.3)) {
            currentMonth = Calendar.current.date(
                byAdding: .month,
                value: -1,
                to: currentMonth
            ) ?? currentMonth
        }
    }
    
    private func nextMonth() {
        slideDirection = .left // Going forward = content slides left
        withAnimation(.easeInOut(duration: 0.3)) {
            currentMonth = Calendar.current.date(
                byAdding: .month,
                value: 1,
                to: currentMonth
            ) ?? currentMonth
        }
    }
    
    // Add this function after the nextMonth() and previousMonth() functions
    private func navigateToAdjacentDay(_ date: Date) {
        let calendar = Calendar.current
        
        // Compare full dates rather than just month numbers
        // This handles year boundaries correctly (e.g., December to January)
        if let currentStartOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) {
            
            // Get start of the target month
            if let targetStartOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) {
                
                // Compare the actual date components to determine if it's previous or next month
                if targetStartOfMonth < currentStartOfMonth {
                    previousMonth()
                } else if targetStartOfMonth > currentStartOfMonth {
                    nextMonth()
                }
                
                // Update selected date to the tapped date
                selectedDate = date
            }
        }
    }
    
    // MARK: - Date/WorkDay Helpers
    private func daysInMonth(for displayMonth: Date = Date()) -> [Date] {
        let calendar = Calendar.current
        
        // First day of currentMonth
        guard let firstOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: displayMonth)
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
        // Use the passed function if available
        if let isWorkDayFunction = isWorkDayFunction {
            return isWorkDayFunction(date)
        }
        
        // Minimal fallback that just uses the default pattern
        // This should never be needed in normal operation
        return isDefaultWorkDay(date)
    }
    
    private func isExplicitlySetByUser(_ date: Date) -> Bool {
        if let existingDay = workDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            return existingDay.dayStatus > 0
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
    private func localizedMonthYear(for displayMonth: Date) -> String {
        let language = AppLanguage(rawValue: languagePreference) ?? .systemDefault
        
        if language == .chinese {
            let cal = Calendar.current
            let y = cal.component(.year, from: displayMonth)
            let m = cal.component(.month, from: displayMonth)
            return "\(y)年\(m)月"
        } else {
            // e.g., "March 2025"
            return displayMonth.formatted(.dateTime.month().year())
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

    // MARK: - Month Selection View
    private var monthSelectionView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Year header with back/forward
            yearHeaderView
                .frame(height: 50)  // Same height as calendar header
            
            // 4x3 grid of months
            monthsGridView
                .frame(height: calendarGridHeight + 25)  // Match calendar height
        }
        .frame(maxWidth: .infinity)
    }

    private var yearHeaderView: some View {
        HStack {
            Button(action: previousYear) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.primary)
            }
            Spacer()
            
            Text(localizedYear(for: yearForMonthSelection))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .transition(.asymmetric(
                    insertion: .move(edge: yearSlideDirection == .left ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: yearSlideDirection == .left ? .leading : .trailing).combined(with: .opacity)
                ))
                .id("year-title-\(yearForMonthSelection.timeIntervalSince1970)")
            
            Spacer()
            Button(action: nextYear) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.primary)
            }
        }
        .padding(.vertical)
    }

    private var monthsGridView: some View {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: yearForMonthSelection)
        // Calculate cell size based on screen width
        let currentYear = calendar.component(.year, from: Date())
        let currentMonth = calendar.component(.month, from: Date())
        
        // Create a grid layout with 3 columns (4 rows x 3 columns = 12 months)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 0) {
            ForEach(1...12, id: \.self) { month in
                let isCurrentMonth = (year == currentYear && month == currentMonth)
                
                Button(action: {
                    selectMonth(month: month, year: year)
                }) {
                    monthCell(month: month, isCurrentMonth: isCurrentMonth)
                }
            }
        }
        .padding(.horizontal, 20) // Exactly 20pt padding on left/right
        .transition(.asymmetric(
            insertion: .move(edge: yearSlideDirection == .left ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: yearSlideDirection == .left ? .leading : .trailing).combined(with: .opacity)
        ))
        .id("months-grid-\(yearForMonthSelection.timeIntervalSince1970)")
    }

    // Replace both monthCell and monthMiniCalendar with this simpler implementation
    private func monthCell(month: Int, isCurrentMonth: Bool) -> some View {
        let monthName = localizedMonthName(month: month)
        let year = Calendar.current.component(.year, from: yearForMonthSelection)
        
        // Create date components for the first day of this month
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        
        // Size constants for mini-calendar
        let miniCircleSize: CGFloat = 4
        let miniRowSpacing: CGFloat = 5 
        let miniColSpacing: CGFloat = 5
        
        return VStack(spacing: 3) {
            // Month name at top
            Text(monthName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .padding(.bottom, 4)
                .opacity(isCurrentMonth ? 0.8 : 0.4) // Updated opacity based on current month
            
            // Conditionally show calendar if we can create the date
            if let firstOfMonth = Calendar.current.date(from: components) {
                let allDays = daysInMonth(for: firstOfMonth)
                let weeks = allDays.chunked(into: 7)
                
                // Mini calendar grid
                VStack(spacing: miniRowSpacing) {
                    ForEach(0..<min(6, max(1, weeks.count)), id: \.self) { weekIndex in
                        HStack(spacing: miniColSpacing) {
                            ForEach(0..<7, id: \.self) { dayIndex in
                                if weekIndex < weeks.count && dayIndex < weeks[weekIndex].count {
                                    let date = weeks[weekIndex][dayIndex]
                                    let isInCurrentMonth = date.monthInt == month
                                    
                                    Circle()
                                        .fill(isInCurrentMonth 
                                              ? (isWorkDay(date) ? Color.red : Color.green)
                                              : Color.clear)
                                        .frame(width: miniCircleSize, height: miniCircleSize)
                                        .opacity(isInCurrentMonth ? 0.8 : 0)
                                } else {
                                    Circle()
                                        .fill(Color.clear)
                                        .frame(width: miniCircleSize, height: miniCircleSize)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 3)
                .opacity(isCurrentMonth ? 0.8 : 0.4) // Updated opacity based on current month
            } else {
                // Fallback if date creation fails
                Spacer()
                    .frame(height: 70) // Approximate height to match the grid
            }
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cornerRadius(8)
        // Removed blue background and border
    }

    // MARK: - Year Navigation
    private func previousYear() {
        yearSlideDirection = .right
        withAnimation(.easeInOut(duration: 0.3)) {
            yearForMonthSelection = Calendar.current.date(
                byAdding: .year,
                value: -1,
                to: yearForMonthSelection
            ) ?? yearForMonthSelection
        }
    }

    private func nextYear() {
        yearSlideDirection = .left
        withAnimation(.easeInOut(duration: 0.3)) {
            yearForMonthSelection = Calendar.current.date(
                byAdding: .year,
                value: 1,
                to: yearForMonthSelection
            ) ?? yearForMonthSelection
        }
    }

    // Select a month and return to calendar view
    private func selectMonth(month: Int, year: Int) {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        
        if let selectedDate = Calendar.current.date(from: components) {
            // Set the current month to the selected date and return to calendar view
            currentMonth = selectedDate
            
            // Use the appropriate slide direction based on month relationship
            let currentMonthValue = Calendar.current.component(.month, from: currentMonth)
            if month < currentMonthValue {
                slideDirection = .right
            } else if month > currentMonthValue {
                slideDirection = .left
            }
            
            withAnimation(.easeInOut(duration: 0.25)) {
                isShowingMonthSelection = false
            }
        }
    }

    // MARK: - Additional Localization Helpers
    private func localizedYear(for date: Date) -> String {
        let language = AppLanguage(rawValue: languagePreference) ?? .systemDefault
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        
        if language == .chinese {
            return "\(year)年"
        } else {
            return "\(year)"
        }
    }

    private func localizedMonthName(month: Int) -> String {
        let language = AppLanguage(rawValue: languagePreference) ?? .systemDefault
        
        if language == .chinese {
            let chineseMonths = ["一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"]
            return chineseMonths[month - 1]
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale.current
            return dateFormatter.monthSymbols[month - 1]
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
            showStatusOpacityDifference: true,
            patternManager: WorkdayPatternManager.shared,
            isEraserModeActive: false,
            isWorkDayFunction: nil,
            getPartialDayShiftsFunction: nil
        )
        .padding()
        .background(Color(UIColor.systemBackground))
        .previewLayout(.sizeThatFits)
    }
}
