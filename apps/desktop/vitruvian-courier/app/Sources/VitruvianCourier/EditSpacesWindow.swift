// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// Edit Spaces: the bar's order and what it hides. Drag a space to reorder it, below "Hidden" to hide it (or use
/// its eye button). The inbox stays first. Each change is saved at once, and the inbox says "Sidebar updated".
struct EditSpacesWindow: View {
    @ObservedObject var spaces: SpacesModel
    /// Its toast says "Sidebar updated" here too, where the person is looking.
    let inbox: InboxModel
    @State private var draft = SpacesLayoutDraft(spaces: [])
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField(String(localized: "Search Spaces"), text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            List {
                ForEach(shownEntries, id: \.self) { entry in
                    row(entry)
                }
                .onMove(perform: search.isEmpty ? move : nil)
            }
            .listStyle(.inset)
            Text(String(localized: "Drag a space to change its place, or below Hidden to take it off the bar."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
        }
        .frame(minWidth: 320, minHeight: 420)
        .overlay(alignment: .bottom) { ToastView(inbox: inbox) }
        .onAppear {
            spaces.isEditing = true
            draft = SpacesLayoutDraft(spaces: spaces.spaces)
        }
        .onDisappear { spaces.isEditing = false }
        .onChange(of: spaces.spaces) { _, new in draft = SpacesLayoutDraft(spaces: new) }
    }

    /// While searching, only the spaces that match (and nothing can be dragged).
    private var shownEntries: [SpacesLayoutDraft.Entry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        var entries = draft.entries
        if draft.hidden.isEmpty, let divider = entries.firstIndex(of: .divider) {
            entries.insert(.space(Self.noHidden), at: divider + 1)
        }
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            guard case let .space(id) = entry, let space = space(id) else { return false }
            return SpaceLook.title(space).localizedCaseInsensitiveContains(query)
        }
    }

    /// The placeholder row under the divider when nothing is hidden.
    private static let noHidden = "\u{0}no-hidden"

    @ViewBuilder
    private func row(_ entry: SpacesLayoutDraft.Entry) -> some View {
        switch entry {
        case .divider:
            HStack {
                Text(String(localized: "Hidden"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack { Divider() }
            }
            .moveDisabled(true)
        case let .space(id) where id == Self.noHidden:
            Text(String(localized: "No hidden spaces"))
                .foregroundStyle(.secondary)
                .moveDisabled(true)
        case let .space(id):
            if let space = space(id) {
                HStack(spacing: 10) {
                    icon(space)
                        .frame(width: 22, height: 22)
                    Text(SpaceLook.title(space))
                    Spacer()
                    if id != "inbox" {
                        let hidden = draft.isHidden(id)
                        Button {
                            draft.setHidden(id, !hidden)
                            save()
                        } label: {
                            Image(systemName: hidden ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(hidden ? String(localized: "Show on the bar") : String(localized: "Hide from the bar"))
                    }
                }
                .moveDisabled(id == "inbox")
            }
        }
    }

    @ViewBuilder
    private func icon(_ space: Space) -> some View {
        switch space.kind {
        case .account: NetworkBadge(network: space.network, name: space.title, size: 18)
        case .label: LabelIcon(color: space.color, icon: space.icon, size: 20)
        default: Image(systemName: SpaceLook.symbol(space.spaceID)).foregroundStyle(.secondary)
        }
    }

    private func space(_ id: String) -> Space? { spaces.spaces.first { $0.spaceID == id } }

    private func move(_ source: IndexSet, _ destination: Int) {
        // The "No hidden spaces" row is in the list but not in the draft: it sits right after the divider, so a
        // place after it is one place earlier in the draft (and dropping on either side of it hides).
        let placeholder = shownEntries.firstIndex(of: .space(Self.noHidden))
        let toDraft = { (index: Int) in placeholder.map { index > $0 ? index - 1 : index } ?? index }
        var next = draft
        next.move(fromOffsets: IndexSet(source.map(toDraft)), toOffset: toDraft(destination))
        guard next != draft else { return }
        draft = next
        save()
    }

    private func save() {
        let order = draft.order
        let hidden = draft.hidden
        Task { await spaces.saveLayout(order: order, hidden: hidden) }
    }
}
