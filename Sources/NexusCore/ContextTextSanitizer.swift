import Foundation

/// Removes internal citation aliases from model-written text before it reaches a user or an agent.
/// Citation aliases are request metadata, not part of the confirmed context language.
public enum ContextTextSanitizer {
    private static let citationAliasPattern = #"(?<![A-Za-z0-9])S[0-9]{1,3}(?![A-Za-z0-9])"#
    private static let citationWords = ["来源", "依据", "引用", "参见", "source", "citation", "ref"]

    public static func cleanText(_ text: String) -> String {
        cleanText(text, forceInternalAliases: false)
    }

    /// Cleans text that came from a model-generated Context Pack or projection.
    /// Unlike user-authored text, generated context must never expose request-only
    /// citation aliases such as S3 in natural-language fields.
    public static func cleanGeneratedText(_ text: String) -> String {
        cleanText(text, forceInternalAliases: true)
    }

    private static func cleanText(_ text: String, forceInternalAliases: Bool) -> String {
        let regex = try! NSRegularExpression(pattern: citationAliasPattern)
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        let removeAllAliases = forceInternalAliases || matches.count > 1
        let mutableText = NSMutableString(string: text)

        for match in matches.reversed() {
            let beforeStart = max(0, match.range.location - 10)
            let before = source.substring(
                with: NSRange(location: beforeStart, length: match.range.location - beforeStart)
            )
            let previousToken = before
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isWhitespace)
                .last
            let followsTechnicalToken = previousToken?.unicodeScalars.allSatisfy {
                (48...57).contains($0.value) || (65...90).contains($0.value) || (97...122).contains($0.value)
            } == true
            let shouldRemove = !followsTechnicalToken
                && (removeAllAliases
                    || citationWords.contains { before.lowercased().hasSuffix($0.lowercased()) })
            if shouldRemove {
                mutableText.replaceCharacters(in: match.range, with: "")
            }
        }

        return String(mutableText)
            .replacingOccurrences(
                of: #"\s*(\(\s*\)|（\s*）)"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: "  ", with: " ")
            .replacingOccurrences(
                of: #"\s+([，。！？；：、）】])"#,
                with: "$1",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func clean(_ content: ContextPackContent) -> ContextPackContent {
        var cleaned = content
        cleaned.objective = cleanText(content.objective, forceInternalAliases: true)
        cleaned.scopeIn = cleanClaims(content.scopeIn)
        cleaned.scopeOut = cleanClaims(content.scopeOut)
        cleaned.confirmedFacts = cleanClaims(content.confirmedFacts)
        cleaned.constraints = cleanClaims(content.constraints)
        cleaned.acceptanceCriteria = cleanClaims(content.acceptanceCriteria)
        cleaned.assumptions = cleanClaims(content.assumptions)
        cleaned.questions = content.questions.map { question in
            var cleanedQuestion = question
            cleanedQuestion.question = cleanText(question.question, forceInternalAliases: true)
            cleanedQuestion.whyItMatters = cleanText(question.whyItMatters, forceInternalAliases: true)
            return cleanedQuestion
        }
        cleaned.brief = cleanText(content.brief, forceInternalAliases: true)
        return cleaned
    }

    private static func cleanClaims(_ claims: [ContextClaim]) -> [ContextClaim] {
        claims.map { claim in
            var cleanedClaim = claim
            cleanedClaim.text = cleanText(claim.text, forceInternalAliases: true)
            return cleanedClaim
        }
    }
}
