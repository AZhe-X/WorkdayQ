//
//  Item.swift
//  WorkdayQ
//
//  Created by Xueqi Li on 3/3/25.
//

import Foundation
import SwiftData

@Model
final class WorkDay {
    var date: Date
    var isWorkDay: Bool
    var note: String?
    
    init(date: Date, isWorkDay: Bool = false, note: String? = nil) {
        self.date = date
        self.isWorkDay = isWorkDay
        self.note = note
    }
}
