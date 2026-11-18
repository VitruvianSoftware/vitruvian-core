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

import AppKit
import SwiftUI
import VitruvianCodeCore

/// Pure form state, validation, encoding, shortcut mapping, and summary projection for `AgentQuestion`.
public struct AgentQuestionForm: Equatable, Sendable {
    public static let urlDecisionKey = "decision"

    public struct SummaryRow: Equatable, Sendable {
        public let label: String?
        public let value: String

        public init(label: String?, value: String) {
            self.label = label
            self.value = value
        }
    }

    public let question: AgentQuestion
    public private(set) var choiceValues: [String: String] = [:]
    public private(set) var multiChoiceValues: [String: [String]] = [:]
    public private(set) var booleanValues: [String: Bool] = [:]
    public private(set) var textValues: [String: String] = [:]

    public init(question: AgentQuestion) {
        self.question = question
        for field in question.fields where field.type == .boolean {
            booleanValues[field.id] = false
        }
    }

    public var shortcutFieldID: String? {
        question.fields.first(where: { $0.type == .choice || $0.type == .multiChoice })?.id
    }

    public func selectedChoice(for fieldID: String) -> String? {
        choiceValues[fieldID]
    }

    public func selectedMultiChoice(for fieldID: String) -> [String] {
        multiChoiceValues[fieldID] ?? []
    }

    public func booleanValue(for fieldID: String) -> Bool {
        booleanValues[fieldID] ?? false
    }

    public func textValue(for fieldID: String) -> String {
        textValues[fieldID] ?? ""
    }

    public mutating func selectChoice(fieldID: String, value: String) {
        guard let field = question.fields.first(where: { $0.id == fieldID }),
              field.type == .choice,
              field.options.contains(where: { $0.value == value }) else {
            return
        }
        if !field.required && choiceValues[fieldID] == value {
            choiceValues.removeValue(forKey: fieldID)
        } else {
            choiceValues[fieldID] = value
        }
    }

    public mutating func toggleMultiChoice(fieldID: String, value: String) {
        guard let field = question.fields.first(where: { $0.id == fieldID }),
              field.type == .multiChoice,
              field.options.contains(where: { $0.value == value }) else {
            return
        }
        var current = Set(multiChoiceValues[fieldID] ?? [])
        if current.contains(value) {
            current.remove(value)
        } else {
            current.insert(value)
        }
        let ordered = field.options.map(\.value).filter { current.contains($0) }
        multiChoiceValues[fieldID] = ordered
    }

    public mutating func setBoolean(fieldID: String, value: Bool) {
        guard question.fields.contains(where: { $0.id == fieldID && $0.type == .boolean }) else {
            return
        }
        booleanValues[fieldID] = value
    }

    public mutating func setText(fieldID: String, value: String) {
        guard let field = question.fields.first(where: { $0.id == fieldID }),
              field.type == .text || field.type == .number || field.type == .integer else {
            return
        }
        textValues[fieldID] = value
    }

    /// Selects or toggles the 1-based option index on the first choice/multi_choice field.
    @discardableResult
    public mutating func applyDigitShortcut(_ digit: Int) -> Bool {
        guard (1...9).contains(digit),
              let field = question.fields.first(where: { $0.type == .choice || $0.type == .multiChoice }) else {
            return false
        }
        let index = digit - 1
        guard field.options.indices.contains(index) else {
            return false
        }
        let value = field.options[index].value
        switch field.type {
        case .choice:
            selectChoice(fieldID: field.id, value: value)
            return true
        case .multiChoice:
            toggleMultiChoice(fieldID: field.id, value: value)
            return true
        case .text, .number, .integer, .boolean:
            return false
        }
    }

    /// Validates numeric input consistently with `ACPElicitationForm`.
    public static func isValidNumber(_ raw: String, integer: Bool) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = Double(trimmed), parsed.isFinite else {
            return false
        }
        if integer {
            return parsed.rounded() == parsed
                && parsed >= Double(Int.min)
                && parsed <= Double(Int.max)
        }
        return true
    }

    public func hasParseError(fieldID: String) -> Bool {
        guard let field = question.fields.first(where: { $0.id == fieldID }),
              field.type == .number || field.type == .integer else {
            return false
        }
        let trimmed = (textValues[fieldID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        return !Self.isValidNumber(trimmed, integer: field.type == .integer)
    }

    public static func encodeMultiChoice(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    public static func decodeMultiChoice(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("["),
           let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
        }
        guard !trimmed.isEmpty else { return [] }
        return trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Returns validated form answers ready to send, or `nil` when incomplete or invalid.
    public func buildAnswers() -> [String: String]? {
        if question.url != nil {
            return nil
        }
        var output: [String: String] = [:]
        for field in question.fields {
            switch field.type {
            case .choice:
                if let value = choiceValues[field.id],
                   field.options.contains(where: { $0.value == value }) {
                    output[field.id] = value
                } else if field.required {
                    return nil
                }

            case .multiChoice:
                let validOptions = Set(field.options.map(\.value))
                let selected = (multiChoiceValues[field.id] ?? []).filter { validOptions.contains($0) }
                if selected.isEmpty {
                    if field.required { return nil }
                } else {
                    output[field.id] = Self.encodeMultiChoice(selected)
                }

            case .boolean:
                output[field.id] = (booleanValues[field.id] ?? false) ? "true" : "false"

            case .text:
                let raw = textValues[field.id] ?? ""
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    if field.required { return nil }
                } else {
                    output[field.id] = raw
                }

            case .number, .integer:
                let trimmed = (textValues[field.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    if field.required { return nil }
                } else {
                    guard Self.isValidNumber(trimmed, integer: field.type == .integer) else {
                        return nil
                    }
                    output[field.id] = trimmed
                }
            }
        }
        return output
    }

    public var canSubmit: Bool {
        buildAnswers() != nil
    }

    public static func urlHost(for rawURL: String) -> String {
        if let parsed = URL(string: rawURL), let host = parsed.host, !host.isEmpty {
            return host
        }
        return rawURL
    }

    public static func summaryRows(
        for question: AgentQuestion,
        answers: [String: String],
        strings: VitruvianCodeChatStrings
    ) -> [SummaryRow] {
        if question.url != nil {
            let raw = (answers[urlDecisionKey] ?? answers["action"] ?? answers["url"] ?? answers.values.first ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let declined = raw == "decline" || raw == "reject" || raw == "deny" || raw == "false"
            return [SummaryRow(label: nil, value: declined ? strings.declineLink : strings.openLink)]
        }

        let showFieldLabels = question.fields.count > 1
        var rows: [SummaryRow] = []
        for field in question.fields {
            guard let raw = answers[field.id], !raw.isEmpty else { continue }
            let fieldLabel = showFieldLabels ? field.label : nil
            switch field.type {
            case .choice:
                let display = field.options.first(where: { $0.value == raw })?.label ?? raw
                rows.append(SummaryRow(label: fieldLabel, value: display))
            case .multiChoice:
                let values = decodeMultiChoice(raw)
                let labels = values.map { val in
                    field.options.first(where: { $0.value == val })?.label ?? val
                }
                guard !labels.isEmpty else { continue }
                rows.append(SummaryRow(label: fieldLabel, value: labels.joined(separator: ", ")))
            case .boolean:
                let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let display = normalized == "true" ? strings.booleanYes : strings.booleanNo
                rows.append(SummaryRow(label: fieldLabel, value: display))
            case .text, .number, .integer:
                rows.append(SummaryRow(label: fieldLabel, value: raw))
            }
        }
        return rows
    }
}

/// Interactive question form and URL-consent card rendered inside an agent message bubble.
struct AgentFormCard: View {
    let question: AgentQuestion
    let status: AgentQuestionStatus
    let strings: VitruvianCodeChatStrings
    var errorScheme: String = "vitruvian-code-error"
    var workingDirectory: String? = nil
    var isShortcutActive: Bool = false
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var onAnswer: ([String: String]) -> Void = { _ in }
    var onSkip: () -> Void = {}

    @State private var form: AgentQuestionForm
    @State private var hoveredRow: String?
    @State private var hoveredButton: String?

    init(
        question: AgentQuestion,
        status: AgentQuestionStatus,
        strings: VitruvianCodeChatStrings,
        errorScheme: String = "vitruvian-code-error",
        workingDirectory: String? = nil,
        isShortcutActive: Bool = false,
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        onAnswer: @escaping ([String: String]) -> Void = { _ in },
        onSkip: @escaping () -> Void = {}
    ) {
        self.question = question
        self.status = status
        self.strings = strings
        self.errorScheme = errorScheme
        self.workingDirectory = workingDirectory
        self.isShortcutActive = isShortcutActive
        self.openURL = openURL
        self.onAnswer = onAnswer
        self.onSkip = onSkip
        self._form = State(initialValue: AgentQuestionForm(question: question))
    }

    private var isPending: Bool {
        status == .pending
    }

    private var headerTitle: String {
        if let title = question.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return strings.questionTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow

            if !question.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VitruvianCodeMarkdownContentView(
                    text: question.message,
                    strings: strings,
                    errorScheme: errorScheme,
                    workingDirectory: workingDirectory
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let rawURL = question.url {
                urlBody(rawURL: rawURL)
            } else {
                formBody
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isPending ? VitruvianCodeTheme.warmCoral.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .background(
            FormCardKeyMonitor(
                isActive: { isPending && isShortcutActive },
                onDigit: { digit in
                    form.applyDigitShortcut(digit)
                },
                onReturn: {
                    submitIfValid()
                }
            )
        )
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(isPending ? VitruvianCodeTheme.warmCoral : Color.secondary)
            Text(headerTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .pending:
            Text(strings.waitingForAnswer)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(VitruvianCodeTheme.warmCoral)
        case .answered:
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                Text(strings.answered)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
            }
        case .skipped:
            Text(strings.skipped)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        case .expired:
            Text(strings.noLongerWaiting)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func urlBody(rawURL: String) -> some View {
        Text(AgentQuestionForm.urlHost(for: rawURL))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.primary.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

        switch status {
        case .pending:
            HStack(spacing: 8) {
                Button {
                    onAnswer([AgentQuestionForm.urlDecisionKey: "decline"])
                } label: {
                    Text(strings.declineLink)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(hoveredButton == "decline" ? 0.12 : 0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                        )
                        .foregroundStyle(Color.primary.opacity(0.9))
                }
                .buttonStyle(.plain)
                .onHover { hoveredButton = $0 ? "decline" : nil }

                Button {
                    if let parsed = URL(string: rawURL) {
                        openURL(parsed)
                    }
                    onAnswer([AgentQuestionForm.urlDecisionKey: "accept"])
                } label: {
                    Text(strings.openLink)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(hoveredButton == "accept" ? VitruvianCodeTheme.warmCoralLight : VitruvianCodeTheme.warmCoral)
                        )
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .onHover { hoveredButton = $0 ? "accept" : nil }

                Spacer(minLength: 0)
            }
            .padding(.top, 2)

        case .answered(let answers):
            answeredSummaryView(answers: answers)

        case .skipped, .expired:
            EmptyView()
        }
    }

    @ViewBuilder
    private var formBody: some View {
        switch status {
        case .pending:
            VStack(alignment: .leading, spacing: 10) {
                let showFieldLabels = question.fields.count > 1
                let shortcutFieldID = form.shortcutFieldID
                ForEach(question.fields) { field in
                    fieldView(
                        field,
                        showLabel: showFieldLabels,
                        showsShortcuts: field.id == shortcutFieldID
                    )
                }
                footerButtons
            }

        case .answered(let answers):
            answeredSummaryView(answers: answers)

        case .skipped, .expired:
            EmptyView()
        }
    }

    @ViewBuilder
    private func fieldView(_ field: AgentQuestion.Field, showLabel: Bool, showsShortcuts: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if showLabel {
                HStack(spacing: 4) {
                    Text(field.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if field.required {
                        Text("*")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(VitruvianCodeTheme.warmCoral)
                            .accessibilityLabel(strings.requiredField)
                    }
                }
                if let desc = field.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !desc.isEmpty,
                   desc != field.label {
                    Text(desc)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            switch field.type {
            case .choice:
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(field.options.enumerated()), id: \.element.value) { index, option in
                        let selected = form.selectedChoice(for: field.id) == option.value
                        optionRow(
                            fieldID: field.id,
                            option: option,
                            index: index,
                            isMulti: false,
                            isSelected: selected,
                            showsShortcut: showsShortcuts && index < 9
                        ) {
                            form.selectChoice(fieldID: field.id, value: option.value)
                        }
                    }
                }

            case .multiChoice:
                let selectedValues = Set(form.selectedMultiChoice(for: field.id))
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(field.options.enumerated()), id: \.element.value) { index, option in
                        let selected = selectedValues.contains(option.value)
                        optionRow(
                            fieldID: field.id,
                            option: option,
                            index: index,
                            isMulti: true,
                            isSelected: selected,
                            showsShortcut: showsShortcuts && index < 9
                        ) {
                            form.toggleMultiChoice(fieldID: field.id, value: option.value)
                        }
                    }
                }

            case .boolean:
                HStack(spacing: 8) {
                    Toggle(
                        isOn: Binding(
                            get: { form.booleanValue(for: field.id) },
                            set: { form.setBoolean(fieldID: field.id, value: $0) }
                        )
                    ) {
                        Text(form.booleanValue(for: field.id) ? strings.booleanYes : strings.booleanNo)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    Spacer(minLength: 0)
                }

            case .text, .number, .integer:
                let hasError = form.hasParseError(fieldID: field.id)
                VStack(alignment: .leading, spacing: 3) {
                    TextField(
                        "",
                        text: Binding(
                            get: { form.textValue(for: field.id) },
                            set: { form.setText(fieldID: field.id, value: $0) }
                        )
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(hasError ? Color.red : Color.primary.opacity(0.14), lineWidth: hasError ? 1.2 : 1)
                    )
                    .onSubmit {
                        submitIfValid()
                    }
                    if hasError {
                        Text(field.type == .integer ? strings.invalidInteger : strings.invalidNumber)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.red)
                    }
                }
            }
        }
    }

    private func optionRow(
        fieldID: String,
        option: AgentQuestion.Option,
        index: Int,
        isMulti: Bool,
        isSelected: Bool,
        showsShortcut: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let rowKey = "\(fieldID):\(option.value)"
        let trimmedDesc = option.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let showDescription = !trimmedDesc.isEmpty && trimmedDesc != option.label
        return Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    if isMulti {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isSelected ? VitruvianCodeTheme.warmCoral : Color.primary.opacity(0.04))
                            .frame(width: 14, height: 14)
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isSelected ? VitruvianCodeTheme.warmCoral : Color.primary.opacity(0.45), lineWidth: 1)
                            .frame(width: 14, height: 14)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                    } else {
                        Circle()
                            .fill(isSelected ? VitruvianCodeTheme.warmCoral : Color.primary.opacity(0.04))
                            .frame(width: 14, height: 14)
                        Circle()
                            .strokeBorder(isSelected ? VitruvianCodeTheme.warmCoral : Color.primary.opacity(0.45), lineWidth: 1)
                            .frame(width: 14, height: 14)
                        if isSelected {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 5, height: 5)
                        }
                    }
                }
                .frame(height: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if showDescription {
                        Text(trimmedDesc)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsShortcut {
                    Text("\(index + 1)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 16, minHeight: 16)
                        .padding(.horizontal, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.primary.opacity(0.08) : (hoveredRow == rowKey ? Color.primary.opacity(0.04) : Color.clear))
            )
            .contentShape(Rectangle())
            .opacity(isSelected ? 1.0 : 0.7)
        }
        .buttonStyle(.plain)
        .onHover { hoveredRow = $0 ? rowKey : nil }
    }

    private var footerButtons: some View {
        let canSend = form.canSubmit
        return HStack(spacing: 8) {
            Button {
                onSkip()
            } label: {
                Text(strings.skipQuestion)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(hoveredButton == "skip" ? 0.12 : 0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                    )
                    .foregroundStyle(Color.primary.opacity(0.9))
            }
            .buttonStyle(.plain)
            .onHover { hoveredButton = $0 ? "skip" : nil }

            Button {
                submitIfValid()
            } label: {
                Text(strings.send)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(canSend
                                ? (hoveredButton == "send" ? VitruvianCodeTheme.warmCoralLight : VitruvianCodeTheme.warmCoral)
                                : Color.primary.opacity(0.08))
                    )
                    .foregroundStyle(canSend ? Color.white : Color.primary.opacity(0.35))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .onHover { hoveredButton = $0 ? "send" : nil }

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func answeredSummaryView(answers: [String: String]) -> some View {
        let rows = AgentQuestionForm.summaryRows(for: question, answers: answers, strings: strings)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 6) {
                        if let label = row.label {
                            Text("\(label):")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Text(row.value)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
        }
    }

    private func submitIfValid() {
        guard isPending, let answers = form.buildAnswers() else { return }
        onAnswer(answers)
    }
}

/// Captures digit `1`...`9` and `Return` shortcuts when the pending question card is active
/// and neither the composer nor a form text field has focus.
private struct FormCardKeyMonitor: NSViewRepresentable {
    let isActive: () -> Bool
    let onDigit: (Int) -> Void
    let onReturn: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.isActive = isActive
        view.onDigit = onDigit
        view.onReturn = onReturn
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.isActive = isActive
        nsView.onDigit = onDigit
        nsView.onReturn = onReturn
    }

    static func dismantleNSView(_ nsView: MonitorView, coordinator: ()) {
        nsView.stop()
    }

    final class MonitorView: NSView {
        var isActive: (() -> Bool)?
        var onDigit: ((Int) -> Void)?
        var onReturn: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      let window = self.window,
                      event.window === window,
                      self.isActive?() == true else {
                    return event
                }
                if window.firstResponder is NSText {
                    return event
                }
                let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                guard modifiers.isEmpty else { return event }
                if event.keyCode == 36 || event.keyCode == 76 {
                    self.onReturn?()
                    return nil
                }
                if let chars = event.charactersIgnoringModifiers,
                   chars.count == 1,
                   let digit = Int(chars),
                   (1...9).contains(digit) {
                    self.onDigit?(digit)
                    return nil
                }
                return event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}
