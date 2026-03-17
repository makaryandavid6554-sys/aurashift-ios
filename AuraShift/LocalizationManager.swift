import Foundation
import ObjectiveC.runtime

final class LocalizationManager {
    static let shared = LocalizationManager()

    private init() {}

    func apply(language: AppLanguage) {
        Bundle.setAppLanguage(language.localizationCode)
    }
}

private var associatedLanguageBundleKey: UInt8 = 0

private final class LocalizedAppBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(self, &associatedLanguageBundleKey) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

private extension Bundle {
    static func setAppLanguage(_ code: String?) {
        object_setClass(Bundle.main, LocalizedAppBundle.self)

        guard let code else {
            objc_setAssociatedObject(
                Bundle.main,
                &associatedLanguageBundleKey,
                nil,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            return
        }

        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            objc_setAssociatedObject(
                Bundle.main,
                &associatedLanguageBundleKey,
                bundle,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        } else {
            objc_setAssociatedObject(
                Bundle.main,
                &associatedLanguageBundleKey,
                nil,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}
