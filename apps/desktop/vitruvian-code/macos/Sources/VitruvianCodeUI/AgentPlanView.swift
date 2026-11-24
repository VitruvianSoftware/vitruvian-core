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
//
// Shared by the standalone Vitruvian Code app and the Code feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian-atrium/UPSTREAM.md).

import SwiftUI
import VitruvianCodeCore

/// Pure state and formatting rules for the live agent plan card.
public struct AgentPlanCardState: Equatable, Sendable {
    public private(set) var entries: [PlanEntry]
    public private(set) var isExpanded: Bool
    private var userToggled = false

    public init(entries: [PlanEntry] = [], isExpandedOverride: Bool? = nil) {
        self.entries = entries
        self.isExpanded = isExpandedOverride ?? Self.defaultExpanded(for: entries)
    }

    public static func defaultExpanded(for entries: [PlanEntry]) -> Bool {
        entries.contains { $0.status != .completed }
    }

    public var isVisible: Bool { !entries.isEmpty }
    public var completedCount: Int { entries.filter { $0.status == .completed }.count }
    public var totalCount: Int { entries.count }
    public var allCompleted: Bool { !entries.isEmpty && completedCount == totalCount }
    public var inProgressIndex: Int? { entries.firstIndex { $0.status == .inProgress } }

    public mutating func toggle() {
        isExpanded.toggle()
        userToggled = true
    }

    public mutating func update(entries next: [PlanEntry]) {
        let wasEmpty = entries.isEmpty
        let wasAllCompleted = allCompleted
        entries = next

        guard !next.isEmpty else {
            isExpanded = false
            userToggled = false
            return
        }

        let nowAllCompleted = allCompleted
        if wasEmpty || wasAllCompleted != nowAllCompleted {
            isExpanded = Self.defaultExpanded(for: next)
            userToggled = false
        } else if !userToggled {
            isExpanded = Self.defaultExpanded(for: next)
        }
    }

    public static func format(_ template: String, _ first: String, _ second: String) -> String {
        var text = template
        for argument in [first, second] {
            guard let range = text.range(of: "%@") else { break }
            text.replaceSubrange(range, with: argument)
        }
        return text
    }

    public static func progressText(completed: Int, total: Int, strings: VitruvianCodeChatStrings) -> String {
        format(strings.planProgressFormat, "\(completed)", "\(total)")
    }

    public static func statusLabel(for status: PlanEntry.Status, strings: VitruvianCodeChatStrings) -> String {
        switch status {
        case .pending: return strings.planStatusPending
        case .inProgress: return strings.planStatusInProgress
        case .completed: return strings.planStatusCompleted
        case .other: return strings.planStatusOther
        }
    }

    public static func accessibilityLabel(for entry: PlanEntry, strings: VitruvianCodeChatStrings) -> String {
        "\(statusLabel(for: entry.status, strings: strings)): \(entry.content)"
    }
}

/// Compact collapsible card displaying the agent's live plan above the composer.
public struct AgentPlanView: View {
    public static let maxListHeight: CGFloat = 180

    let entries: [PlanEntry]
    let strings: VitruvianCodeChatStrings
    @State private var state: AgentPlanCardState
    @State private var contentHeight: CGFloat = 0

    public init(
        entries: [PlanEntry],
        strings: VitruvianCodeChatStrings,
        isExpandedOverride: Bool? = nil
    ) {
        self.entries = entries
        self.strings = strings
        _state = State(initialValue: AgentPlanCardState(entries: entries, isExpandedOverride: isExpandedOverride))
    }

    public var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                header
                if state.isExpanded {
                    Divider().opacity(0.25)
                    stepsList
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onChange(of: entries) { _, next in
                withAnimation(.easeInOut(duration: 0.15)) {
                    state.update(entries: next)
                }
            }
        }
    }

    private var header: some View {
        let progress = AgentPlanCardState.progressText(
            completed: state.completedCount,
            total: state.totalCount,
            strings: strings
        )
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                state.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(state.allCompleted ? Color.green : VitruvianCodeTheme.warmCoral)
                Text(strings.plan)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(progress)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: 8)
                Image(systemName: state.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(strings.plan), \(progress)")
    }

    private var stepsList: some View {
        let estimatedHeight = CGFloat(entries.count) * 24 + 8
        let targetHeight = min(contentHeight > 0 ? contentHeight : estimatedHeight, Self.maxListHeight)
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        stepRow(entry)
                            .id(index)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: PlanListHeightPreferenceKey.self, value: geo.size.height)
                    }
                )
            }
            .frame(height: targetHeight)
            .onPreferenceChange(PlanListHeightPreferenceKey.self) { [height = $contentHeight] next in
                if next > 0, abs(next - height.wrappedValue) > 0.5 {
                    height.wrappedValue = next
                }
            }
            .onAppear {
                if let index = state.inProgressIndex {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
            .onChange(of: state.inProgressIndex) { _, index in
                if let index {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
            .onChange(of: entries) { _, _ in
                if let index = state.inProgressIndex {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }

    private func stepRow(_ entry: PlanEntry) -> some View {
        HStack(alignment: .top, spacing: 7) {
            statusGlyph(for: entry.status)
                .frame(width: 12, height: 15, alignment: .center)
            Text(entry.content)
                .font(.system(size: 11.5))
                .foregroundStyle(entry.status == .completed ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AgentPlanCardState.accessibilityLabel(for: entry, strings: strings))
    }

    @ViewBuilder
    private func statusGlyph(for status: PlanEntry.Status) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        case .inProgress:
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(VitruvianCodeTheme.warmCoral)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.green)
        case .other:
            Image(systemName: "minus")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct PlanListHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
