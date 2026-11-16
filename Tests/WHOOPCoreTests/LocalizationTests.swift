import Foundation
import XCTest
@testable import WHOOPCore

final class LocalizationTests: XCTestCase {
    func testLanguageResolutionAndDirection() {
        XCTAssertEqual(AppLanguage.resolve(stored: "ar", preferred: ["en-US"]), .arabic)
        XCTAssertEqual(AppLanguage.resolve(stored: "en", preferred: ["ar-AE"]), .english)
        XCTAssertEqual(AppLanguage.resolve(stored: nil, preferred: ["ar_AE"]), .arabic)
        XCTAssertEqual(AppLanguage.resolve(stored: "invalid", preferred: []), .english)
        XCTAssertTrue(AppLanguage.arabic.isRightToLeft)
        XCTAssertFalse(AppLanguage.english.isRightToLeft)
    }
    func testArabicDigitsAndDecimalInput() {
        XCTAssertEqual(AppLanguage.canonicalDigits("١٬٢٣٤٫٥"), "1234.5")
        XCTAssertEqual(AppLanguage.canonicalDigits("۷۲٫۳"), "72.3")
        XCTAssertEqual(AppLanguage.canonicalDigits("\u{200f}-١٢٫٥"), "-12.5")
        XCTAssertEqual(AppLanguage.canonicalDigits("123.4"), "123.4")
    }
    func testArabicDecimalParsingNeverDropsFractionOrAcceptsAPrefix() throws {
        let parser = AppNumberStyle().parseStrategy
        XCTAssertEqual(try parser.parse("١٢٣٫٤"), 123.4)
        XCTAssertEqual(try parser.parse("١٬٢٣٤٫٥"), 1234.5)
        XCTAssertEqual(try parser.parse("۷۲.۳"), 72.3)
        XCTAssertEqual(try parser.parse("123.4"), 123.4)
        XCTAssertThrowsError(try parser.parse("123.4 calories"))
        XCTAssertThrowsError(try parser.parse("NaN"))
        XCTAssertThrowsError(try parser.parse("Infinity"))
        XCTAssertEqual(try parser.parse(AppNumberStyle().format(1234.56789)), 1234.56789)
    }
    func testTranslatedTemplatePreservesUserContent() {
        XCTAssertEqual(L10n.text("Recovery", language: .arabic), "التعافي")
        XCTAssertEqual(L10n.text("RECOVERY", language: .arabic), "التعافي")
        XCTAssertEqual(L10n.text("Connect to Abdullah {0}", language: .arabic), "الاتصال بـ Abdullah {0}")
        XCTAssertEqual(L10n.text("Protein", language: .english), "Protein")
        XCTAssertEqual(L10n.text("Untranslated user name", language: .arabic), "Untranslated user name")
        XCTAssertEqual(L10n.text("12 saved days · 3 logged activities", language: .arabic), "12 أيام محفوظة · 3 أنشطة مسجّلة")
    }
    func testLanguageRequestPreservesFlatAPIContract() throws {
        struct Food: Encodable { let text: String }
        struct Request: Decodable { let text: String; let language: String }
        let data = try JSONEncoder().encode(NutritionLanguageRequest(body: Food(text: "بيضتان"), language: "ar"))
        let decoded = try JSONDecoder().decode(Request.self, from: data)
        XCTAssertEqual(decoded.text, "بيضتان"); XCTAssertEqual(decoded.language, "ar")
    }
}
