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
    // 0 = Not modified (follow pattern)
    // 1 = User-set rest day
    // 2 = User-set full work day
    // 3 = User-set partial day (with specific shifts assigned)
    var dayStatus: Int
    var note: String?
    
    // Shift information - array contains shift IDs (1-4) that are active for this day
    // The global numberOfShifts setting determines which values are valid:
    // - For 2-shift system: only values 2 and 4 are used (morning and night)
    // - For 3-shift system: values 2, 3, and 4 are used (morning, noon, night)
    // - For 4-shift system: all values 1-4 are used (early morning, morning, noon, night)
    //
    // 1 = early morning shift
    // 2 = morning shift
    // 3 = noon shift
    // 4 = night shift
    var shifts: [Int]?
    
    // For backward compatibility
    var isWorkDay: Bool {
        get {
            return dayStatus == 2 || dayStatus == 3
        }
        set {
            dayStatus = newValue ? 2 : 1
        }
    }
    
    init(date: Date, dayStatus: Int = 0, note: String? = nil, shifts: [Int]? = nil) {
        self.date = date
        self.dayStatus = dayStatus
        self.note = note
        self.shifts = shifts
    }
    
    // Legacy initializer for backward compatibility
    convenience init(date: Date, isWorkDay: Bool, note: String? = nil) {
        self.init(date: date, dayStatus: isWorkDay ? 2 : 1, note: note)
    }
}
