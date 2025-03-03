//
//  CustomCalendarView.swift
//  WorkdayQ
//

import SwiftUI

struct CustomCalendarView: View {
    @Binding var selectedDate: Date
    let workDays: [WorkDay]
    
    @State private var currentMonth = Date()
    
    var body: some View {
        VStack {
            monthHeader
            
            dayOfWeekHeader
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                ForEach(daysInMonth(), id: \.self) { date in
                    if date.monthInt != currentMonth.monthInt {
                        // Days from other months
                        Text("")
                            .frame(maxWidth: .infinity)
                    } else {
                        // Days from current month
                        dayView(for: date)
                    }
                }
            }
        }
        .padding(.horizontal)
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
    }
    
    @ViewBuilder
    private func dayView(for date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let isToday = Calendar.current.isDate(date, inSameDayAs: Date())
        let dayWorkDay = getDayWorkStatus(date)
        let day = Calendar.current.component(.day, from: date)
        
        Button(action: {
            selectedDate = date
        }) {
            ZStack {
                if let isWorkDay = dayWorkDay {
                    Circle()
                        .fill(isWorkDay ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                        .aspectRatio(1, contentMode: .fit)
                }
                
                if isSelected {
                    Circle()
                        .stroke(Color.blue, lineWidth: 2)
                        .aspectRatio(1, contentMode: .fit)
                } else if isToday {
                    Circle()
                        .stroke(Color.gray, lineWidth: 1)
                        .aspectRatio(1, contentMode: .fit)
                }
                
                Text("\(day)")
                    .font(.callout)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundColor(
                        dayWorkDay != nil
                            ? .white
                            : (isToday ? .primary : .primary)
                    )
            }
        }
        .frame(height: 40)
        .padding(.vertical, 4)
    }
    
    private func getDayWorkStatus(_ date: Date) -> Bool? {
        let calendar = Calendar.current
        return workDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) })?.isWorkDay
    }
    
    private func previousMonth() {
        withAnimation {
            currentMonth = Calendar.current.date(
                byAdding: .month,
                value: -1,
                to: currentMonth
            ) ?? currentMonth
        }
    }
    
    private func nextMonth() {
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