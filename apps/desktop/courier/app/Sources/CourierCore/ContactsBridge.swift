// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Contacts
import Foundation

public enum ContactsAuthStatus: String, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

public struct MatchedContact: Equatable, Sendable {
    public let contactIdentifier: String
    public let fullName: String
    public let organization: String
    public let phones: [String]
    public let emails: [String]

    public init(
        contactIdentifier: String,
        fullName: String,
        organization: String = "",
        phones: [String] = [],
        emails: [String] = []
    ) {
        self.contactIdentifier = contactIdentifier
        self.fullName = fullName
        self.organization = organization
        self.phones = phones
        self.emails = emails
    }
}

public enum ContactsBridgeError: LocalizedError, Equatable, Sendable {
    case accessDenied

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            String(localized: "Contacts access is turned off in System Settings.")
        }
    }
}

public protocol ContactsStoreProtocol: Sendable {
    func authorizationStatus() -> ContactsAuthStatus
    func requestAccess() async -> Bool
    func match(identifiers: [String], fallbackName: String) async -> MatchedContact?
    func saveNewContact(givenName: String, familyName: String, phone: String?, email: String?) async throws -> MatchedContact
}

/// The active sender hover card shown in a conversation (opened after 0.5s of steady hover or via ⌘⇧O).
public struct SenderHoverCardState: Equatable, Sendable {
    public let messageID: String
    public let userID: String
    public let member: Member
    public let network: String

    public init(messageID: String, userID: String, member: Member, network: String) {
        self.messageID = messageID
        self.userID = userID
        self.member = member
        self.network = network
    }
}

/// On-demand bridge to macOS Contacts.framework.
///
/// Contacts access is requested only when the user opens a hover card's Contacts section or saves a contact,
/// never at launch. If denied or restricted, it never prompts again. Contact data stays strictly on-device
/// for matching and display and is never sent to the Courier engine or any network.
@MainActor
public final class ContactsBridge: ObservableObject {
    @Published public private(set) var status: ContactsAuthStatus
    @Published public private(set) var matchedContact: MatchedContact?
    @Published public private(set) var lastError: String?

    private let store: ContactsStoreProtocol

    public init(store: ContactsStoreProtocol = SystemContactsStore()) {
        self.store = store
        self.status = store.authorizationStatus()
    }

    public var isAccessDenied: Bool {
        status == .denied || status == .restricted
    }

    /// Normalizes a phone number or `tel:` URI to E.164 (`+` followed by country code and subscriber digits).
    /// Returns `nil` if the input is not an E.164 phone number.
    nonisolated public static func normalizePhone(_ raw: String) -> String? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("tel:") {
            trimmed = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard trimmed.hasPrefix("+") else { return nil }
        var digits = ""
        for ch in trimmed.dropFirst() {
            if ch.isASCII && ch.isNumber {
                digits.append(ch)
            } else if ch == " " || ch == "-" || ch == "(" || ch == ")" || ch == "." || ch == "\u{00A0}" || ch == "\u{202F}" || ch == "\t" {
                continue
            } else {
                return nil
            }
        }
        guard digits.count >= 2 else { return nil }
        return "+" + digits
    }

    /// Normalizes an email address or `mailto:` URI to lowercase.
    /// Returns `nil` for Matrix IDs (`@user:domain`) or non-email handles.
    nonisolated public static func normalizeEmail(_ raw: String) -> String? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("mailto:") {
            trimmed = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("@"),
              !trimmed.contains(" "),
              let atIndex = trimmed.firstIndex(of: "@"),
              atIndex > trimmed.startIndex,
              trimmed.index(after: atIndex) < trimmed.endIndex
        else {
            return nil
        }
        return trimmed.lowercased()
    }

    /// Compares candidate identifiers against a contact's phones and emails using whole-number E.164 equality
    /// (never suffixes) and case-insensitive email equality.
    nonisolated public static func matches(identifiers: [String], phones: [String], emails: [String]) -> Bool {
        let queryPhones = Set(identifiers.compactMap(normalizePhone))
        let queryEmails = Set(identifiers.compactMap(normalizeEmail))
        if !queryPhones.isEmpty {
            let contactPhones = Set(phones.compactMap(normalizePhone))
            if !queryPhones.isDisjoint(with: contactPhones) {
                return true
            }
        }
        if !queryEmails.isEmpty {
            let contactEmails = Set(emails.compactMap(normalizeEmail))
            if !queryEmails.isDisjoint(with: contactEmails) {
                return true
            }
        }
        return false
    }

    /// Formats a raw identifier (`tel:+15550100101`, `mailto:alice@example.com`, `@alice`) for display.
    /// Formats NANP E.164 phone numbers (`+15550100101`) as `+1 555-010-0101` so the hover card and Chat Info match.
    nonisolated public static func displayIdentifier(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("tel:") {
            trimmed = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if trimmed.lowercased().hasPrefix("mailto:") {
            return String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let e164 = normalizePhone(trimmed), e164.count == 12, e164.hasPrefix("+1") {
            let digits = Array(e164.dropFirst(2))
            let area = String(digits[0 ..< 3])
            let exchange = String(digits[3 ..< 6])
            let subscriber = String(digits[6 ..< 10])
            return "+1 \(area)-\(exchange)-\(subscriber)"
        }
        return trimmed
    }

    /// Requests Contacts access on demand if `.notDetermined`, or immediately resolves a match if `.authorized`.
    /// Never prompts if `.denied` or `.restricted`.
    public func loadMatch(identifiers: [String], fallbackName: String) async {
        guard AppLockGate.shared.canPerform(.other) else { return }
        lastError = nil
        status = store.authorizationStatus()
        switch status {
        case .notDetermined:
            let granted = await store.requestAccess()
            let updated = store.authorizationStatus()
            status = updated == .notDetermined ? (granted ? .authorized : .denied) : updated
            if status == .authorized {
                matchedContact = await store.match(identifiers: identifiers, fallbackName: fallbackName)
            } else {
                matchedContact = nil
            }
        case .authorized:
            matchedContact = await store.match(identifiers: identifiers, fallbackName: fallbackName)
        case .denied, .restricted:
            matchedContact = nil
        }
    }

    /// Saves a new contact on demand and updates `matchedContact`.
    @discardableResult
    public func saveContact(
        givenName: String,
        familyName: String,
        phone: String?,
        email: String?
    ) async throws -> MatchedContact {
        try AppLockGate.shared.ensureUnlocked(.other)
        lastError = nil
        status = store.authorizationStatus()
        if status == .notDetermined {
            let granted = await store.requestAccess()
            let updated = store.authorizationStatus()
            status = updated == .notDetermined ? (granted ? .authorized : .denied) : updated
        }
        guard status == .authorized else {
            throw ContactsBridgeError.accessDenied
        }
        do {
            let saved = try await store.saveNewContact(
                givenName: givenName,
                familyName: familyName,
                phone: phone,
                email: email
            )
            matchedContact = saved
            return saved
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }
}

/// Production `ContactsStoreProtocol` backed by macOS `CNContactStore`.
public struct SystemContactsStore: ContactsStoreProtocol {
    public init() {}

    public func authorizationStatus() -> ContactsAuthStatus {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    public func requestAccess() async -> Bool {
        let store = CNContactStore()
        return (try? await store.requestAccess(for: .contacts)) ?? false
    }

    public func match(identifiers: [String], fallbackName: String) async -> MatchedContact? {
        guard authorizationStatus() == .authorized else { return nil }
        return await Task.detached {
            let store = CNContactStore()
            let keys: [CNKeyDescriptor] = [
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor,
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            ]

            for identifier in identifiers {
                if let normalizedPhone = ContactsBridge.normalizePhone(identifier) {
                    let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: normalizedPhone))
                    if let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keys) {
                        for cn in contacts {
                            let phones = cn.phoneNumbers.map(\.value.stringValue)
                            if ContactsBridge.matches(identifiers: [normalizedPhone], phones: phones, emails: []) {
                                return Self.makeMatchedContact(from: cn, fallbackName: fallbackName)
                            }
                        }
                    }
                }
                if let normalizedEmail = ContactsBridge.normalizeEmail(identifier) {
                    let predicate = CNContact.predicateForContacts(matchingEmailAddress: normalizedEmail)
                    if let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keys) {
                        for cn in contacts {
                            let emails = cn.emailAddresses.map { $0.value as String }
                            if ContactsBridge.matches(identifiers: [normalizedEmail], phones: [], emails: emails) {
                                return Self.makeMatchedContact(from: cn, fallbackName: fallbackName)
                            }
                        }
                    }
                }
            }
            return nil
        }.value
    }

    public func saveNewContact(
        givenName: String,
        familyName: String,
        phone: String?,
        email: String?
    ) async throws -> MatchedContact {
        try await Task.detached {
            let mutable = CNMutableContact()
            mutable.givenName = givenName.trimmingCharacters(in: .whitespacesAndNewlines)
            mutable.familyName = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
            var savedPhones: [String] = []
            if let phone = phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
                let cleanPhone = phone.lowercased().hasPrefix("tel:")
                    ? String(phone.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                    : phone
                mutable.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: cleanPhone))]
                savedPhones.append(cleanPhone)
            }
            var savedEmails: [String] = []
            if let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
                let cleanEmail = ContactsBridge.displayIdentifier(email)
                mutable.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: cleanEmail as NSString)]
                savedEmails.append(cleanEmail)
            }
            let saveRequest = CNSaveRequest()
            saveRequest.add(mutable, toContainerWithIdentifier: nil)
            let store = CNContactStore()
            try store.execute(saveRequest)

            let fullName = [mutable.givenName, mutable.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return MatchedContact(
                contactIdentifier: mutable.identifier,
                fullName: fullName,
                organization: mutable.organizationName,
                phones: savedPhones,
                emails: savedEmails
            )
        }.value
    }

    private static func makeMatchedContact(from cn: CNContact, fallbackName: String) -> MatchedContact {
        let formatted = CNContactFormatter.string(from: cn, style: .fullName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let manual = [cn.givenName, cn.familyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let fullName = (formatted?.isEmpty == false ? formatted! : (manual.isEmpty ? fallbackName : manual))
        return MatchedContact(
            contactIdentifier: cn.identifier,
            fullName: fullName,
            organization: cn.organizationName,
            phones: cn.phoneNumbers.map(\.value.stringValue),
            emails: cn.emailAddresses.map { $0.value as String }
        )
    }
}

/// In-memory `ContactsStoreProtocol` for unit and snapshot tests. Never touches macOS `CNContactStore`.
public final class FakeContactsStore: ContactsStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _status: ContactsAuthStatus
    private let _requestGrantResult: Bool
    private var _contacts: [MatchedContact]
    private var _requestAccessCalls = 0

    public init(
        status: ContactsAuthStatus = .authorized,
        requestGrantResult: Bool = true,
        contacts: [MatchedContact] = []
    ) {
        self._status = status
        self._requestGrantResult = requestGrantResult
        self._contacts = contacts
    }

    public var requestAccessCalls: Int {
        lock.withLock { _requestAccessCalls }
    }

    public var contacts: [MatchedContact] {
        lock.withLock { _contacts }
    }

    public func authorizationStatus() -> ContactsAuthStatus {
        lock.withLock { _status }
    }

    public func requestAccess() async -> Bool {
        lock.withLock {
            _requestAccessCalls += 1
            _status = _requestGrantResult ? .authorized : .denied
            return _requestGrantResult
        }
    }

    public func match(identifiers: [String], fallbackName: String) async -> MatchedContact? {
        let snapshot = lock.withLock { (_status, _contacts) }
        guard snapshot.0 == .authorized else { return nil }
        for contact in snapshot.1 {
            if ContactsBridge.matches(identifiers: identifiers, phones: contact.phones, emails: contact.emails) {
                return contact
            }
        }
        return nil
    }

    public func saveNewContact(
        givenName: String,
        familyName: String,
        phone: String?,
        email: String?
    ) async throws -> MatchedContact {
        try lock.withLock {
            guard _status == .authorized else {
                throw ContactsBridgeError.accessDenied
            }
            let cleanGiven = givenName.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanFamily = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
            let fullName = [cleanGiven, cleanFamily].filter { !$0.isEmpty }.joined(separator: " ")
            var phones: [String] = []
            if let phone = phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
                let cleanPhone = phone.lowercased().hasPrefix("tel:")
                    ? String(phone.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                    : phone
                phones.append(cleanPhone)
            }
            var emails: [String] = []
            if let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
                emails.append(ContactsBridge.displayIdentifier(email))
            }
            let created = MatchedContact(
                contactIdentifier: "fake-contact-\(_contacts.count + 1)",
                fullName: fullName,
                organization: "",
                phones: phones,
                emails: emails
            )
            _contacts.append(created)
            return created
        }
    }
}
