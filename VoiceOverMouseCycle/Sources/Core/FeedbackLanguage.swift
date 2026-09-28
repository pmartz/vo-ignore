import Foundation

struct FeedbackPhrases: Decodable, Sendable {
    let name: String
    let ignore: String
    let mouseFollowsVoiceOver: String
    let voiceOverFollowsMouse: String
}

enum FeedbackTranslations {
    // A missing or damaged resource must not break tracking. The shipping bundle
    // and all three strings for every locale are checked separately in tests.
    static let emergencyEnglish = FeedbackPhrases(name: "English", ignore: "No tracking",
        mouseFollowsVoiceOver: "Mouse follows VoiceOver", voiceOverFollowsMouse: "VoiceOver follows mouse")
    static let catalog: [String: FeedbackPhrases] = BundledCatalog.load("FeedbackTranslations", fallback: emergencyEnglish)
}

struct FeedbackLanguage: RawRepresentable, Equatable, Sendable {
    let rawValue: String
    init?(rawValue: String) {
        guard FeedbackTranslations.catalog[rawValue] != nil else { return nil }
        self.rawValue = rawValue
    }
    private init(known: String) { rawValue = known }
    static let chinese = Self(known: "zh-Hans")
    static let traditionalChinese = Self(known: "zh-Hant")
    static let english = Self(known: "en")

    var phrases: FeedbackPhrases { FeedbackTranslations.catalog[rawValue] ?? FeedbackTranslations.emergencyEnglish }

    static func primaryLanguageCode(_ tag: String?) -> String? {
        guard let base = components(tag).first,
              (2...3).contains(base.count), base.utf8.allSatisfy({ (97...122).contains($0) }) else { return nil }
        return base
    }

    private static func components(_ tag: String?) -> [String] {
        (tag ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-").lowercased()
            .split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    }

    static func forLanguageTag(_ tag: String?) -> FeedbackLanguage? {
        guard var base = primaryLanguageCode(tag) else { return nil }
        let parts = components(tag)
        if base == "cmn" { base = "zh" }
        if base == "wuu" { return Self(rawValue: "zh-Hans") } // Written Chinese for Shanghainese voices.
        if base == "zh" {
            if parts.contains("yue") { return Self(rawValue: "yue") }
            if parts.contains("hans") { return Self(rawValue: "zh-Hans") }
            if parts.contains("hant") { return Self(rawValue: "zh-Hant") }
            if parts.contains("hk") || parts.contains("mo") { return Self(rawValue: "yue") }
            return Self(rawValue: parts.contains("tw") ? "zh-Hant" : "zh-Hans")
        }
        if base == "pt" { return Self(rawValue: parts.contains("br") ? "pt-BR" : "pt-PT") }
        if base == "no" { base = "nb" }
        if base == "iw" { base = "he" }
        if base == "in" { base = "id" }
        // Only Gurmukhi Punjabi has a translation; do not feed that script to a
        // Shahmukhi/Arabic voice and pretend it is the same localization.
        if base == "pa", parts.contains("arab") || (parts.contains("pk") && !parts.contains("guru")) { return nil }
        return Self(rawValue: base)
    }

    // System language is intentional. Never initialize ScreenReader speech
    // settings or enumerate speech voices just to choose feedback text.
    static func resolve(systemLanguages: [String] = Locale.preferredLanguages) -> Self {
        systemLanguages.lazy.compactMap(forLanguageTag).first ?? .english
    }
}
