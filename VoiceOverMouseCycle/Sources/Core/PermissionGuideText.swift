import Foundation

struct PermissionGuideText: Decodable, Sendable {
    let title: String
    let message: String
    let settings: String
    let cancel: String

    static let english = Self(title: "Full Disk Access required",
        message: "Enable VoiceOverMouseCycle in System Settings → Privacy & Security → Full Disk Access. If missing, click plus and add VoiceOverMouseCycle.app from Applications. Then run this app again. The mode has not changed.",
        settings: "Open System Settings", cancel: "Cancel")
}

struct PermissionGuideLanguage: Sendable {
    let language: String
    let text: PermissionGuideText

    static let catalog: [String: PermissionGuideText] = BundledCatalog.load("PermissionGuideTranslations", fallback: .english)

    /// Uses system preferred languages only. Does not read VoiceOver settings.
    static func resolve(preferredLanguages: [String] = Locale.preferredLanguages) -> Self {
        for tag in preferredLanguages {
            if let locale = FeedbackLanguage.forLanguageTag(tag)?.rawValue, let text = catalog[locale] {
                return Self(language: locale, text: text)
            }
        }
        return Self(language: "en", text: catalog["en"] ?? .english)
    }
}
