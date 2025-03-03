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
    
    // Fixed sizes to prevent layout shifts
    private let calendarGridHeight: CGFloat = 300
    private let dayHeight: CGFloat = 42 // Fixed height for each day
    private let rowSpacing: CGFloat = 8 // Fixed spacing between rows
    
    enum SlideDirection {
        case none, left, right
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            monthHeader
            
            dayOfWeekHeader
            
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
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.3), value: currentMonth)
    }
    
    private var monthHeader: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            Text(currentMonth, format: .dateTime.month().year())
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.primary)
            }
        }
        .padding(.vertical)
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