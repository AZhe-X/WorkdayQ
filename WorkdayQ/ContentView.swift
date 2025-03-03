//
//  ContentView.swift
//  WorkdayQ
//
//  Created by Xueqi Li on 3/3/25.
//

import SwiftUI
import SwiftData
import WidgetKit

// Constants for app group synchronization
let appGroupID = "group.io.azhe.WorkdayQ"
let lastUpdateKey = "lastDatabaseUpdate"

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
                
                // Custom Calendar with callbacks
                CustomCalendarView(
                    selectedDate: $selectedDate,
                    workDays: workDays,
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
                        Label("Tap a day to toggle work/off status", systemImage: "hand.tap")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Label("Long-press to add or edit notes", systemImage: "hand.tap.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("WorkdayQ")
            .sheet(isPresented: $showingNoteEditor) {
                noteEditorView
            }
            .onAppear {
                checkAndCreateTodayEntry()
                // Always reload widget when view appears
                reloadWidgets()
            }
            .onChange(of: workDays) { _, _ in
                // Reload widgets when workdays change 
                reloadWidgets()
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
                let isWorkDay = todayWorkDay?.isWorkDay ?? false
                Text(isWorkDay ? "Workday" : "Off day")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(isWorkDay ? .red : .green)
                
                Spacer()
                
                Circle()
                    .fill(isWorkDay ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                    .frame(width: 30, height: 30)
            }
            
            if let note = todayWorkDay?.note, !note.isEmpty {
                Text(note)
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
            
            // Save data and notify widget
            try? modelContext.save()
            notifyWidgetDataChanged()
        }
    }
    
    private func toggleWorkStatus(for date: Date) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        
        if let existingDay = workDays.first(where: { calendar.isDate($0.date, inSameDayAs: dayStart) }) {
            existingDay.isWorkDay.toggle()
        } else {
            let newWorkDay = WorkDay(date: dayStart, isWorkDay: true)
            modelContext.insert(newWorkDay)
        }
        
        // Save data and notify widget
        try? modelContext.save()
        notifyWidgetDataChanged()
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
        
        // Save data and notify widget
        try? modelContext.save()
        notifyWidgetDataChanged()
    }
    
    // Force reload of all widgets
    private func reloadWidgets() {
        print("Reloading all widget timelines")
        WidgetCenter.shared.reloadAllTimelines()
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
}

#Preview {
    ContentView()
        .modelContainer(for: WorkDay.self, inMemory: true)
}

