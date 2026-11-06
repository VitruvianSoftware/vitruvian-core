// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import NexusAgentCore
import SwiftUI

// MARK: - The rules

/// The conversation's timeline: one dot per prompt down the chat's edge,
/// a card that previews a prompt and the start of its reply, and a click
/// that scrolls to it. What the rail shows is worked out here, as plain
/// functions the tests drive; `NexusAgentTimelineScrubber` only draws it.
public enum NexusAgentTimeline {
    /// One prompt and the replies after it, up to the next prompt.
    public struct Turn: Identifiable, Equatable, Sendable {
        public var id: UUID { promptID }
        /// The prompt's message, which the chat scrolls to.
        public let promptID: UUID
        /// The prompt, its lines run together.
        public let prompt: String
        /// The start of the turn's first reply that has text, as plain
        /// text; nil while there is none.
        public let replySnippet: String?
        /// When the prompt was sent, if the chat knows.
        public let createdAt: Date?
        /// Every shown message of the turn, the prompt first.
        public let messageIDs: [UUID]
    }

    /// The rail appears from this many turns on: below it there is
    /// nothing to scrub through.
    public static let minimumTurns = 3

    public static func showsRail(turnCount: Int) -> Bool {
        turnCount >= minimumTurns
    }

    /// Whether a message has a bubble: an agent's message with nothing in
    /// it yet (no text, steps, thinking or question) is not drawn, and is
    /// not part of a turn. The chat view draws by the same rule.
    public static func isShown(_ message: NexusAgentChatMessage) -> Bool {
        !(message.role == .agent && message.text.isEmpty && message.approvalRequest == nil
            && (message.toolSteps ?? []).isEmpty && (message.thinkingText ?? "").isEmpty)
    }

    /// The turns of a conversation, in order. Agent messages before the
    /// first prompt (a resumed session's note, say) belong to no turn.
    public static func turns(from messages: [NexusAgentChatMessage]) -> [Turn] {
        var turns: [Turn] = []
        var prompt: NexusAgentChatMessage?
        var ids: [UUID] = []
        var reply: String?
        func close() {
            guard let prompt else { return }
            turns.append(Turn(promptID: prompt.id, prompt: oneLine(prompt.text), replySnippet: reply,
                              createdAt: prompt.createdAt, messageIDs: ids))
        }
        for message in messages where isShown(message) {
            if message.role == .user {
                close()
                prompt = message
                ids = [message.id]
                reply = nil
            } else if prompt != nil {
                ids.append(message.id)
                if reply == nil, !message.isError {
                    let snippet = plainSnippet(message.text)
                    if !snippet.isEmpty { reply = snippet }
                }
            }
        }
        close()
        return turns
    }

    /// Each shown message's turn, by the message's id.
    public static func turnIndexByMessage(_ turns: [Turn]) -> [UUID: Int] {
        var index: [UUID: Int] = [:]
        for (turn, entry) in turns.enumerated() {
            for id in entry.messageIDs { index[id] = turn }
        }
        return index
    }

    /// The turn at the top of the viewport, from the top edge of each turn
    /// with a bubble in view (`tops`, by turn, in the scroll view's own
    /// coordinates): the last one that starts at or above `threshold`.
    /// When every turn in view starts below it, the one before them is the
    /// one still showing at the top. With nothing in view the answer stays
    /// `current`.
    public static func activeTurn(tops: [Int: CGFloat], current: Int, threshold: CGFloat = 40) -> Int {
        if let atTop = tops.filter({ $0.value <= threshold }).keys.max() { return atTop }
        guard let first = tops.keys.min() else { return current }
        return max(0, first - 1)
    }

    // MARK: Text

    /// The prompt's lines as one, for a two-line card.
    static func oneLine(_ text: String) -> String {
        collapseWhitespace(text)
    }

    /// The start of a reply as plain text: no code blocks, heading marks,
    /// list and quote marks, emphasis, inline code ticks or table rules;
    /// a link reads as its text; every run of spaces and new lines is one
    /// space. Cut at `limit` characters with an ellipsis. Only the first
    /// stretch of the reply is read, so a long reply costs no more than a
    /// short one. A reply that is only code keeps the code.
    public static func plainSnippet(_ markdown: String, limit: Int = 220) -> String {
        let head = String(markdown.prefix(1_500))
        var prose: [String] = []
        var code: [String] = []
        var inFence = false
        for rawLine in head.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence {
                code.append(line)
                continue
            }
            if isTableRule(line) { continue }
            prose.append(stripLineMarks(line))
        }
        var text = collapseWhitespace(prose.joined(separator: " "))
        if text.isEmpty { text = collapseWhitespace(code.joined(separator: " ")) }
        text = stripInline(text)
        text = collapseWhitespace(text)
        guard text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// `| --- | :---: |`: a table's rule line.
    private static func isTableRule(_ line: String) -> Bool {
        guard line.contains("-"), line.contains("|") || line.hasPrefix("-") && line.contains(":") else { return false }
        return line.allSatisfy { "|-: ".contains($0) }
    }

    /// A line's leading marks: `#`, `>`, `-`, `*`, `+`, `1.`; a table
    /// row's bars become spaces; a rule (`---`) is dropped.
    private static func stripLineMarks(_ line: String) -> String {
        var line = Substring(line)
        if line.allSatisfy({ "-*_ ".contains($0) }), line.filter({ $0 != " " }).count >= 3 { return "" }
        while line.first == ">" { line = line.dropFirst().drop(while: { $0 == " " }) }
        if line.first == "#" {
            let marks = line.prefix(while: { $0 == "#" })
            let rest = line.dropFirst(marks.count)
            if marks.count <= 6, rest.isEmpty || rest.first == " " { line = rest.drop(while: { $0 == " " }) }
        }
        if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " {
            line = line.dropFirst(2)
        } else {
            let digits = line.prefix(while: \.isNumber)
            let after = line.dropFirst(digits.count)
            if !digits.isEmpty, digits.count <= 3, after.hasPrefix(". ") || after.hasPrefix(") ") {
                line = after.dropFirst(2)
            }
        }
        if line.contains("|") {
            return line.replacingOccurrences(of: "|", with: " ")
        }
        return String(line)
    }

    /// Links and images to their text, then emphasis and code ticks away.
    private static func stripInline(_ text: String) -> String {
        var text = text
        let rules: [(String, String)] = [
            (#"!\[([^\]]*)\]\([^)]*\)"#, "$1"),
            (#"\[([^\]]+)\]\([^)]*\)"#, "$1"),
            (#"\[([^\]]+)\]\[[^\]]*\]"#, "$1"),
            (#"<(https?://[^>\s]+)>"#, "$1"),
            (#"(\*\*|__|~~)(.+?)\1"#, "$2"),
            (#"(?<![\w*])\*(?!\s)([^*\n]+?)(?<!\s)\*(?![\w*])"#, "$1"),
            (#"(?<![\w_])_(?!\s)([^_\n]+?)(?<!\s)_(?![\w_])"#, "$1"),
            (#"`+([^`]*)`+"#, "$1"),
        ]
        for (pattern, template) in rules {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return text
    }

    // MARK: Words

    /// "12 of 40", from the words' pieces.
    public static func position(_ number: Int, of total: Int, strings: NexusAgentChatStrings) -> String {
        "\(number)\(strings.timelineOf)\(total)"
    }

    /// "Prompt 12 of 40: Fix the …": a dot's spoken label, with the
    /// prompt's first sixty characters.
    public static func dotLabel(_ number: Int, of total: Int, prompt: String,
                                strings: NexusAgentChatStrings) -> String {
        let head = prompt.count > 60 ? String(prompt.prefix(60)) + "…" : prompt
        return strings.timelinePromptPrefix + position(number, of: total, strings: strings)
            + strings.timelinePromptSeparator + head
    }

    /// When a prompt was sent, in the reader's locale: the time alone for
    /// one sent today ("3:11 PM"), the date and time for an older one
    /// ("Oct 26, 2026 at 3:11 PM").
    public static func timeLabel(_ date: Date, now: Date, calendar: Calendar = .current,
                                 locale: Locale = .current) -> String {
        var calendar = calendar
        calendar.locale = locale
        let sameDay = calendar.isDate(date, inSameDayAs: now)
        let style = Date.FormatStyle(date: sameDay ? .omitted : .abbreviated, time: .shortened,
                                     locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return date.formatted(style)
    }

    // MARK: Geometry

    /// Where the dots sit on a rail `height` points tall. They are spread
    /// evenly over it; when that would put them closer than `minimumSpacing`
    /// they keep that spacing instead, and the rail shows the stretch of
    /// them around the active dot (`offset` is how far the first dot sits
    /// above the rail's top).
    public struct RailLayout: Equatable, Sendable {
        public let count: Int
        public let height: CGFloat
        public let spacing: CGFloat
        public let offset: CGFloat

        public static let minimumSpacing: CGFloat = 6

        public init(count: Int, height: CGFloat, active: Int) {
            self.count = count
            self.height = max(0, height)
            guard count > 1 else {
                spacing = 0
                offset = -self.height / 2
                return
            }
            let even = self.height / CGFloat(count - 1)
            if even >= Self.minimumSpacing {
                spacing = even
                offset = 0
            } else {
                spacing = Self.minimumSpacing
                let length = spacing * CGFloat(count - 1)
                let centred = CGFloat(min(max(active, 0), count - 1)) * spacing - self.height / 2
                offset = min(max(centred, 0), length - self.height)
            }
        }

        /// Whether every dot fits on the rail.
        public var showsAll: Bool { offset <= 0 && spacing * CGFloat(max(count - 1, 0)) <= height + 0.5 }

        /// A dot's centre, from the rail's top.
        public func y(of index: Int) -> CGFloat {
            CGFloat(index) * spacing - offset
        }

        /// The dot nearest a point `y` down the rail.
        public func nearest(to y: CGFloat) -> Int {
            guard count > 1, spacing > 0 else { return 0 }
            let index = Int(((y + offset) / spacing).rounded())
            return min(max(index, 0), count - 1)
        }
    }
}

// MARK: - The view

/// The timeline over the conversation: a thin rail of dots on one edge,
/// the card beside it while the pointer is on it. It fills the
/// conversation (for the card to stay inside it) but only the rail takes
/// the pointer, so the messages under the rest scroll and click as before.
struct NexusAgentTimelineScrubber: View {
    let turns: [NexusAgentTimeline.Turn]
    /// The turn at the top of the viewport.
    let activeIndex: Int
    @Binding var onLeft: Bool
    let strings: NexusAgentChatStrings
    /// Scrolls the conversation to a prompt.
    let select: (UUID) -> Void
    /// The time the card's dates are read against; nil is now.
    var now: Date? = nil

    @State private var hovered: Int?
    @State private var isOverRail = false
    @State private var cardHeight: CGFloat = 80

    static let railWidth: CGFloat = 14
    static let edgeInset: CGFloat = 6
    static let topInset: CGFloat = 12
    /// Clear of the jump buttons, which stand 72 points tall at most.
    static let bottomInset: CGFloat = 84
    /// Room at the rail's ends for the larger dots.
    static let dotInset: CGFloat = 4
    static let cardWidth: CGFloat = 260
    static let cardGap: CGFloat = 6
    /// Extra room the transcript leaves at the rail's edge: the rail spans
    /// 20 points from the edge, the transcript's own padding is 14.
    static let gutter: CGFloat = 12

    init(turns: [NexusAgentTimeline.Turn], activeIndex: Int, onLeft: Binding<Bool>,
         strings: NexusAgentChatStrings, now: Date? = nil, hovered: Int? = nil,
         select: @escaping (UUID) -> Void) {
        self.turns = turns
        self.activeIndex = activeIndex
        _onLeft = onLeft
        self.strings = strings
        self.now = now
        self.select = select
        _hovered = State(initialValue: hovered)
        _isOverRail = State(initialValue: hovered != nil)
    }

    var body: some View {
        GeometryReader { geo in
            let railHeight = max(0, geo.size.height - Self.topInset - Self.bottomInset)
            let layout = NexusAgentTimeline.RailLayout(
                count: turns.count, height: max(0, railHeight - 2 * Self.dotInset),
                active: min(max(activeIndex, 0), max(turns.count - 1, 0)))
            let railX = onLeft
                ? Self.edgeInset + Self.railWidth / 2
                : geo.size.width - Self.edgeInset - Self.railWidth / 2
            ZStack(alignment: .topLeading) {
                rail(layout: layout, height: railHeight)
                    .frame(width: Self.railWidth, height: railHeight)
                    .position(x: railX, y: Self.topInset + railHeight / 2)
                if let hovered, turns.indices.contains(hovered) {
                    card(for: hovered)
                        .position(cardCentre(dotY: Self.topInset + Self.dotInset + layout.y(of: hovered),
                                             railX: railX, size: geo.size))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.easeOut(duration: 0.15), value: hovered)
        }
    }

    // MARK: The rail

    private func rail(layout: NexusAgentTimeline.RailLayout, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1, height: height)
            ZStack(alignment: .topLeading) {
                ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                    let y = layout.y(of: index)
                    if y >= -Self.dotInset, y <= layout.height + Self.dotInset {
                        dot(index: index, turn: turn)
                            .position(x: Self.railWidth / 2, y: Self.dotInset + y)
                    }
                }
            }
            .frame(width: Self.railWidth, height: height)
            .clipped()
        }
        .frame(width: Self.railWidth, height: height)
        .contentShape(Rectangle())
        .opacity(isOverRail ? 1 : 0.35)
        .animation(.easeOut(duration: 0.15), value: isOverRail)
        .animation(.easeOut(duration: 0.15), value: hovered)
        .animation(.easeOut(duration: 0.15), value: activeIndex)
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                isOverRail = true
                hovered = layout.nearest(to: point.y - Self.dotInset)
            case .ended:
                isOverRail = false
                hovered = nil
            }
        }
        .gesture(SpatialTapGesture().onEnded { tap in
            let index = layout.nearest(to: tap.location.y - Self.dotInset)
            if turns.indices.contains(index) { select(turns[index].promptID) }
        })
        .contextMenu {
            Button(onLeft ? strings.timelineMoveRight : strings.timelineMoveLeft) { onLeft.toggle() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(strings.timelineLabel)
    }

    private func dot(index: Int, turn: NexusAgentTimeline.Turn) -> some View {
        let isHovered = hovered == index
        let isActive = index == activeIndex
        let size: CGFloat = isHovered || isActive ? 7 : 5
        let colour: Color = isHovered ? .primary : isActive ? NexusAgentTheme.warmCoral : .secondary
        return Circle()
            .fill(colour)
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(NexusAgentTimeline.dotLabel(index + 1, of: turns.count, prompt: turn.prompt,
                                                            strings: strings))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { select(turn.promptID) }
    }

    // MARK: The card

    private func card(for index: Int) -> some View {
        let turn = turns[index]
        return VStack(alignment: .leading, spacing: 4) {
            Text(turn.prompt)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            Text(turn.replySnippet ?? strings.timelineWaitingForReply)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(NexusAgentTimeline.position(index + 1, of: turns.count, strings: strings))
                Spacer(minLength: 0)
                if let date = turn.createdAt {
                    Text(NexusAgentTimeline.timeLabel(date, now: now ?? Date()))
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
        }
        .padding(10)
        .frame(width: Self.cardWidth, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .background(GeometryReader { geo in
            Color.clear.preference(key: TimelineCardHeightKey.self, value: geo.size.height)
        })
        .onPreferenceChange(TimelineCardHeightKey.self) { [height = $cardHeight] value in
            if value > 0, abs(value - height.wrappedValue) > 0.5 { height.wrappedValue = value }
        }
        .accessibilityHidden(true)
    }

    /// Beside the rail on the side facing the messages, level with the
    /// dot, and inside the conversation.
    private func cardCentre(dotY: CGFloat, railX: CGFloat, size: CGSize) -> CGPoint {
        let half = Self.cardWidth / 2
        let x = onLeft
            ? railX + Self.railWidth / 2 + Self.cardGap + half
            : railX - Self.railWidth / 2 - Self.cardGap - half
        let margin: CGFloat = 8
        let low = margin + cardHeight / 2
        let high = max(low, size.height - margin - cardHeight / 2)
        return CGPoint(x: min(max(x, half + margin), max(half + margin, size.width - half - margin)),
                       y: min(max(dotY, low), high))
    }
}

private struct TimelineCardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The top edge of each turn with a bubble in view, by turn, in the
/// conversation's scroll coordinates: what the rail's active dot follows.
struct TimelineTopsPreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: min)
    }
}
