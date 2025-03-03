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
    case days, months, years
}

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
    // Track which direction we're moving in the view hierarchy
    @State private var isMovingUpInTimeScale: Bool = true
    
    // Fixed sizes to prevent layout shifts
    private let calendarGridHeight: CGFloat = 300
    private let dayHeight: CGFloat = 42 // Fixed height for each day
    private let rowSpacing: CGFloat = 8 // Fixed spacing between rows
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header changes based on view mode
            headerView
            
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
    
    // Create a computed property for each header type with its own transition
    private var headerView: some View {
        ZStack {
            // Only one of these will be visible at a time due to the if conditions
            if calendarViewMode == .days {
                monthYearHeader
                    .transition(.asymmetric(
                        insertion: isMovingUpInTimeScale ? 
                            .move(edge: .top).combined(with: .opacity) :
                            .move(edge: .bottom).combined(with: .opacity),
                        removal: isMovingUpInTimeScale ? 
                            .move(edge: .bottom).combined(with: .opacity) :
                            .move(edge: .top).combined(with: .opacity)
                    ))
                    .id("month-year-header")
            } else if calendarViewMode == .months {
                yearHeader
                    .transition(.asymmetric(
                        insertion: isMovingUpInTimeScale ? 
                            .move(edge: .bottom).combined(with: .opacity) :
                            .move(edge: .top).combined(with: .opacity),
                        removal: isMovingUpInTimeScale ? 
                            .move(edge: .bottom).combined(with: .opacity) :
                            .move(edge: .top).combined(with: .opacity)
                    ))
                    .id("year-header")
            } else {
                decadeHeader
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                    .id("decade-header")
            }
        }
    }
    
    // Header showing Month Year (e.g., "March 2025")
    private var monthYearHeader: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Month + Year title
            Button(action: {
                withAnimation(.easeInOut(duration: 0.4)) {
                    isMovingUpInTimeScale = true
                    calendarViewMode = .months
                }
            }) {
                Text(currentMonth.formatted(.dateTime.month().year()))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
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
            Button(action: previousYear) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Year title
            Button(action: {
                withAnimation(.easeInOut(duration: 0.4)) {
                    isMovingUpInTimeScale = true
                    calendarViewMode = .years
                }
            }) {
                Text(String(Calendar.current.component(.year, from: currentMonth)))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            Button(action: nextYear) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.primary)
            }
        }
        .padding(.vertical)
    }
    
    // Header showing Decade range (e.g., "2020 - 2029")
    private var decadeHeader: some View {
        let year = Calendar.current.component(.year, from: currentMonth)
        let decadeStart = year - (year % 10)
        
        return HStack {
            Button(action: previousDecade) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Decade title (not clickable as there's no higher level)
            Text("\(decadeStart) - \(decadeStart + 9)")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: nextDecade) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.primary)
            }
        }
        .padding(.vertical)
    }
    
    // Day of week header (Sun, Mon, Tue, etc.)
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
            // Different transitions based on whether we're changing months or view modes
            .modifier(DaysTransitionModifier(slideDirection: slideDirection))
        }
        .frame(height: calendarGridHeight)
        .clipped() // Prevent any content from overflowing
    }
    
    // New view for month selection grid
    private var monthsGridView: some View {
        let monthNames = Calendar.current.monthSymbols
        let columns = Array(repeating: GridItem(.flexible()), count: 3)
        
        return ZStack(alignment: .top) {
            // Background container to maintain consistent height
            Rectangle()
                .fill(Color.clear)
                .frame(height: calendarGridHeight)
                
            LazyVGrid(columns: columns, spacing: 20) {
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
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .frame(maxHeight: calendarGridHeight) // Maintain same height as days view
        }
        .frame(height: calendarGridHeight)
        .transition(.asymmetric(
            // When coming from days or years view, months slide from appropriate direction
            insertion: isMovingUpInTimeScale ? 
                .move(edge: .bottom).combined(with: .opacity) : // Coming from days (moving up)
                .move(edge: .top).combined(with: .opacity),    // Coming from years (moving down)
            
            // When going to days or years view, months exit in appropriate direction
            removal: isMovingUpInTimeScale ? 
                .move(edge: .bottom).combined(with: .opacity) : // Going to years (moving up)
                .move(edge: .top).combined(with: .opacity)     // Going to days (moving down)
        ))
    }
    
    // New view for year selection grid
    private var yearsGridView: some View {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: currentMonth)
        let decadeStart = currentYear - (currentYear % 10)
        let columns = Array(repeating: GridItem(.flexible()), count: 3)
        
        return ZStack(alignment: .top) {
            // Background container to maintain consistent height
            Rectangle()
                .fill(Color.clear)
                .frame(height: calendarGridHeight)
                
            LazyVGrid(columns: columns, spacing: 20) {
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
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .frame(maxHeight: calendarGridHeight) // Maintain same height as days view
        }
        .frame(height: calendarGridHeight)
        .transition(.asymmetric(
            // Always comes from months view (moving up)
            insertion: .move(edge: .bottom).combined(with: .opacity),
            // Always goes back to months view (moving down)
            removal: .move(edge: .top).combined(with: .opacity)
        ))
    }
    
    // Helper to check if month is the current displayed month
    private func isCurrentMonth(_ month: Int) -> Bool {
        let calendar = Calendar.current
        return calendar.component(.month, from: currentMonth) == month
    }
    
    // Action when a month is selected - going from months -> days (moving down in time scale)
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
        withAnimation(.easeInOut(duration: 0.4)) {
            // When going from months -> days (moving down in time scale)
            slideDirection = .none // Reset slide direction to trigger vertical transition
            isMovingUpInTimeScale = false // We're moving down in time scale
            calendarViewMode = .days
        }
    }
    
    // Update the action when a year is selected
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
        
        // Go back to months view with animation
        withAnimation(.easeInOut(duration: 0.4)) {
            isMovingUpInTimeScale = false // We're moving down in time scale
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

// Add a new modifier to handle both transitions
struct DaysTransitionModifier: ViewModifier {
    let slideDirection: SlideDirection
    
    func body(content: Content) -> some View {
        if slideDirection == .none {
            // For view mode transitions:
            // When going from days -> months (moving up): days slide down and disappear
            // When coming back from months -> days (moving down): days slide down from top
            content.transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity), // Coming from months (moving down)
                removal: .move(edge: .bottom).combined(with: .opacity) // Going to months (moving up)
            ))
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