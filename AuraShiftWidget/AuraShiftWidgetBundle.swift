//
//  AuraShiftWidgetBundle.swift
//  AuraShiftWidget
//
//  Created by David Makarian on 27.02.2026.
//

import WidgetKit
import SwiftUI

@main
struct AuraShiftWidgetBundle: WidgetBundle {
    var body: some Widget {
        AuraShiftWidget()
        AuraShiftWidgetLiveActivity()
        if #available(iOS 18.0, *) {
            AuraShiftWidgetControl()
        }
    }
}
