//
//  WorkdayQWidgetBundle.swift
//  WorkdayQWidget
//
//  Created by Xueqi Li on 3/3/25.
//

import WidgetKit
import SwiftUI

@main
struct WorkdayQWidgetBundle: WidgetBundle {
    init() {
        // Initialize any resources needed for the widget
        print("WorkdayQWidgetBundle initializing...")
    }
    
    var body: some Widget {
        TodayStatusWidget()
        WeekOverviewWidget()
    }
}
