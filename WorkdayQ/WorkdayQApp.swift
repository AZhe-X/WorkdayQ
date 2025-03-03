//
//  WorkdayQApp.swift
//  WorkdayQ
//
//  Created by Xueqi Li on 3/3/25.
//

import SwiftUI
import SwiftData
import WidgetKit

@main
struct WorkdayQApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            WorkDay.self,
        ])
        
        // Use App Group container for shared access with widget
        let modelConfiguration = ModelConfiguration(
            schema: schema, 
            isStoredInMemoryOnly: false,
            groupContainer: .identifier("group.io.azhe.WorkdayQ")
        )
        
        // Set migration options through the model configuration
        // In SwiftData, not specifying migration options defaults to preventing schema migrations
        
        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            
            // Update an app group UserDefault to signal database is ready
            if let sharedDefaults = UserDefaults(suiteName: "group.io.azhe.WorkdayQ") {
                sharedDefaults.set(Date().timeIntervalSince1970, forKey: "lastDatabaseUpdate")
                print("App updated database timestamp in UserDefaults")
            }
            
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
