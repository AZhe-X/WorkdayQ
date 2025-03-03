//
//  Item.swift
//  WorkdayQ
//
//  Created by Xueqi Li on 3/3/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
