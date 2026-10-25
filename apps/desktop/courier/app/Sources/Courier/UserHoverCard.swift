// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// Popover card shown when hovering a message sender's avatar or name for 0.5s, or pressing ⌘⇧O.
public struct UserHoverCard: View {
    public let member: Member
    public let network: String
    public let sharedGroups: [PersonHit]
    @ObservedObject public var contactsBridge: ContactsBridge
    public var now: Date
    public var locale: Locale
    public var onMessage: () -> Void
    public var onSelectRoom: (String) -> Void
    public var onCopyHandle: ((String) -> Void)?

    @State private var showSaveForm: Bool
    @State private var givenName: String
    @State private var familyName: String
    @State private var phone: String
    @State private var email: String

    public init(
        member: Member,
        network: String,
        sharedGroups: [PersonHit] = [],
        contactsBridge: ContactsBridge,
        now: Date = Date(),
        locale: Locale = Locale(identifier: "en_US"),
        initialShowSaveForm: Bool = false,
        onMessage: @escaping () -> Void = {},
        onSelectRoom: @escaping (String) -> Void = { _ in },
        onCopyHandle: ((String) -> Void)? = nil
    ) {
        self.member = member
        self.network = network
        self.sharedGroups = sharedGroups
        self.contactsBridge = contactsBridge
        self.now = now
        self.locale = locale
        self.onMessage = onMessage
        self.onSelectRoom = onSelectRoom
        self.onCopyHandle = onCopyHandle

        let parts = member.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let defaultGiven = parts.first.map(String.init) ?? ""
        let defaultFamily = parts.count > 1 ? String(parts[1]) : ""
        let defaultPhone = member.identifiers.compactMap { id -> String? in
            guard ContactsBridge.normalizePhone(id) != nil else { return nil }
            return ContactsBridge.displayIdentifier(id)
        }.first ?? ""
        let defaultEmail = member.identifiers.compactMap { id -> String? in
            guard ContactsBridge.normalizeEmail(id) != nil else { return nil }
            return ContactsBridge.displayIdentifier(id)
        }.first ?? ""

        self._showSaveForm = State(initialValue: initialShowSaveForm)
        self._givenName = State(initialValue: defaultGiven)
        self._familyName = State(initialValue: defaultFamily)
        self._phone = State(initialValue: defaultPhone)
        self._email = State(initialValue: defaultEmail)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            identifiersSection
            if let tzText = ChatInfoPane.localTimeText(for: member.tz, now: now, locale: locale) {
                timezoneRow(tzText)
            }
            primaryActionsRow
            if !sharedGroups.isEmpty {
                Divider()
                sharedGroupsSection
            }
            Divider()
            contactsSection
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack(spacing: 12) {
            avatarView
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let networkTitle = NetworkNames.displayName(of: network) ?? (network.isEmpty ? nil : network) {
                        Text(networkTitle)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                    if member.isBot {
                        Text(String(localized: "Bot"))
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if !member.avatarPath.isEmpty, let image = NSImage(contentsOfFile: member.avatarPath) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 48, height: 48)
        }
    }

    private var identifiersSection: some View {
        let items = displayedIdentifiers
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { identifier in
                HStack(spacing: 6) {
                    Image(systemName: iconName(for: identifier))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text(ContactsBridge.displayIdentifier(identifier))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Button(String(localized: "Copy")) {
                        copyToPasteboard(ContactsBridge.displayIdentifier(identifier))
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                }
            }
        }
    }

    private func timezoneRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var primaryActionsRow: some View {
        HStack(spacing: 8) {
            Button(action: onMessage) {
                Label(String(localized: "Message"), systemImage: "bubble.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                copyToPasteboard(primaryHandle)
            } label: {
                Label(String(localized: "Copy Handle"), systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var sharedGroupsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Shared Groups"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(sharedGroups.prefix(5)), id: \.roomID) { group in
                Button {
                    onSelectRoom(group.roomID)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(group.roomName)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var contactsSection: some View {
        if let matched = contactsBridge.matchedContact {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(.green)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "In Contacts: \(matched.fullName)"))
                        .font(.caption.weight(.medium))
                    if !matched.organization.isEmpty {
                        Text(matched.organization)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        } else if contactsBridge.isAccessDenied {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(String(localized: "Contacts access is turned off in System Settings."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(String(localized: "Open System Settings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showSaveForm.toggle()
                } label: {
                    Label(String(localized: "Save to Contacts…"), systemImage: "person.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if showSaveForm {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            TextField(String(localized: "Given Name"), text: $givenName)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                            TextField(String(localized: "Family Name"), text: $familyName)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                        }
                        TextField(String(localized: "Phone"), text: $phone)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                        TextField(String(localized: "Email"), text: $email)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                        HStack(spacing: 6) {
                            Spacer(minLength: 0)
                            Button(String(localized: "Cancel")) {
                                showSaveForm = false
                            }
                            .controlSize(.small)
                            Button(String(localized: "Save")) {
                                Task {
                                    _ = try? await contactsBridge.saveContact(
                                        givenName: givenName,
                                        familyName: familyName,
                                        phone: phone.isEmpty ? nil : phone,
                                        email: email.isEmpty ? nil : email
                                    )
                                    showSaveForm = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(
                                givenName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    && familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                        }
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: - Helpers

    private var displayName: String {
        let trimmed = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? member.userID : trimmed
    }

    private var displayedIdentifiers: [String] {
        member.identifiers.isEmpty ? [member.userID] : member.identifiers
    }

    private var primaryHandle: String {
        ContactsBridge.displayIdentifier(member.identifiers.first ?? member.userID)
    }

    private func iconName(for raw: String) -> String {
        if ContactsBridge.normalizePhone(raw) != nil {
            return "phone"
        }
        if ContactsBridge.normalizeEmail(raw) != nil {
            return "envelope"
        }
        return "at"
    }

    private func copyToPasteboard(_ value: String) {
        if let onCopyHandle {
            onCopyHandle(value)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
