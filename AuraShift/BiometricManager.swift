import Foundation
import LocalAuthentication

final class BiometricManager {
    static let shared = BiometricManager()
    private init() {}

    enum AuthType {
        case faceID
        case touchID
        case passcode
        case unavailable

        var localizedTitle: String {
            switch self {
            case .faceID:
                return "Face ID"
            case .touchID:
                return "Touch ID"
            case .passcode:
                return NSLocalizedString("Код устройства", comment: "biometric auth type: passcode")
            case .unavailable:
                return NSLocalizedString("Недоступно", comment: "biometric auth type: unavailable")
            }
        }
    }

    func authType() -> AuthType {
        let context = LAContext()
        var error: NSError?
        let canAuth = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        guard canAuth else { return .unavailable }
        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        default:
            return .passcode
        }
    }

    func canAuthenticate() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func authenticate(
        reason: String = NSLocalizedString("Разблокируйте приложение AuraShift", comment: "biometric prompt reason"),
        completion: @escaping (Bool, String?) -> Void
    ) {
        let context = LAContext()
        context.localizedCancelTitle = NSLocalizedString("Отмена", comment: "biometric cancel button")

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(false, error?.localizedDescription ?? NSLocalizedString("Биометрия недоступна", comment: "biometric unavailable fallback"))
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authError in
            DispatchQueue.main.async {
                completion(success, authError?.localizedDescription)
            }
        }
    }
}
