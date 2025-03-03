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
    var body: some Widget {
        TodayStatusWidget()
        WeekOverviewWidget()
    }
}
