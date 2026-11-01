// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// What a label window is for: a new label (put on `applyTo` once made, when a chat's menu asked for it), or
/// changing one.
enum LabelWindowTarget: Codable, Hashable {
    case new(applyTo: [String])
    case edit(labelID: Int64)
}

/// The scene ids of the windows these views open.
enum WindowID {
    static let editSpaces = "edit-spaces"
    static let label = "label"
    static let editLabels = "edit-labels"
    static let autoArchive = "auto-archive"
    static let chatInfo = "chat-info"
    static let mediaViewer = "media-viewer"
}

/// Making or changing a label: its title, a colour and an icon, and for a label that exists, its auto-archive
/// rule.
struct LabelEditorWindow: View {
    let target: LabelWindowTarget
    @ObservedObject var labels: LabelsModel
    @ObservedObject var spaces: SpacesModel
    let inbox: InboxModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var color = 7
    @State private var icon = LabelsModel.icons[0]
    @State private var problem: String?
    @State private var saving = false
    @FocusState private var titleFocused: Bool

    private var existing: Space? {
        guard case let .edit(id) = target else { return nil }
        return spaces.spaces.first { $0.kind == .label && $0.labelID == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Pick a name, a colour and an icon. This is how the label looks everywhere in Courier."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                LabelIcon(color: color, icon: icon, size: 28)
                TextField(String(localized: "Title"), text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($titleFocused)
                    .onSubmit(save)
                    .onChange(of: title) { _, new in title = Self.limited(new) }
            }
            IconColorPicker(color: $color, icon: $icon)
            if case let .edit(id) = target {
                Divider()
                AutoArchiveSection(spaceID: "label:\(id)", labels: labels, inbox: inbox)
            }
            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? String(localized: "Create Label") : String(localized: "Save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(LabelsModel.clean(title).isEmpty || saving)
            }
        }
        .padding(20)
        .frame(width: 400)
        // The auto-archive section's Undo shows here, where its button is.
        .overlay(alignment: .bottom) { ToastView(inbox: inbox) }
        .navigationTitle(isNew ? String(localized: "New Label") : String(localized: "Edit Label"))
        .onAppear(perform: fill)
        .onChange(of: existing?.labelID) { _, _ in fill() }
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    /// A label being changed starts as it is.
    private func fill() {
        titleFocused = true
        guard let existing, title.isEmpty else { return }
        title = existing.title
        color = existing.color
        icon = CourierIconCatalog.allowedLabelSFSymbols.contains(existing.icon) ? existing.icon : LabelsModel.icons[0]
    }

    /// The field takes no more than the engine does: 40 letters (counted as the engine counts them).
    static func limited(_ text: String) -> String {
        var text = text
        while text.unicodeScalars.count > LabelsModel.maxTitle { text.removeLast() }
        return text
    }

    private func save() {
        guard !LabelsModel.clean(title).isEmpty, !saving else { return }
        saving = true
        problem = nil
        Task {
            defer { saving = false }
            do {
                switch target {
                case let .new(applyTo):
                    let id = try await labels.create(title: title, color: color, icon: icon)
                    if !applyTo.isEmpty { await inbox.setLabel(id, on: true, ids: applyTo) }
                case let .edit(id):
                    try await labels.update(id, title: title, color: color, icon: icon)
                }
                dismiss()
            } catch {
                problem = EngineErrorText.text(for: error, fallback: String(localized: "That didn’t work. Try again."))
            }
        }
    }
}

/// A label's mark: its icon in its colour.
struct LabelIcon: View {
    let color: Int
    let icon: String
    let size: CGFloat

    var body: some View {
        Image(systemName: icon.isEmpty ? "tag" : icon)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28).fill(LabelColor.color(color)))
            .accessibilityHidden(true)
    }
}

/// Nudge badge shown in `EditLabelsWindow`'s empty state (`CreateLabelNudgeIcon.tsx`).
public struct CreateLabelNudgeIcon: View {
    public init() {}

    public var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 48, height: 48)
            Image(systemName: "tag.circle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .accessibilityHidden(true)
    }
}

/// Every label, to change or delete, and a button for a new one.
struct EditLabelsWindow: View {
    @ObservedObject var spaces: SpacesModel
    let labels: LabelsModel
    @Environment(\.openWindow) private var openWindow

    private var labelSpaces: [Space] { spaces.spaces.filter { $0.kind == .label } }

    var body: some View {
        VStack(spacing: 0) {
            if labelSpaces.isEmpty {
                VStack(spacing: 8) {
                    CreateLabelNudgeIcon()
                    Text(String(localized: "No labels yet"))
                        .font(.headline)
                    Text(String(localized: "A label groups chats from any network into a space of its own."))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(labelSpaces) { space in
                    HStack(spacing: 10) {
                        LabelIcon(color: space.color, icon: space.icon, size: 24)
                        Text(space.title)
                            .lineLimit(1)
                        Spacer()
                        Text(ChatCount.chats(space.chats))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Button(String(localized: "Edit…")) {
                            openWindow(id: WindowID.label, value: LabelWindowTarget.edit(labelID: space.labelID))
                        }
                        Button(String(localized: "Delete…")) {
                            Task { await LabelDeletion.confirmAndDelete(space.labelID, labels: labels) }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button(String(localized: "New Label…")) {
                    openWindow(id: WindowID.label, value: LabelWindowTarget.new(applyTo: []))
                }
            }
            .padding(12)
        }
        .frame(minWidth: 380, minHeight: 300)
    }
}

/// "Delete this label?": a label deleted comes off every chat, and its space and rule go with it.
@MainActor
enum LabelDeletion {
    static func confirmAndDelete(_ labelID: Int64, labels: LabelsModel) async {
        guard Confirm.ask(String(localized: "Delete this label?"),
                          detail: String(localized: "It comes off every chat. The chats stay."),
                          action: String(localized: "Delete Label"), destructive: true) else { return }
        do {
            try await labels.delete(labelID)
        } catch {
            Confirm.tell(EngineErrorText.text(for: error, fallback: String(localized: "That didn’t work. Try again.")))
        }
    }
}

/// How many chats, as the space bar and the label list say it.
enum ChatCount {
    static func chats(_ count: Int) -> String {
        count == 1 ? String(localized: "1 chat") : String(localized: "\(count) chats")
    }

    static func reminders(_ count: Int) -> String {
        count == 1 ? String(localized: "1 reminder") : String(localized: "\(count) reminders")
    }

    static func requests(_ count: Int) -> String {
        count == 1 ? String(localized: "1 request") : String(localized: "\(count) requests")
    }
}

/// The ages a sweep takes, as the pickers say them.
enum SweepAge {
    static func text(days: Int) -> String {
        switch days {
        case 7: String(localized: "1 week")
        case 14: String(localized: "2 weeks")
        case 28: String(localized: "4 weeks")
        case 90: String(localized: "3 months")
        case 365: String(localized: "1 year")
        default: String(localized: "\(days) days")
        }
    }
}

/// "Archive [all / read] chats older than [3 days … 1 year]": the picker pair the auto-archive section and the
/// archive-all tool share.
struct SweepChoice: View {
    @Binding var readOnly: Bool
    @Binding var days: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(String(localized: "Archive"))
            Picker(String(localized: "Which chats"), selection: $readOnly) {
                Text(String(localized: "all")).tag(false)
                Text(String(localized: "read")).tag(true)
            }
            .labelsHidden()
            .fixedSize()
            Text(String(localized: "chats older than"))
            Picker(String(localized: "Age"), selection: $days) {
                ForEach(LabelsModel.sweepAges, id: \.self) { Text(SweepAge.text(days: $0)).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// How many chats match a sweep now, and the button that archives them: "3 chats here already match this rule."
/// and "Archive 3 chats". Nil is "Couldn't check"; none shows nothing.
struct SweepCount: View {
    let count: Int?
    let rule: Bool
    let archive: () -> Void

    var body: some View {
        switch count {
        case nil:
            Text(String(localized: "Couldn’t check"))
                .font(.callout)
                .foregroundStyle(.secondary)
        case 0?:
            EmptyView()
        case let count?:
            HStack {
                if rule {
                    Text(count == 1 ? String(localized: "1 chat here already matches this rule.")
                        : String(localized: "\(count) chats here already match this rule."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button(count == 1 ? String(localized: "Archive 1 chat") : String(localized: "Archive \(count) chats"),
                       action: archive)
            }
        }
    }
}

/// A label's or an account's auto-archive rule: archive its chats once their newest message is old enough, with
/// how many already are and a button that archives those now.
struct AutoArchiveSection: View {
    let spaceID: String
    @ObservedObject var labels: LabelsModel
    let inbox: InboxModel

    @State private var enabled = false
    @State private var readOnly = false
    @State private var days = 28
    @State private var count: Int?
    @State private var counted = false
    @State private var problem: String?
    /// The controls as they were last filled in from the rule: only a change from these is the person's, and saved.
    @State private var filled: Choice?

    private struct Choice: Equatable {
        let enabled: Bool
        let readOnly: Bool
        let days: Int
    }

    private var choice: Choice { Choice(enabled: enabled, readOnly: readOnly, days: days) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Auto-archive"))
                .font(.subheadline.weight(.semibold))
            if labels.canAutoArchive {
                Toggle(isOn: $enabled) {
                    SweepChoice(readOnly: $readOnly, days: $days)
                }
                .help(String(localized: "Courier archives chats here by itself once their newest message is this old. They come back when someone writes."))
            } else {
                Text(String(localized: "Available with a plan"))
                    .foregroundStyle(.secondary)
            }
            if counted {
                SweepCount(count: count, rule: true) {
                    Task {
                        await Confirm.sweep(inbox, readOnly: readOnly, olderThanDays: days, space: spaceID)
                        await recount()
                    }
                }
            }
            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .onAppear(perform: fill)
        .onChange(of: labels.rules(for: spaceID)) { _, _ in fill() }
        .onChange(of: enabled) { _, _ in save() }
        .onChange(of: readOnly) { _, _ in save() }
        .onChange(of: days) { _, _ in save() }
        .task(id: "\(readOnly)|\(days)") { await recount() }
    }

    /// The controls start as the rule is (with none, off, all chats, four weeks). An age the picker doesn't offer
    /// shows as the nearest one it does, and the rule is left as it is until the person changes something.
    private func fill() {
        if let rule = labels.rules(for: spaceID) {
            enabled = rule.enabled
            readOnly = rule.chatType == .read
            days = LabelsModel.nearestSweepAge(Int(rule.durationMS / 86_400_000))
        }
        filled = choice
    }

    /// A change the person made is saved at once. Showing the section never writes: filling the controls in from
    /// the rule is no change.
    private func save() {
        guard choice != filled, labels.rules(for: spaceID) != nil || enabled, labels.canAutoArchive else { return }
        filled = choice
        problem = nil
        Task {
            do {
                try await labels.setSweep(for: spaceID, chatType: readOnly ? .read : .all, days: days, enabled: enabled)
            } catch {
                problem = EngineErrorText.text(for: error, fallback: String(localized: "That didn’t work. Try again."))
            }
        }
    }

    private func recount() async {
        count = await inbox.archiveAllCount(readOnly: readOnly, olderThanDays: days, space: spaceID)
        counted = true
    }
}

/// An account's auto-archive rule, in a window of its own (the account's menu opens it).
struct AutoArchiveWindow: View {
    let spaceID: String
    @ObservedObject var spaces: SpacesModel
    let labels: LabelsModel
    let inbox: InboxModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AutoArchiveSection(spaceID: spaceID, labels: labels, inbox: inbox)
        }
        .padding(20)
        .frame(width: 440)
        .frame(minHeight: 180, alignment: .top)
        .overlay(alignment: .bottom) { ToastView(inbox: inbox) }
        .navigationTitle(spaces.spaces.first { $0.spaceID == spaceID }?.title ?? String(localized: "Auto-archive"))
    }
}
