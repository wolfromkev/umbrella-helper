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
            .markdownTheme(.cursorPopupChat)
            .markdownTextStyle {
                FontSize(fontSize)
                BackgroundColor(nil)
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Markdown theme (neutral grey — no GitHub blue panel behind body text)

private extension Theme {
    static let cursorPopupChat: Theme = {
        let codeBackground = Color(nsColor: NSColor(calibratedWhite: 0.10, alpha: 1))
        let tableAltRow = Color(nsColor: NSColor(calibratedWhite: 0.18, alpha: 0.35))
        let borderColor = Color(nsColor: NSColor(calibratedWhite: 0.30, alpha: 0.45))
        let linkColor = Color(nsColor: NSColor(calibratedRed: 0.45, green: 0.62, blue: 0.95, alpha: 1))

        return Theme.gitHub
            .text {
                ForegroundColor(.primary)
                BackgroundColor(nil)
            }
            .link {
                ForegroundColor(linkColor)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.85))
                BackgroundColor(codeBackground)
            }
            .paragraph { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.25))
                    .markdownMargin(top: 0, bottom: 10)
                    .markdownTextStyle {
                        BackgroundColor(nil)
                    }
            }
            .blockquote { configuration in
                HStack(alignment: .top, spacing: 0) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 3)
                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(.secondary)
                            BackgroundColor(nil)
                        }
                        .padding(.leading, 10)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .codeBlock { configuration in
                ScrollView(.horizontal) {
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                        .relativeLineSpacing(.em(0.225))
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.85))
                            BackgroundColor(nil)
                        }
                        .padding(12)
                }
                .background(codeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .markdownMargin(top: 0, bottom: 10)
            }
            .table { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownTableBorderStyle(.init(color: borderColor))
                    .markdownTableBackgroundStyle(
                        .alternatingRows(Color.clear, tableAltRow)
                    )
                    .markdownMargin(top: 0, bottom: 10)
            }
            .tableCell { configuration in
                configuration.label
                    .markdownTextStyle {
                        if configuration.row == 0 {
                            FontWeight(.semibold)
                        }
                        BackgroundColor(nil)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .relativeLineSpacing(.em(0.25))
            }
            .heading1 { configuration in
                headingBlock(configuration, fontSize: .em(1.45), bottomMargin: 10)
            }
            .heading2 { configuration in
                headingBlock(configuration, fontSize: .em(1.3), bottomMargin: 10)
            }
            .heading3 { configuration in
                headingBlock(configuration, fontSize: .em(1.15), bottomMargin: 8)
            }
            .heading4 { configuration in
                headingBlock(configuration, fontSize: .em(1.05), bottomMargin: 8)
            }
            .heading5 { configuration in
                headingBlock(configuration, fontSize: .em(0.95), bottomMargin: 6)
            }
            .heading6 { configuration in
                headingBlock(configuration, fontSize: .em(0.9), bottomMargin: 6, secondary: true)
            }
    }()

    @ViewBuilder
    private static func headingBlock(
        _ configuration: BlockConfiguration,
        fontSize: RelativeSize,
        bottomMargin: CGFloat,
        secondary: Bool = false
    ) -> some View {
        configuration.label
            .relativeLineSpacing(.em(0.125))
            .markdownMargin(top: 4, bottom: bottomMargin)
            .markdownTextStyle {
                FontWeight(.semibold)
                FontSize(fontSize)
                BackgroundColor(nil)
                if secondary {
                    ForegroundColor(.secondary)
                }
            }
    }
}
