import SwiftUI

enum AssistantMessageFormatter {
    private static let statusLinePattern = try! NSRegularExpression(
        pattern: #"^(Checking|Looking|Reading|Searching|Inspecting|Reviewing|Gathering|Analyzing|Loading|Fetching|Exploring)[^\n]{0,240}\.\s*\n+"#,
        options: [.caseInsensitive]
    )

    static func displayText(from rawText: String) -> String {
        let stripped = stripStatusPreamble(from: rawText)
        if !stripped.isEmpty {
            return stripped
        }
        return looksLikeStatusIndicator(rawText) ? "" : rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeStatusIndicator(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let statusPrefix = #"^(Checking|Looking|Reading|Searching|Inspecting|Reviewing|Gathering|Analyzing|Loading|Fetching|Exploring)\b"#
        guard trimmed.range(of: statusPrefix, options: [.regularExpression, .caseInsensitive]) != nil else {
            return false
        }

        return !trimmed.contains("##") && !trimmed.contains("**")
    }

    static func stripStatusPreamble(from text: String) -> String {
        var remaining = text
        var didStrip = true

        while didStrip {
            didStrip = false
            let range = NSRange(remaining.startIndex..<remaining.endIndex, in: remaining)
            guard let match = statusLinePattern.firstMatch(in: remaining, range: range),
                  let swiftRange = Range(match.range, in: remaining)
            else {
                break
            }

            remaining.removeSubrange(swiftRange)
            didStrip = true
        }

        return remaining.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func attributedString(from markdown: String, fontSize: CGFloat) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full

        guard var attributed = try? AttributedString(markdown: markdown, options: options) else {
            var fallback = AttributedString(markdown)
            fallback.font = .systemFont(ofSize: fontSize)
            return fallback
        }

        attributed.font = .systemFont(ofSize: fontSize)
        return attributed
    }
}

struct MarkdownMessageText: View {
    let text: String
    var fontSize: CGFloat = 14

    var body: some View {
        Text(AssistantMessageFormatter.attributedString(from: text, fontSize: fontSize))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
