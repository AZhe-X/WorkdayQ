//
//  ContentView.swift
//  WorkdayQ
//
//  Created by Xueqi Li on 3/3/25.
//

import SwiftUI
import SwiftData
import WidgetKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var workDays: [WorkDay]
    
    @State private var selectedDate: Date = Date()
    @State private var showingNoteEditor = false
    @State private var noteText = ""
    
    var todayWorkDay: WorkDay? {
        let calendar = Calendar.current
        return workDays.first { calendar.isDate($0.date, inSameDayAs: Date()) }
    }
    
    var selectedWorkDay: WorkDay? {
        let calendar = Calendar.current
        return workDays.first { calendar.isDate($0.date, inSameDayAs: selectedDate) }
    }
    
    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Today's Status Card
                todayStatusCard
                
                // Custom Calendar
                CustomCalendarView(selectedDate: $selectedDate, workDays: workDays)
                
                // Controls for selected date
                dateControlsView
                
                Spacer()
            }
            .padding()
            .navigationTitle("WorkdayQ")
            .sheet(isPresented: $showingNoteEditor) {
                noteEditorView
            }
            .onAppear {
                checkAndCreateTodayEntry()
            }
        }
    }
    
    var todayStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dateFormatter.string(from: Date()))
                .font(.headline)
            
            Text("Today is:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Text(todayWorkDay?.isWorkDay == true ? "Workday" : "Off day")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(todayWorkDay?.isWorkDay == true ? .red : .green)
                
                Spacer()
                
                Circle()
                    .fill(todayWorkDay?.isWorkDay == true ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                    .frame(width: 30, height: 30)
            }
            
            if let note = todayWorkDay?.note, !note.isEmpty {
                Text("Note: \(note)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
    
    var dateControlsView: some View {
        HStack {
            Button(action: toggleSelectedDateStatus) {
                Text(selectedWorkDay?.isWorkDay == true ? "Set as Off Day" : "Set as Work Day")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(selectedWorkDay?.isWorkDay == true ? Color.green : Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            
            Button(action: {
                if let selectedDay = selectedWorkDay {
                    noteText = selectedDay.note ?? ""
                }
                showingNoteEditor = true
            }) {
                Image(systemName: "note.text")
                    .font(.headline)
                    .padding()
                    .background(Color(UIColor.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
            }
        }
    }
    
    var noteEditorView: some View {
        NavigationStack {
            VStack {
                TextField("Enter note for \(dateFormatter.string(from: selectedDate))", text: $noteText, axis: .vertical)
                    .padding()
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(5...10)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Date Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingNoteEditor = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveNote()
                        showingNoteEditor = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private func checkAndCreateTodayEntry() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        if !workDays.contains(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            let newWorkDay = WorkDay(date: today)
            modelContext.insert(newWorkDay)
            
            // Request widget to refresh
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    private func toggleSelectedDateStatus() {
        let calendar = Calendar.current
        let selectedDayStart = calendar.startOfDay(for: selectedDate)
        
        if let existingDay = workDays.first(where: { calendar.isDate($0.date, inSameDayAs: selectedDayStart) }) {
            existingDay.isWorkDay.toggle()
        } else {
            let newWorkDay = WorkDay(date: selectedDayStart, isWorkDay: true)
            modelContext.insert(newWorkDay)
        }
        
        // Request widget to refresh
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func saveNote() {
        let calendar = Calendar.current
        let selectedDayStart = calendar.startOfDay(for: selectedDate)
        
        if let existingDay = workDays.first(where: { calendar.isDate($0.date, inSameDayAs: selectedDayStart) }) {
            existingDay.note = noteText.isEmpty ? nil : noteText
        } else {
            let newWorkDay = WorkDay(date: selectedDayStart, note: noteText.isEmpty ? nil : noteText)
            modelContext.insert(newWorkDay)
        }
        
        // Request widget to refresh
        WidgetCenter.shared.reloadAllTimelines()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: WorkDay.self, inMemory: true)
}

