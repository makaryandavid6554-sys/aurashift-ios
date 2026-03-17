import AudioToolbox
import Foundation

final class SoundManager {
    static let shared = SoundManager()

    enum Event {
        case tap
        case success
        case error

        var systemSoundID: SystemSoundID {
            switch self {
            case .tap:
                return 1104
            case .success:
                return 1519
            case .error:
                return 1521
            }
        }
    }

    private init() {}

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: "soundsEnabled") as? Bool ?? true
    }

    func play(_ event: Event) {
        guard enabled else { return }
        AudioServicesPlaySystemSound(event.systemSoundID)
    }
}
