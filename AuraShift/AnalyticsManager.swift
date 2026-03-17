import Foundation

final class AnalyticsManager {
    static let shared = AnalyticsManager()

    private let key = "anonymousAnalyticsEnabled"
    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? false
    }

    private init() {}

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key)
    }

    func track(_ event: String, metadata: [String: String] = [:]) {
        guard isEnabled else { return }
        let payload = metadata.map { "\($0)=\($1)" }.joined(separator: ", ")
        if payload.isEmpty {
            print("📈 Analytics: \(event)")
        } else {
            print("📈 Analytics: \(event) | \(payload)")
        }
    }
}
