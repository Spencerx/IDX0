import Foundation

struct BranchNameGenerator {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter
    }()

    static func generate(
        sessionTitle: String?,
        repoName: String,
        now: Date = Date()
    ) -> String {
        let preferredSource = (sessionTitle?.isEmpty == false ? sessionTitle : repoName) ?? repoName
        let preferredSlug = slugifyAllowingEmpty(preferredSource)
        let repoSlug = slugifyAllowingEmpty(repoName)
        let base = !preferredSlug.isEmpty ? preferredSlug : (!repoSlug.isEmpty ? repoSlug : "session")
        let timestamp = formatter.string(from: now)
        return "idx0/\(base)-\(timestamp)"
    }

    static func slugify(_ value: String) -> String {
        let collapsed = slugifyAllowingEmpty(value)
        return collapsed.isEmpty ? "session" : collapsed
    }

    private static func slugifyAllowingEmpty(_ value: String) -> String {
        let lower = value.lowercased()
        let mapped = lower.map { char -> Character in
            switch char {
            case "a"..."z", "0"..."9":
                return char
            case " ", "_", "/", ".", ":":
                return "-"
            default:
                return "-"
            }
        }

        let collapsed = String(mapped)
            .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return collapsed
    }
}
