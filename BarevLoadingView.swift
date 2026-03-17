// AuraShiftLoadingView.swift
// Simple loading window with 'Barev' text.

import SwiftUI

struct AuraShiftLoadingView: View {
    var body: some View {
        ZStack {
            // Optional: background color
            Color(.systemBackground)
                .ignoresSafeArea()
                .opacity(0.95)
            VStack(spacing: 18) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color.accentColor))
                    .scaleEffect(1.5)
                Text("AuraShift")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color(.secondarySystemBackground).opacity(0.72))
            )
            .shadow(radius: 10)
        }
    }
}

#Preview {
    AuraShiftLoadingView()
}
