import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case system, english = "en", arabic = "ar"
    public static let preferenceKey = "whoop.language.v1"
    public static var current: AppLanguage { resolve(stored: UserDefaults.standard.string(forKey: preferenceKey), preferred: Locale.preferredLanguages) }
    public static func resolve(stored: String?, preferred: [String]) -> AppLanguage {
        if let explicit = stored.flatMap(AppLanguage.init(rawValue:)), explicit != .system { return explicit }
        return preferred.first?.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first == "ar" ? .arabic : .english
    }
    public var code: String { self == .system ? Self.current.code : rawValue }
    public var isRightToLeft: Bool { code == "ar" }
    // Keep the wearable's familiar numeric notation; Arabic input is still accepted.
    public var locale: Locale { Locale(identifier: isRightToLeft ? "ar_AE@numbers=latn" : "en") }
    public static var isArabic: Bool { current.isRightToLeft }
    public static func choose(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: preferenceKey)
        if language == .system { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
        else { UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages") }
    }
    public static func canonicalDigits(_ input: String) -> String {
        input.reduce(into: "") { result, character in
            if let digit = character.wholeNumberValue, (0...9).contains(digit) { result += String(digit) }
            else if character == "٫" { result += "." }
            else if character == "٬" || character == "\u{200e}" || character == "\u{200f}" || character == "\u{061c}" { }
            else { result.append(character) }
        }
    }
}

/// UI strings only. Imported names, notes, persisted keys and export schemas are not translated.
public enum L10n {
    private struct Template {
        let regex: NSRegularExpression
        let translation: String
    }
    private static let table: [String: String] = {
        guard let url = Bundle.module.url(forResource: "arabic", withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return value
    }()
    private static let folded: [String: String] = {
        var result: [String: String] = [:]
        for key in table.keys.sorted() where result[key.lowercased()] == nil { result[key.lowercased()] = table[key] }
        return result
    }()
    private static let placeholders = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
    private static let templates: [Template] = table.keys.filter { $0.contains("{0}") }.sorted { $0.count > $1.count }.compactMap { key in
        var pattern = NSRegularExpression.escapedPattern(for: key)
        let matches = placeholders.matches(in: key, range: NSRange(key.startIndex..., in: key))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: key) else { continue }
            pattern = pattern.replacingOccurrences(of: NSRegularExpression.escapedPattern(for: String(key[range])), with: "(.*?)")
        }
        guard let regex = try? NSRegularExpression(pattern: "^" + pattern + "$", options: [.dotMatchesLineSeparators]), let translation = table[key] else { return nil }
        return Template(regex: regex, translation: translation)
    }
    public static func text(_ english: String, language: AppLanguage = .current) -> String {
        guard language.isRightToLeft else { return english }
        if let value = table[english] ?? folded[english.lowercased()] { return value }
        for template in templates {
            guard let match = template.regex.firstMatch(in: english, range: NSRange(english.startIndex..., in: english)) else { continue }
            var value = template.translation
            let slots = placeholders.matches(in: value, range: NSRange(value.startIndex..., in: value))
            for slot in slots.reversed() {
                guard let indexRange = Range(slot.range(at: 1), in: value), let index = Int(value[indexRange]),
                      index + 1 < match.numberOfRanges, let source = Range(match.range(at: index + 1), in: english), let target = Range(slot.range, in: value) else { continue }
                value.replaceSubrange(target, with: english[source])
            }
            return value
        }
        return english
    }
}

/// Adds the response language without changing any existing nutrition request keys.
public struct NutritionLanguageRequest<Body: Encodable>: Encodable {
    public let body: Body
    public let language: String
    public init(body: Body, language: String) { self.body = body; self.language = language }
    private enum CodingKeys: String, CodingKey { case language }
    public func encode(to encoder: Encoder) throws {
        try body.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(language, forKey: .language)
    }
}
