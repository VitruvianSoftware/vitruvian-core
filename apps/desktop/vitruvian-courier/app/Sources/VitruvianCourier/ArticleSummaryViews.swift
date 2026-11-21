// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore

/// What a link card needs for "Summarize" (E1): whether to offer it, the summary's state, and what the buttons do.
/// `MessageRowActions.make` fills it from `MessageActionsModel`; by default nothing is offered.
struct ArticleSummaryControls {
    /// Summarize is offered for the link: an https link, "Show link previews" on, an AI service ready.
    var canSummarize: (URL) -> Bool = { _ in false }
    var state: (URL) -> ArticleSummaryState? = { _ in nil }
    /// Any summary at all is open: the cheap check before a message without a card looks for its link.
    var hasAny: () -> Bool = { false }
    var summarize: (ArticleSummaryRequest) -> Void = { _ in }
    var dismiss: (URL) -> Void = { _ in }
    var retry: (URL) -> Void = { _ in }
    var copy: (String) -> Void = { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    var open: (URL) -> Void = { url in
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        _ = NSWorkspace.shared.open(url)
    }
    /// Whether an AI service is ready: part of the row's height signature, since the button comes and goes with it.
    var aiIsAvailable: () -> Bool = { false }
    /// The AI service's name for the button's tooltip ("Claude"): the person sees where the article goes before the
    /// first send.
    var providerName: () -> String = { "" }
    var suggestionsHeight: (URL) -> Int? = { _ in nil }
    var setSuggestionsHeight: (URL, CGFloat) -> Void = { _, _ in }

    /// What the row's height depends on for `message`: whether Summarize is offered, and the state of each link's
    /// summary (a spinner, bullets and a failure are all different heights).
    func heightSignature(for message: TimelineMessage) -> Int {
        var hasher = Hasher()
        hasher.combine(aiIsAvailable())
        guard hasAny() else { return hasher.finalize() }
        var urls: [URL] = message.linkPreviews.compactMap { ArticleSummaryRequest(preview: $0)?.url }
        if let first = ArticleSummaryRequest.first(in: message, isEmbed: Self.isEmbed)?.url { urls.append(first) }
        for url in urls {
            hasher.combine(state(url))
            hasher.combine(suggestionsHeight(url))
        }
        return hasher.finalize()
    }

    /// A link with a player card of its own (YouTube and the like) isn't an article.
    static func isEmbed(_ url: URL) -> Bool {
        ExternalEmbedDescriptor.match(urlString: url.absoluteString) != nil
    }
}

/// The "Summarize" button of a link card, and the panel that replaces it once a summary is asked for.
///
/// This is one self-contained view so that it can sit in the card's footer slot (the card redesign leaves one): the
/// card passes the preview and says whether it draws on a bubble.
struct ArticleSummarySection: View {
    let request: ArticleSummaryRequest
    var onBubble: Bool
    let controls: ArticleSummaryControls

    /// "Summarize with Claude": names the service the article's text goes to.
    private var buttonHelp: String { Self.help(providerName: controls.providerName()) }

    static func help(providerName name: String) -> String {
        name.isEmpty ? String(localized: "Summarize this article with AI") : String(localized: "Summarize with \(name)")
    }

    var body: some View {
        if let state = controls.state(request.url) {
            ArticleSummaryPanel(url: request.url, state: state, onBubble: onBubble, controls: controls)
        } else if controls.canSummarize(request.url) {
            Button {
                controls.summarize(request)
            } label: {
                Label(String(localized: "Summarize"), systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(onBubble ? Color.white : Color.accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(onBubble ? Color.white.opacity(0.18) : Color.accentColor.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .help(buttonHelp)
            .accessibilityLabel(String(localized: "Summarize"))
            .accessibilityIdentifier("article-summarize")
        }
    }
}

/// The summary under a card: a spinner while it works, then 3 to 5 bullets with "Summary by …", "Open article" and
/// "Copy"; or what went wrong, in plain words.
struct ArticleSummaryPanel: View {
    let url: URL
    let state: ArticleSummaryState
    var onBubble: Bool
    let controls: ArticleSummaryControls

    private var primary: Color { onBubble ? .white : .primary }
    private var secondary: Color { onBubble ? Color.white.opacity(0.78) : .secondary }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(onBubble ? Color.white : Color.accentColor)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                controls.dismiss(url)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Close summary"))
            .accessibilityLabel(String(localized: "Close summary"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(onBubble ? Color.black.opacity(0.18) : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(onBubble ? Color.white.opacity(0.22) : Color.primary.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case let .working(phase):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(ArticleSummaryCopy.working(phase))
                    .font(.caption)
                    .foregroundStyle(secondary)
            }
        case let .summary(summary):
            if let header = ArticleSummaryCopy.header(for: state) {
                Text(headerText(header, summary: summary))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(primary)
                    // The link to the source is the accent colour, or white on an accent-coloured bubble.
                    .tint(onBubble ? Color.white : nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(summary.bullets.enumerated()), id: \.offset) { _, bullet in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(bullet).textSelection(.enabled)
                }
                .font(.caption)
                .foregroundStyle(primary)
                .fixedSize(horizontal: false, vertical: true)
            }
            footer(summary)
            if let suggestions = summary.searchSuggestionsHTML {
                // Google's terms: its search suggestions go under whatever its search grounded.
                SearchSuggestionsBlock(
                    html: suggestions,
                    height: CGFloat(controls.suggestionsHeight(url) ?? Int(SearchSuggestionsBlock.placeholderHeight)),
                    onHeight: { controls.setSuggestionsHeight(url, $0) })
            }
        case let .failed(failure):
            if let header = ArticleSummaryCopy.header(for: state) {
                Text(header)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case let .notFoundElsewhere(_, _, detail?) = failure {
                Text(detail).font(.caption).foregroundStyle(secondary).fixedSize(horizontal: false, vertical: true)
            }
            if canRetry(failure) {
                Button(String(localized: "Try Again")) { controls.retry(url) }
                    .buttonStyle(.borderless)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(onBubble ? Color.white : Color.accentColor)
            }
        }
    }

    private func canRetry(_ failure: ArticleSummaryFailure) -> Bool {
        switch failure {
        case .aiError: true
        case let .notFoundElsewhere(_, _, detail): detail != nil
        }
    }

    /// The header, with the domain of the page the summary is from as a link to it.
    private func headerText(_ header: String, summary: ArticleSummary) -> AttributedString {
        var text = AttributedString(header)
        if case .elsewhere = summary.origin, let range = text.range(of: summary.sourceDomain, options: .backwards) {
            text[range].link = summary.sourceURL
            text[range].underlineStyle = .single
        }
        return text
    }

    private func footer(_ summary: ArticleSummary) -> some View {
        HStack(spacing: 10) {
            Text(ArticleSummaryCopy.footer(for: summary))
                .font(.caption2)
                .foregroundStyle(secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(String(localized: "Open article")) { controls.open(summary.sourceURL) }
                .buttonStyle(.borderless)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(onBubble ? Color.white : Color.accentColor)
            Button(String(localized: "Copy")) { controls.copy(summary.copyText) }
                .buttonStyle(.borderless)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(onBubble ? Color.white : Color.accentColor)
        }
    }
}
