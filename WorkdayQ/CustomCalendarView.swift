//
//  CustomCalendarView.swift
//  WorkdayQ
//

import SwiftUI

struct CustomCalendarView: View {
    @Binding var selectedDate: Date
    let workDays: [WorkDay]
    @Environment(\.modelContext) private var modelContext
    
    // Add callbacks for actions
    var onToggleWorkStatus: ((Date) -> Void)?
    var onOpenNoteEditor: ((Date) -> Void)?
    
    @State private var currentMonth = Date()
    @State private var slideDirection: SlideDirection = .none
    
    // New state for hierarchical date selection
    @State private var calendarViewMode: CalendarViewMode = .days
    
    // Fixed sizes to prevent layout shifts
    private let calendarGridHeight: CGFloat = 300
    private let dayHeight: CGFloat = 42 // Fixed height for each day
    private let rowSpacing: CGFloat = 8 // Fixed spacing between rows
    
    enum SlideDirection {
        case none, left, right
    }
    
    enum CalendarViewMode {
        case days, months, years
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header changes based on view mode
            calendarHeader
            
            // Content changes based on view mode
            switch calendarViewMode {
            case .days:
                dayOfWeekHeader
                daysGridView
            case .months:
                monthsGridView
            case .years:
                yearsGridView
            }
        }
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.3), value: currentMonth)
        .animation(.easeInOut(duration: 0.3), value: calendarViewMode)
    }
    
    // Dynamic header based on current view mode
    private var calendarHeader: some View {
        HStack {
            Button(action: navigatePrevious) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Title changes based on view mode and is tappable
            Button(action: advanceToNextViewMode) {
                Text(headerTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            Spacer()
            
            Button(action: navigateNext) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.primary)
            }
        }
        .padding(.vertical)
    }
    
    // Title text changes based on current view mode
    private var headerTitle: String {
        let calendar = Calendar.current
        switch calendarViewMode {
        case .days:
            // Show month and year
            return currentMonth.formatted(.dateTime.month().year())
        case .months:
            // Show just the year
            return String(calendar.component(.year, from: currentMonth))
        case .years:
            // Show year range
            let year = calendar.component(.year, from: currentMonth)
            let decadeStart = year - (year % 10)
            return "\(decadeStart) - \(decadeStart + 9)"
        }
    }
    
    // Action for the title button
    private func advanceToNextViewMode() {
        withAnimation {
            switch calendarViewMode {
            case .days:
                calendarViewMode = .months
            case .months:
                calendarViewMode = .years
            case .years:
                // Already at highest level, do nothing
                break
            }
        }
    }
    
    // Navigation buttons do different things based on view mode
    private func navigatePrevious() {
        switch calendarViewMode {
        case .days:
            previousMonth()
        case .months:
            previousYear()
        case .years:
            previousDecade()
        }
    }
    
    private func navigateNext() {
        switch calendarViewMode {
        case .days:
            nextMonth()
        case .months:
            nextYear()
        case .years:
            nextDecade()
        }
    }
    
    private var dayOfWeekHeader: some View {
        HStack {
            ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { day in
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
            .transition(slideDirection == .left ? 
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ) : 
                        .asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
        }
        .frame(height: calendarGridHeight)
        .clipped() // Prevent any content from overflowing
    }
    
    // New view for month selection grid
    private var monthsGridView: some View {
        let monthNames = Calendar.current.monthSymbols
        let columns = Array(repeating: GridItem(.flexible()), count: 3)
        
        return LazyVGrid(columns: columns, spacing: 20) {
            ForEach(0..<12) { monthIndex in
                let month = monthIndex + 1
                
                Button(action: {
                    selectMonth(month)
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isCurrentMonth(month) ? Color.blue.opacity(0.2) : Color.clear)
                            .frame(height: 60)
                        
                        Text(monthNames[monthIndex])
                            .fontWeight(isCurrentMonth(month) ? .bold : .regular)
                    }
                }
            }
        }
        .frame(height: calendarGridHeight)
        .transition(.opacity)
    }
    
    // New view for year selection grid
    private var yearsGridView: some View {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: currentMonth)
        let decadeStart = currentYear - (currentYear % 10)
        let columns = Array(repeating: GridItem(.flexible()), count: 3)
        
        return LazyVGrid(columns: columns, spacing: 20) {
            ForEach(0..<12) { offset in
                let year = decadeStart - 1 + offset
                
                Button(action: {
                    selectYear(year)
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(year == currentYear ? Color.blue.opacity(0.2) : Color.clear)
                            .frame(height: 60)
                        
                        Text("\(year)")
                            .fontWeight(year == currentYear ? .bold : .regular)
                    }
                }
            }
        }
        .frame(height: calendarGridHeight)
        .transition(.opacity)
    }
    
    // Helper to check if month is the current displayed month
    private func isCurrentMonth(_ month: Int) -> Bool {
        let calendar = Calendar.current
        return calendar.component(.month, from: currentMonth) == month
    }
    
    // Action when a month is selected
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
        
        // Go back to days view
        withAnimation {
            calendarViewMode = .days
        }
    }
    
    // Action when a year is selected
    private func selectYear(_ year: Int) {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: currentMonth)
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = 1
        
        if let newDate = calendar.date(from: dateComponents) {
            currentMonth = newDate
        }
        
        // Go back to months view
        withAnimation {
            calendarViewMode = .months
        }
    }
    
    // Original day view
    @ViewBuilder
    private func dayView(for date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let isToday = Calendar.current.isDate(date, inSameDayAs: Date())
        let dayWorkDay = getDayWorkStatus(date)
        let hasNote = dayHasNote(date)
        let day = Calendar.current.component(.day, from: date)
        
        ZStack {
            // Always show a circle with appropriate color
            Circle()
                .fill(dayWorkDay == true ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                .aspectRatio(1, contentMode: .fit)
                .frame(width: 36, height: 36) // Fixed size for circles
            
            if isSelected {
                Circle()
                    .stroke(Color.blue, lineWidth: 2)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: 36, height: 36)
            } else if isToday {
                Circle()
                    .stroke(Color.gray, lineWidth: 1)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: 36, height: 36)
            }
            
            VStack(spacing: 2) {
                Text("\(day)")
                    .font(.callout)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundColor(.white) // Always white text for better contrast
                
                // Add a small dot indicator when the day has a note
                if hasNote {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 4, height: 4)
                } else {
                    // Empty spacer to maintain consistent layout
                    Spacer().frame(height: 4)
                }
            }
        }
        // Add tap gesture to toggle work status
        .onTapGesture {
            // First select the date (for visual feedback)
            selectedDate = date
            // Then toggle the status
            onToggleWorkStatus?(date)
        }
        // Add long press gesture to edit notes
        .onLongPressGesture {
            // First select the date
            selectedDate = date
            // Then open note editor
            onOpenNoteEditor?(date)
        }
    }
    
    private func getDayWorkStatus(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return workDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) })?.isWorkDay ?? false
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
    
    private func previousDecade() {
        withAnimation {
            currentMonth = Calendar.current.date(
                byAdding: .year,
                value: -10,
                to: currentMonth
            ) ?? currentMonth
        }
    }
    
    private func nextDecade() {
        withAnimation {
            currentMonth = Calendar.current.date(
                byAdding: .year,
                value: 10,
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
        let weekdayIndex = firstDayWeekday - 1 // 0-indexed weekday
        
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

struct CustomCalendarView_Previews: PreviewProvider {
    @State static var selectedDate = Date()
    
    static var previews: some View {
        CustomCalendarView(
            selectedDate: $selectedDate,
            workDays: [
                WorkDay(date: Date(), isWorkDay: true),
                WorkDay(date: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, isWorkDay: false),
                WorkDay(date: Calendar.current.date(byAdding: .day, value: 2, to: Date())!, isWorkDay: true)
            ]
        )
        .padding()
        .background(Color(UIColor.systemBackground))
        .previewLayout(.sizeThatFits)
    }
}