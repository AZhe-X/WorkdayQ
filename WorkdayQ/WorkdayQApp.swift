//
//  WorkdayQApp.swift
//  WorkdayQ
//
//  Created by Xueqi Li on 3/3/25.
//

import SwiftUI
import SwiftData

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

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
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
