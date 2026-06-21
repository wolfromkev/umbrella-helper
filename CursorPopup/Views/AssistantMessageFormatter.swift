import AppKit
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
        let spacedMarkdown = normalizeParagraphSpacing(markdown)
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full

        guard var attributed = try? AttributedString(markdown: spacedMarkdown, options: options) else {
            var fallback = AttributedString(spacedMarkdown)
            applyTextSpacing(to: &fallback, fontSize: fontSize)
            return fallback
        }

        applyTextSpacing(to: &attributed, fontSize: fontSize)
        return attributed
    }

    /// Markdown treats single newlines as soft breaks (same paragraph). Insert blank lines
    /// before structural elements so lists, headings, and labels render as separate blocks.
    static func normalizeParagraphSpacing(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return text }

        var result: [String] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if index > 0, !trimmed.isEmpty, looksLikeBlockStart(trimmed) {
                if let last = result.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                    result.append("")
                }
            }
            result.append(line)
        }
        return result.joined(separator: "\n")
    }

    private static func looksLikeBlockStart(_ line: String) -> Bool {
        let patterns = [
            #"^\d+\.\s"#,
            #"^\*\*\d+\."#,
            #"^#{1,6}\s"#,
            #"^[-*+]\s"#,
            #"^\*\*[^*]+:\*\*"#,
        ]
        return patterns.contains { line.range(of: $0, options: .regularExpression) != nil }
    }

    private static func applyTextSpacing(to attributed: inout AttributedString, fontSize: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 10
        var container = AttributeContainer()
        container.paragraphStyle = style
        container.font = .systemFont(ofSize: fontSize)
        attributed.mergeAttributes(container)
    }
}

struct MarkdownMessageText: View {
    let text: String
    var fontSize: CGFloat = 14

    var body: some View {
        Text(AssistantMessageFormatter.attributedString(from: text, fontSize: fontSize))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineSpacing(4)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
