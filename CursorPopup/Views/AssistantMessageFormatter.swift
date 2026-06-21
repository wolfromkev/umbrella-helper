import AppKit
import MarkdownUI
import SwiftUI

enum AssistantMessageFormatter {
    private static let statusLinePattern = try! NSRegularExpression(
        pattern: #"^(Checking|Looking|Reading|Searching|Inspecting|Reviewing|Gathering|Analyzing|Loading|Fetching|Exploring)[^\n]{0,240}\.\s*\n+"#,
        options: [.caseInsensitive]
    )

    private static let runOnSentencePattern = try! NSRegularExpression(
        pattern: #"([.!?])\s*([A-Z])"#
    )

    private static let inlineLineLabelPattern = try! NSRegularExpression(
        pattern: #"\s+(Line\s+\w+:)"#
    )

    static func displayText(from rawText: String) -> String {
        let stripped = stripStatusPreamble(from: rawText)
        if !stripped.isEmpty {
            return stripped
        }
        return looksLikeStatusIndicator(rawText) ? "" : rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Markdown source for rendering. Plain streamed text may omit newlines; rich markdown is passed through.
    static func markdownContent(from text: String) -> String {
        guard !containsMarkdownSyntax(text) else { return text }
        return expandPlainRunOnText(text)
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

    private static func containsMarkdownSyntax(_ text: String) -> Bool {
        if text.contains("```") || text.contains("**") || text.contains("__") || text.contains("`") {
            return true
        }

        if text.contains("](") || text.contains("|") {
            return true
        }

        let blockPattern = #"(^|\n)(#{1,6}\s|[-*+]\s|\d+\.\s|>\s?|---+\s*$)"#
        return text.range(of: blockPattern, options: .regularExpression) != nil
    }

    /// Only for plain streamed text with missing newlines — never run on markdown.
    private static func expandPlainRunOnText(_ text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var expanded = runOnSentencePattern.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: "$1\n\n$2"
        )

        let lineLabelRange = NSRange(expanded.startIndex..<expanded.endIndex, in: expanded)
        return inlineLineLabelPattern.stringByReplacingMatches(
            in: expanded,
            range: lineLabelRange,
            withTemplate: "\n$1"
        )
    }
}

struct MarkdownMessageText: View {
    let text: String
    var fontSize: CGFloat = 14

    var body: some View {
        Markdown(AssistantMessageFormatter.markdownContent(from: text))
            .markdownTheme(.gitHub)
            .markdownTextStyle {
                FontSize(fontSize)
                BackgroundColor(nil)
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
