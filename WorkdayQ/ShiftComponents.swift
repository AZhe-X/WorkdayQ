//
//  ShiftComponents.swift
//  WorkdayQ
//
//  Components related to partial day shift visualization
//

import SwiftUI

/// Displays a circle with segments representing different shifts in a day
public struct ShiftCircle: View {
    let shifts: [Int]?
    let numberOfShifts: Int
    let size: CGFloat
    let baseOpacity: Double
    
    public var body: some View {
        ZStack {
            // Base circle - green for rest days (empty shifts), light red background otherwise
            Circle()
                .fill(shifts?.isEmpty ?? true ? Color.green.opacity(0.8) : Color.red.opacity(0.4))
                .frame(width: size, height: size)
            
            // Only show shift segments if there are shifts
            if let shifts = shifts, !shifts.isEmpty {
                // Parallel division view with rotation
                ParallelDividedCircle(
                    shifts: shifts,
                    numberOfShifts: numberOfShifts,
                    size: size,
                    baseOpacity: baseOpacity
                )
                .rotationEffect(Angle(degrees: -30)) // Rotate the entire segment display
            }
        }
    }
}

/// Handles the division of circle into parallel segments based on shift count
struct ParallelDividedCircle: View {
    let shifts: [Int]?
    let numberOfShifts: Int
    let size: CGFloat
    let baseOpacity: Double
    
    // Get the valid shift numbers based on numberOfShifts
    var validShiftNumbers: [Int] {
        switch numberOfShifts {
        case 2:
            return [2, 4]          // morning and night
        case 3:
            return [2, 3, 4]       // morning, noon, night
        case 4:
            return [1, 2, 3, 4]    // early morning, morning, noon, night
        default:
            return [2, 4]          // default to 2-shift
        }
    }
    
    var body: some View {
        ZStack {
            // Create each slice based on active shifts
            ForEach(0..<validShiftNumbers.count, id: \.self) { index in
                let shiftNumber = validShiftNumbers[index]
                let isActive = shifts?.contains(shiftNumber) ?? false
                
                ParallelSlice(
                    sliceNumber: index,
                    totalSlices: validShiftNumbers.count,
                    isActive: isActive
                )
                .fill(isActive ? Color.red.opacity(baseOpacity) : Color.clear)
                .frame(width: size, height: size)
            }
            
            // Add divider lines between segments
            ForEach(1..<validShiftNumbers.count, id: \.self) { index in
                // Calculate Y position for each divider
                let yOffset = (size / CGFloat(validShiftNumbers.count)) * CGFloat(index) - (size / 2)
                
                // Draw a horizontal line across the circle
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: size, height: 1.5)
                    .offset(y: yOffset)
            }
        }
    }
}

/// Individual slice shape for a segment of the shift circle
struct ParallelSlice: Shape {
    let sliceNumber: Int
    let totalSlices: Int
    let isActive: Bool
    
    func path(in rect: CGRect) -> Path {
        let diameter = min(rect.width, rect.height)
        let radius = diameter / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        
        // Calculate spacing between horizontal segments
        let sliceHeight = diameter / CGFloat(totalSlices)
        
        // Calculate the top position for this slice
        let topY = center.y - radius + (sliceHeight * CGFloat(sliceNumber))
        let bottomY = topY + sliceHeight
        
        // Create path for this slice
        var path = Path()
        
        // Create a horizontal slice across the circle
        let leftX = center.x - radius
        let rightX = center.x + radius
        
        path.move(to: CGPoint(x: leftX, y: topY))
        path.addLine(to: CGPoint(x: rightX, y: topY))
        path.addLine(to: CGPoint(x: rightX, y: bottomY))
        path.addLine(to: CGPoint(x: leftX, y: bottomY))
        path.closeSubpath()
        
        // Intersect with circle
        let circlePath = Path(ellipseIn: rect)
        return path.intersection(circlePath)
    }
}

/// Displays a rounded rectangle with segments representing different shifts in a day
public struct ShiftRectangle: View {
    let shifts: [Int]?
    let numberOfShifts: Int
    let width: CGFloat
    let height: CGFloat
    let baseOpacity: Double
    // Add callback for handling tap events
    var onShiftToggle: ((Int) -> Void)?
    // Add customizable corner radius
    var cornerRadius: CGFloat = 15
    
    public var body: some View {
        ZStack {
            // Create a container with proper corner radius
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                .frame(width: width, height: height)
            
            // Modified approach to maintain consistent outer shape
            VStack(spacing: 1) {
                ForEach(0..<validShiftNumbers.count, id: \.self) { index in
                    let isFirst = index == 0
                    let isLast = index == validShiftNumbers.count - 1
                    let shiftNumber = validShiftNumbers[index]
                    let isActive = shifts?.contains(shiftNumber) ?? false
                    
                    // Make each segment a button
                    Button {
                        // Call the callback with the shift number when tapped
                        onShiftToggle?(shiftNumber)
                    } label: {
                        // Create a segment with appropriate corner radius
                        if isFirst {
                            // Top segment - round top corners only
                            RoundedCorners(tl: cornerRadius, tr: cornerRadius, bl: 0, br: 0)
                                .fill(isActive ? Color.red.opacity(baseOpacity) : Color.red.opacity(0.1))
                                .frame(height: segmentHeight)
                        } else if isLast {
                            // Bottom segment - round bottom corners only
                            RoundedCorners(tl: 0, tr: 0, bl: cornerRadius, br: cornerRadius)
                                .fill(isActive ? Color.red.opacity(baseOpacity) : Color.red.opacity(0.1))
                                .frame(height: segmentHeight)
                        } else {
                            // Middle segments - no rounded corners
                            Rectangle()
                                .fill(isActive ? Color.red.opacity(baseOpacity) : Color.red.opacity(0.1))
                                .frame(height: segmentHeight)
                        }
                    }
                    .buttonStyle(PlainButtonStyle()) // Remove default button styling
                }
            }
            .frame(width: width - 2, height: height - 2) // Leave room for border
        }
    }
    
    // Get the valid shift numbers based on numberOfShifts
    var validShiftNumbers: [Int] {
        switch numberOfShifts {
        case 2: return [2, 4]          // morning and night
        case 3: return [2, 3, 4]       // morning, noon, night
        case 4: return [1, 2, 3, 4]    // early morning, morning, noon, night
        default: return [2, 4]         // default to 2-shift
        }
    }
    
    // Calculate segment height
    private var segmentHeight: CGFloat {
        (height - CGFloat(validShiftNumbers.count - 1)) / CGFloat(validShiftNumbers.count)
    }
}

// Custom shape for precise corner rounding control
struct RoundedCorners: Shape {
    var tl: CGFloat = 0.0
    var tr: CGFloat = 0.0
    var bl: CGFloat = 0.0
    var br: CGFloat = 0.0
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let w = rect.size.width
        let h = rect.size.height
        
        // Make sure we don't exceed the size of the rect
        let tr = min(min(self.tr, h/2), w/2)
        let tl = min(min(self.tl, h/2), w/2)
        let bl = min(min(self.bl, h/2), w/2)
        let br = min(min(self.br, h/2), w/2)
        
        path.move(to: CGPoint(x: w / 2.0, y: 0))
        path.addLine(to: CGPoint(x: w - tr, y: 0))
        path.addArc(center: CGPoint(x: w - tr, y: tr), radius: tr, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        path.addLine(to: CGPoint(x: w, y: h - br))
        path.addArc(center: CGPoint(x: w - br, y: h - br), radius: br, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        path.addLine(to: CGPoint(x: bl, y: h))
        path.addArc(center: CGPoint(x: bl, y: h - bl), radius: bl, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        path.addLine(to: CGPoint(x: 0, y: tl))
        path.addArc(center: CGPoint(x: tl, y: tl), radius: tl, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        path.closeSubpath()
        
        return path
    }
}

// Helper view for the segments - now using vertical layout
struct ShiftSegmentsView: View {
    let shifts: [Int]?
    let validShiftNumbers: [Int]
    let width: CGFloat
    let height: CGFloat
    let baseOpacity: Double
    
    var body: some View {
        VStack(spacing: 1) { // Changed from HStack to VStack
            ForEach(0..<validShiftNumbers.count, id: \.self) { index in
                // Reverse the index to show early morning/morning at top
                let reverseIndex = validShiftNumbers.count - 1 - index
                ShiftSegment(
                    index: reverseIndex, 
                    totalSegments: validShiftNumbers.count,
                    isActive: shifts?.contains(validShiftNumbers[reverseIndex]) ?? false,
                    width: width, // Now using full width
                    height: segmentHeight, // Using calculated segment height
                    baseOpacity: baseOpacity
                )
            }
        }
        .frame(width: width, height: height)
    }
    
    // Calculate segment height instead of width
    private var segmentHeight: CGFloat {
        (height - CGFloat(validShiftNumbers.count - 1)) / CGFloat(validShiftNumbers.count)
    }
}

// Individual segment - now handling top/bottom corners
struct ShiftSegment: View {
    let index: Int
    let totalSegments: Int
    let isActive: Bool
    let width: CGFloat
    let height: CGFloat
    let baseOpacity: Double
    var cornerRadius: CGFloat = 8
    
    var body: some View {
        // First create the base shape with fill
        RoundedRectangle(cornerRadius: 0)
            .fill(isActive ? Color.red.opacity(baseOpacity) : Color.red.opacity(0.1))
            // Then apply corner radius to top/bottom corners
            .cornerRadius(index == 0 ? cornerRadius : 0, corners: [.topLeft, .topRight])
            .cornerRadius(index == totalSegments - 1 ? cornerRadius : 0, corners: [.bottomLeft, .bottomRight])
            .frame(width: width, height: height)
    }
}

// Divider lines view - fixed implementation with proper line count
struct DividerLinesView: View {
    let segmentCount: Int
    let width: CGFloat
    let height: CGFloat
    
    var body: some View {
        ZStack {
            // Only create segmentCount - 1 dividers
            ForEach(0..<(segmentCount - 1), id: \.self) { index in
                // Calculate position for each divider
                let yPosition = (CGFloat(index + 1) * segmentHeight) + (CGFloat(index) * 1)
                
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: width, height: 1)
                    .position(x: width/2, y: yPosition)
            }
        }
        .frame(width: width, height: height)
    }
    
    // Calculate segment height
    private var segmentHeight: CGFloat {
        (height - CGFloat(segmentCount - 1)) / CGFloat(segmentCount)
    }
}

// Extension to apply corner radius to specific corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

// Custom shape for applying corner radius to specific corners
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
} 