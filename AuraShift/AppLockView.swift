import SwiftUI

struct AppLockView: View {
    let authTypeTitle: String
    let isAuthenticating: Bool
    let errorText: String?
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            VisionBackdropView()

            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        // STYLE: Градиентный бейдж замка.
                        .fill(AppColors.accentGradient)
                        // STYLE: Размер центральной икон-плашки.
                        .frame(width: 86, height: 86)
                        // STYLE: Мягкая тень для отделения плашки от фона.
                        .shadow(color: AppColors.accent.opacity(0.28), radius: 10, x: 0, y: 6)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.white)
                }

                Text(NSLocalizedString("Приложение заблокировано", comment: "app lock title"))
                    // STYLE: Крупный заголовок экрана блокировки.
                    .font(.system(size: 21, weight: .bold))
                    .foregroundColor(AppColors.text)

                Text(String(format: NSLocalizedString("Разблокируйте через %@ или код устройства.", comment: "app lock subtitle with auth type"), authTypeTitle))
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)

                if let errorText, !errorText.isEmpty {
                    Text(errorText)
                        .font(.caption)
                        .foregroundColor(AppColors.negative)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                Button(action: onUnlock) {
                    HStack(spacing: 8) {
                        if isAuthenticating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "faceid")
                        }
                        Text(isAuthenticating ? NSLocalizedString("Проверка...", comment: "app lock authenticating status") : NSLocalizedString("Разблокировать", comment: "app lock unlock button"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                }
                .buttonStyle(VisionPrimaryButtonStyle())
                .disabled(isAuthenticating)
                .padding(.horizontal, 24)
                .padding(.top, 6)
            }
            // STYLE: Стеклянная карточка контента экрана блокировки.
            .padding(22)
            .visionGlassCard(cornerRadius: 20, opacity: 0.86, showRing: true)
            .padding(.horizontal, 24)
        }
    }
}
