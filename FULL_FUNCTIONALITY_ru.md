//
//  AuraShiftLoadingView.swift
//  AuraShift
//
//  Created by Developer on 2024-04-27.
//

import SwiftUI

struct AuraShiftLoadingView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color.accentColor))
                    .scaleEffect(1.5)
                
                Text("AuraShift")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(Color.primary)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
            )
        }
    }
}

struct AuraShiftLoadingView_Previews: PreviewProvider {
    static var previews: some View {
        AuraShiftLoadingView()
            .preferredColorScheme(.light)
        
        AuraShiftLoadingView()
            .preferredColorScheme(.dark)
    }
}
