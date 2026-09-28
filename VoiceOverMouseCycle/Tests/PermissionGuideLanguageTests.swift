import XCTest
@testable import TrackingCore

final class PermissionGuideLanguageTests: XCTestCase {
    func testShippingGuideCoversEveryFeedbackLanguage() {
        XCTAssertEqual(PermissionGuideLanguage.catalog.count, 59)
        XCTAssertEqual(Set(PermissionGuideLanguage.catalog.keys), Set(FeedbackTranslations.catalog.keys))
        for (locale, copy) in PermissionGuideLanguage.catalog {
            for text in [copy.title, copy.message, copy.settings, copy.cancel] {
                XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, locale)
            }
            XCTAssertTrue(copy.message.contains("VoiceOverMouseCycle.app"), locale)
        }
    }

    func testSystemLanguageOrderAndRegionalFallbacks() {
        let cases: [([String], String)] = [
            (["fr-CA", "zh-Hans-CN"], "fr"), (["zh-Hant-TW", "en"], "zh-Hant"),
            (["zh-CN"], "zh-Hans"), (["en-GB", "zh-Hans"], "en"),
            (["pt-BR"], "pt-BR"), (["pt-PT"], "pt-PT"), (["ar-SA"], "ar"),
            (["zz-ZZ", "de-DE"], "de"), (["zz-ZZ"], "en"), ([], "en")
        ]
        for (preferred, expected) in cases {
            XCTAssertEqual(PermissionGuideLanguage.resolve(preferredLanguages: preferred).language, expected)
        }
    }
}
