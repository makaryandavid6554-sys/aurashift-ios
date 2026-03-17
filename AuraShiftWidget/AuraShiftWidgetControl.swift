//
//  AuraShiftWidgetControl.swift
//  AuraShiftWidget
//
//  Created by David Makarian on 27.02.2026.
//

/*
 Why @available(iOS 18.0, *)?
 ----------------------------
 We keep the project's and widget extension's Deployment Target at iOS 17.6, but Control Widgets are an iOS 18 feature (WidgetKit + AppIntents additions). 
 Marking this type and related symbols with @available(iOS 18.0, *) ensures:
 1) The code compiles with a 17.6 Deployment Target, because these symbols are excluded from older SDK/runtime.
 2) The Control Widget is only exposed on devices running iOS 18 or later.
 Combined with a `#available(iOS 18.0, *)` check in the WidgetBundle, this prevents linking/usage on iOS < 18 while keeping other widgets available on 17.6.
*/

import AppIntents
import SwiftUI
import WidgetKit

// Control Widget is an iOS 18 feature — guard it with availability while the Deployment Target stays at 17.6.
@available(iOS 18.0, *)
struct AuraShiftWidgetControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "D-D.AuraShift.AuraShiftWidget",
            provider: Provider()
        ) { value in
            ControlWidgetToggle(
                "Start Timer",
                isOn: value,
                action: StartTimerIntent()
            ) { isRunning in
                Label(isRunning ? "On" : "Off", systemImage: "timer")
            }
        }
        .displayName("Timer")
        .description("A an example control that runs a timer.")
    }
}

// Provider is also limited to iOS 18 because it belongs to the Control Widget API surface.
@available(iOS 18.0, *)
extension AuraShiftWidgetControl {
    struct Provider: ControlValueProvider {
        var previewValue: Bool {
            false
        }

        func currentValue() async throws -> Bool {
            let isRunning = true // Check if the timer is running
            return isRunning
        }
    }
}

// Intent used by the Control Widget — mark as iOS 18+ as well.
@available(iOS 18.0, *)
struct StartTimerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Start a timer"

    @Parameter(title: "Timer is running")
    var value: Bool

    func perform() async throws -> some IntentResult {
        // Start / stop the timer based on `value`.
        return .result()
    }
}
