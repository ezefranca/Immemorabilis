import Foundation

enum NaturalLanguageDateParser {
    struct Match: Equatable {
        let date: Date
        let phrase: String
    }

    static func firstDate(in text: String, locale: Locale = .autoupdatingCurrent) -> Match? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        else { return nil }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let result = detector.matches(in: text, options: [], range: range)
            .first { $0.date != nil && $0.range.location != NSNotFound }
        guard let result, let date = result.date, let phraseRange = Range(result.range, in: text) else { return nil }

        // NSDataDetector follows the user's language and regional settings. Referencing
        // the locale here makes that intent explicit and keeps this API easy to extend.
        _ = locale
        return Match(date: date, phrase: String(text[phraseRange]))
    }

    static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: range).compactMap(\.url)
    }
}
