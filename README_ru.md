import SwiftUI

struct AuraShiftLoadingView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                Text("AuraShift")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color(.secondarySystemBackground).opacity(0.72))
                    .shadow(radius: 10)
            )
            .padding()
        }
    }
}

#Preview {
    AuraShiftLoadingView()
}
