# WorkdayQ

WorkdayQ is an iOS app that helps you track your work days and off days. It provides a simple, intuitive interface to manage your work schedule and includes iOS widgets for quick access to your status.

## Features

### Main App
- **Today's Status Card**: Shows the current date and whether today is a workday or an off day
- **Calendar View**: Displays the entire month with color-coded days (red for workdays, green for off days)
- **Date Status Management**: Tap any day to select it, then use the buttons below to set it as a workday or off day
- **Notes**: Add notes to specific days for reminders or important information

### Widgets
1. **Today Widget** (Small): Shows today's date and work status
2. **Weekly Widget** (Medium): Shows today, tomorrow, and the next 5 days with their work status

## How WorkdayQ Determines Work Days

WorkdayQ uses a three-tiered system to determine whether a day is a work day or an off day:

1. **User-Edited Data** (Highest Priority)
   - Stored in SwiftData as explicit `WorkDay` records
   - Options: not set (no record exists), workday (isWorkDay = true), or off day (isWorkDay = false)
   - Created when a user manually sets a day's status or adds a note
   - Always takes precedence over holiday data and default rules

2. **Holiday Data** (Medium Priority)
   - Managed by `HolidayManager` and stored in UserDefaults
   - Downloaded from calendar services based on user preference (Chinese Holidays or US Federal Holidays)
   - Options: not set (nil), workday (true), or off day (false)
   - Includes both regular holidays (off days) and special work days (e.g., "makeup" work days for extended holidays)
   - Only used if no user-edited record exists for a date

3. **Default Rules** (Lowest Priority)
   - Calculated on demand using the `isDefaultWorkDay()` function
   - Not stored as data but determined by calendar logic
   - Monday-Friday are considered work days, Saturday-Sunday are off days
   - Only applied when neither user-edited data nor holiday data exists for a date

This tiered approach ensures that user preferences always take precedence, while still providing helpful defaults and holiday awareness.

## Technical Details

The app is built using:
- SwiftUI for the user interface
- SwiftData for data persistence
- WidgetKit for home screen widgets
- App Groups for data sharing between the app and widgets

## Setup

To customize the app for your own bundle identifier:

1. Open the project in Xcode
2. Update the App Group identifier in both the main app and widget extension:
   - In `WorkdayQApp.swift` and `WorkdayQWidget.swift`, update the line: 
     ```swift
     forSecurityApplicationGroupIdentifier: "group.com.yourcompany.WorkdayQ"
     ```
   - Also update the App Group identifier in the entitlements files

## Building and Running

1. Open `WorkdayQ.xcodeproj` in Xcode
2. Select your target device
3. Build and run the app (⌘R)
4. To test the widgets, run the widget extension target and add the widgets to your home screen

## Customization

- **Colors**: You can modify the workday/off day colors by editing the color values in the relevant views
- **UI**: The app uses native iOS UI components for a familiar and consistent user experience 