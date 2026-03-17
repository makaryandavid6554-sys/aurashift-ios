# AuraShift

AuraShift is a SwiftUI iOS app for tracking personal finances with a focus on shift-based income. The project combines daily income and expense logging, financial goals, export tools, widgets, and an AI-assisted analytics layer in a single app.

## What It Does

- Tracks shift income, tips, floating income, and daily expenses
- Stores data locally with Core Data
- Shows statistics and charts for income, expenses, and goal progress
- Provides AI-style forecasts, trends, and planning assistance
- Supports financial goals with progress tracking and reminders
- Exports reports to CSV and XLSX
- Includes Home Screen widgets, quick actions, and Siri/App Intents integrations
- Supports app lock with Face ID / Touch ID / device passcode
- Localizes the UI into multiple languages

## Stack

- Swift
- SwiftUI
- Core Data
- WidgetKit
- App Intents
- Charts
- UserNotifications
- CoreLocation
- LocalAuthentication

## Project Highlights

- Multi-tab SwiftUI architecture with dedicated screens for daily tracking, statistics, AI insights, goals, and settings
- Custom export pipeline for spreadsheet generation without external dependencies
- Widget and Live Activity support for lightweight glanceable progress
- Configurable appearance, reminders, analytics options, and app security
- Public-ready setup with personal Xcode user data ignored by Git

## Project Structure

```text
AuraShift/                 Main iOS application source
AuraShiftWidget/           Widget extension
Config/                    App and widget plist files
docs/                      Supporting images and notes
scripts/                   Local build/deploy helpers
AuraShift.xcodeproj/       Xcode project
```

## Run Locally

1. Open `AuraShift.xcodeproj` in Xcode.
2. Select the `AuraShift` scheme.
3. If you want to run on a physical device, choose your own Apple Development team in Signing & Capabilities.
4. Build and run on iOS 17.6 or later.

## Notes

- iCloud / CloudKit sync is intentionally disabled in the current public build configuration.
- Some advanced features are gated by in-app Pro logic already present in the codebase.
- Control Widget APIs are conditionally implemented for newer iOS versions.

## Why This Repo Exists

This repository is used as a portfolio project to demonstrate practical iOS engineering across UI, local persistence, widgets, export features, app security, localization, and product-oriented architecture.
