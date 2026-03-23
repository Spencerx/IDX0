import SwiftUI

enum FuzzyMatch {
    /// Returns true if all characters in query appear in order in text.
    static func matches(query: String, text: String) -> Bool {
        var textIndex = text.startIndex
        for char in query {
            guard let found = text[textIndex...].firstIndex(of: char) else { return false }
            textIndex = text.index(after: found)
        }
        return true
    }

    /// Scores a match. Higher = better. Consecutive matches and word boundaries score higher.
    static func score(query: String, text: String) -> Int {
        var score = 0
        var textIndex = text.startIndex
        var lastMatchIndex: String.Index?
        for char in query {
            guard let found = text[textIndex...].firstIndex(of: char) else { return 0 }
            score += 10
            if let last = lastMatchIndex, text.index(after: last) == found {
                score += 5
            }
            if found == text.startIndex || text[text.index(before: found)] == " " || text[text.index(before: found)] == "-" {
                score += 3
            }
            lastMatchIndex = found
            textIndex = text.index(after: found)
        }
        return score
    }

    /// Returns an AttributedString with matched characters highlighted.
    static func highlight(query: String, in title: String) -> AttributedString {
        var result = AttributedString(title)
        let lowerQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lowerTitle = title.lowercased()
        guard !lowerQuery.isEmpty else { return result }

        var searchStart = lowerTitle.startIndex
        for char in lowerQuery {
            if let range = lowerTitle[searchStart...].range(of: String(char)) {
                let startOffset = lowerTitle.distance(from: lowerTitle.startIndex, to: range.lowerBound)
                let endOffset = lowerTitle.distance(from: lowerTitle.startIndex, to: range.upperBound)
                let attrRange = result.index(result.startIndex, offsetByCharacters: startOffset)..<result.index(result.startIndex, offsetByCharacters: endOffset)
                result[attrRange].foregroundColor = .white
                searchStart = range.upperBound
            }
        }
        return result
    }
}
