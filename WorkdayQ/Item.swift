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
    @Attribute(.unique) var date: Date
    // Replace boolean with Integer status
    // 0 = Not modified (follow pattern)
    // 1 = User-set rest day
    // 2 = User-set work day
    var dayStatus: Int
    var note: String?
    
    // For backward compatibility
    var isWorkDay: Bool {
        get {
            return dayStatus == 2
        }
        set {
            dayStatus = newValue ? 2 : 1
        }
    }
    
    init(date: Date, dayStatus: Int = 0, note: String? = nil) {
        self.date = date
        self.dayStatus = dayStatus
        self.note = note
    }
    
    // Legacy initializer for backward compatibility
    convenience init(date: Date, isWorkDay: Bool, note: String? = nil) {
        self.init(date: date, dayStatus: isWorkDay ? 2 : 1, note: note)
    }
}
