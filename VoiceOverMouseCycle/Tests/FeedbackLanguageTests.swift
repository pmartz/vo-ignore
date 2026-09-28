import XCTest
@testable import TrackingCore

final class FeedbackLanguageTests: XCTestCase {
    func testFirstSupportedSystemLanguageWins() {
        for tag in ["en-US", "en_GB", "EN-au"] {
            let selected = FeedbackLanguage.resolve(systemLanguages: [tag, "zh-Hans-CN"])
            XCTAssertEqual(selected, .english)


        }
        for tag in ["zh-CN", "cmn-Hans"] {
            let selected = FeedbackLanguage.resolve(systemLanguages: [tag, "en-US"])
            XCTAssertEqual(selected, .chinese)
        }
    }

    func testMalformedAndUnsupportedPreferencesTryNextLanguage() {
        for tag in ["", "default", "-en", "123", "English", "brx-IN"] {
            let selected = FeedbackLanguage.resolve(systemLanguages: [tag, "zh-CN"])
            XCTAssertEqual(selected, .chinese)


        }
    }

    func testNoSupportedSystemLanguageFallsBackToEnglish() {
        for tags in [[], ["brx-IN"], ["", "default", "pa-Arab-PK"]] {
            let selected = FeedbackLanguage.resolve(systemLanguages: tags)
            XCTAssertEqual(selected, .english)


        }
    }

    func testScriptRegionsAndLegacyAliases() {
        let cases = ["zh-TW": "zh-Hant", "zh_Hant_CN": "zh-Hant", "zh-Hans-TW": "zh-Hans",
                     "zh-HK": "yue", "yue-HK": "yue", "cmn-Hant": "zh-Hant", "wuu-CN": "zh-Hans",
                     "pt-BR": "pt-BR", "pt-PT": "pt-PT", "pt-AO": "pt-PT",
                     "no-NO": "nb", "nn-NO": "nn", "iw-IL": "he", "in-ID": "id",
                     "fr-CA": "fr", "es-MX": "es", "ca-ES-valencia": "ca", "pa-Guru-IN": "pa"]
        for (tag, expected) in cases {
            XCTAssertEqual(FeedbackLanguage.forLanguageTag(tag)?.rawValue, expected, tag)
        }
        XCTAssertNil(FeedbackLanguage.forLanguageTag("pa-Arab-PK"))
        XCTAssertNil(FeedbackLanguage.forLanguageTag("pa-PK"))
    }

    func testTranslationCatalogIsCompleteAndEveryEntryIsReachable() throws {
        XCTAssertEqual(FeedbackTranslations.catalog.count, 59, "Missing or unbundled localization resource")
        for (tag, phrases) in FeedbackTranslations.catalog {
            let language = try XCTUnwrap(FeedbackLanguage.forLanguageTag(tag), tag)
            XCTAssertEqual(language.rawValue, tag)
            let texts = TrackingMode.allCases.map { $0.feedback(in: language) }
            XCTAssertEqual(Set(texts).count, 3, "Ambiguous directions: \(tag)")
            XCTAssertFalse(phrases.name.isEmpty)
            for text in texts {
                XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, tag)
                XCTAssertFalse(text.contains("\n"), tag)
                XCTAssertFalse(text.contains("TODO"), tag)
            }
        }
        XCTAssertEqual(TrackingMode.mouseFollowsVoiceOver.feedback(in: .chinese), "鼠标跟旁白")
        XCTAssertEqual(TrackingMode.voiceOverFollowsMouse.feedback(in: .chinese), "旁白跟鼠标")
        XCTAssertEqual(TrackingMode.ignore.feedback(in: .chinese), "不跟随")
    }

    func testPublishedVoiceOverLanguageCoverageAndExplicitGaps() {
        // Apple feature-availability list read 2026-09-28. This is a locale
        // routing fixture, not a claim of macOS 27 runtime or spoken-language QA.
        let covered = "sq-AL as-IN eu-ES bn-IN bg-BG yue-HK ca-ES hr-HR cs-CZ da-DK nl-NL en-AU en-IN en-IE en-GB-scotland en-ZA en-GB en-US fa-IR fi-FI nl-BE fr-BE fr-CA fr-FR gl-ES de-DE el-GR gu-IN he-IL hi-IN hu-HU id-ID it-IT ja-JP kn-IN kk-KZ ko-KR lt-LT ms-MY ml-IN cmn-CN cmn-TW mr-IN ne-NP nb-NO or-IN pl-PL pt-BR pt-PT pa-IN ro-RO ru-RU wuu-CN sk-SK sl-SI es-AR es-CL es-CO es-MX es-ES sv-SE ta-IN te-IN th-TH tr-TR uk-UA ca-ES-valencia vi-VN".split(separator: " ")
        XCTAssertEqual(covered.count, 68)
        for tag in covered {
            XCTAssertNotNil(FeedbackLanguage.forLanguageTag(String(tag)), String(tag))
        }
        for tag in ["bho-IN", "brx-IN", "doi-IN", "kok-IN", "mai-IN", "mni-IN", "sa-IN"] {
            let selected = FeedbackLanguage.resolve(systemLanguages: [tag])
            XCTAssertEqual(selected, .english)

        }
    }

    func testEnglishSelectionFeedsTwoCompleteCyclesWithoutChangingTrackingOrder() throws {
        let selection = FeedbackLanguage.resolve(systemLanguages: ["en-GB", "zh-CN"])
        let preferences = MemoryPreferences(TrackingMode.ignore.state)
        let expected: [(TrackingMode, String)] = [
            (.mouseFollowsVoiceOver, "Mouse follows VoiceOver"),
            (.voiceOverFollowsMouse, "VoiceOver follows mouse"),
            (.ignore, "No tracking")
        ]
        for _ in 0..<2 {
            for (mode, phrase) in expected {
                let result = try cycle(preferences)
                XCTAssertEqual(result, mode.state)
                XCTAssertEqual(try XCTUnwrap(result.mode).feedback(in: selection), phrase)
            }
        }
        XCTAssertFalse(preferences.writes.contains { $0.mouseToVO && $0.voToMouse })
    }
}
