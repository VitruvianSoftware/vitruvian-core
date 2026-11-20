// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// One person in New Chat, grouping every network endpoint that clearly belongs to the same person.
public struct ContactPersonGroup: Equatable, Hashable, Identifiable, Sendable {
    public var id: String { primary.id }
    public let primary: ContactCandidate
    public let endpoints: [ContactCandidate]
    public let isNamed: Bool

    public init(primary: ContactCandidate, endpoints: [ContactCandidate], isNamed: Bool) {
        self.primary = primary
        self.endpoints = endpoints
        self.isNamed = isNamed
    }

    public var isMultiNetwork: Bool { endpoints.count > 1 }

    public var displayName: String {
        let stripped = NetworkTag.stripped(primary.name).trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? primary.userID : stripped
    }

    public var avatarPath: String {
        if !primary.avatarPath.isEmpty {
            return primary.avatarPath
        }
        return endpoints.first(where: { !$0.avatarPath.isEmpty })?.avatarPath ?? ""
    }

    /// Distinct network IDs across `endpoints`, preserving endpoint order.
    public var networks: [String] {
        var seen = Set<String>()
        return endpoints.compactMap { seen.insert($0.network).inserted ? $0.network : nil }
    }
}

/// Groups New Chat candidates into one person row per person.
///
/// Merge rule: two candidates are grouped only when they are in the same merged chat, or share a normalized phone
/// number or email address. A number or address held by two or more differently named people (a family landline, a
/// shared inbox) links nobody. Display names alone never merge. Two endpoints with different user IDs are never
/// collapsed into one, even on the same account.
public enum ContactPersonGrouping {
    public struct GroupedSections: Equatable, Sendable {
        public var named: [ContactPersonGroup]
        public var other: [ContactPersonGroup]

        public init(named: [ContactPersonGroup], other: [ContactPersonGroup]) {
            self.named = named
            self.other = other
        }

        public var ordered: [ContactPersonGroup] { named + other }
    }

    /// Splits grouped contacts into named people (A–Z) followed by number/handle-only entries (A–Z).
    public static func sections(
        _ candidates: [ContactCandidate],
        mergedChats: [String: MergedChat] = [:],
        accountOrder: [String] = []
    ) -> GroupedSections {
        let groups = buildGroups(
            candidates,
            mergedChats: mergedChats,
            accountOrder: accountOrder
        ).map(\.group)
        let named = groups.filter(\.isNamed).sorted(by: alphabetical)
        let other = groups.filter { !$0.isNamed }.sorted(by: alphabetical)
        return GroupedSections(named: named, other: other)
    }

    /// Groups candidates into person rows while preserving the earliest candidate order (for Recent or typed search).
    public static func groupedPreservingOrder(
        _ candidates: [ContactCandidate],
        mergedChats: [String: MergedChat] = [:],
        accountOrder: [String] = []
    ) -> [ContactPersonGroup] {
        buildGroups(
            candidates,
            mergedChats: mergedChats,
            accountOrder: accountOrder
        )
        .sorted { lhs, rhs in
            if lhs.minIndex != rhs.minIndex {
                return lhs.minIndex < rhs.minIndex
            }
            return lhs.group.id < rhs.group.id
        }
        .map(\.group)
    }

    /// The primary displayable handle, phone number, or email for an endpoint sub-row.
    public static func handle(for endpoint: ContactCandidate) -> String? {
        if let first = ContactsBridge.displayableIdentifiers(endpoint.identifiers).first {
            let formatted = ContactsBridge.displayIdentifier(first)
            if !formatted.isEmpty { return formatted }
        }
        if ContactListOrdering.isNumberOrHandle(endpoint.name) {
            let stripped = NetworkTag.stripped(endpoint.name).trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty {
                let formatted = ContactsBridge.displayIdentifier(stripped)
                return formatted.isEmpty ? stripped : formatted
            }
        }
        return nil
    }

    // MARK: - Union-Find & Collapsing

    private struct RankedGroup {
        let minIndex: Int
        let group: ContactPersonGroup
    }

    private static func buildGroups(
        _ candidates: [ContactCandidate],
        mergedChats: [String: MergedChat],
        accountOrder: [String]
    ) -> [RankedGroup] {
        guard !candidates.isEmpty else { return [] }

        var roomToMergeID: [String: String] = [:]
        for (mergeID, merged) in mergedChats {
            for roomID in merged.roomIDs {
                roomToMergeID[roomID] = mergeID
            }
        }

        var parent = Array(candidates.indices)

        func find(_ x: Int) -> Int {
            var root = x
            while parent[root] != root {
                root = parent[root]
            }
            var curr = x
            while parent[curr] != root {
                let next = parent[curr]
                parent[curr] = root
                curr = next
            }
            return root
        }

        func union(_ a: Int, _ b: Int) {
            let ra = find(a)
            let rb = find(b)
            if ra != rb {
                parent[rb] = ra
            }
        }

        // A phone number or email address links candidates only when everyone who carries it could be one person.
        var holdersByKey: [String: [Int]] = [:]
        var keysByIndex: [[String]] = Array(repeating: [], count: candidates.count)
        for index in candidates.indices {
            let candidate = candidates[index]
            var keys: [String] = []
            for raw in [candidate.name] + candidate.identifiers {
                if let phoneKey = ContactListOrdering.phoneKey(raw) {
                    keys.append("phone:\(phoneKey)")
                }
                if let emailKey = ContactListOrdering.emailKey(raw) {
                    keys.append("email:\(emailKey)")
                }
            }
            for key in Set(keys) {
                holdersByKey[key, default: []].append(index)
            }
            keysByIndex[index] = Array(Set(keys))
        }
        var sharedKeys = Set<String>()
        for (key, holders) in holdersByKey where holders.count > 1 {
            let names = holders.map { candidates[$0].name }.filter { !ContactListOrdering.isNumberOrHandle($0) }
            if namesCouldBeOnePerson(names) {
                sharedKeys.insert(key)
            }
        }

        var firstIndexByKey: [String: Int] = [:]
        for index in candidates.indices {
            let candidate = candidates[index]
            var keys: [String] = keysByIndex[index].filter { sharedKeys.contains($0) }
            if let roomID = candidate.roomID, !roomID.isEmpty, let mergeID = roomToMergeID[roomID] {
                keys.append("merge:\(mergeID)")
            }
            for key in keys {
                if let existing = firstIndexByKey[key] {
                    union(existing, index)
                } else {
                    firstIndexByKey[key] = index
                }
            }
        }

        var componentIndicesByRoot: [Int: [Int]] = [:]
        var rootOrder: [Int] = []
        for index in candidates.indices {
            let root = find(index)
            if componentIndicesByRoot[root] == nil {
                rootOrder.append(root)
            }
            componentIndicesByRoot[root, default: []].append(index)
        }

        var accountRank: [String: Int] = [:]
        for (idx, net) in accountOrder.enumerated() where accountRank[net] == nil {
            accountRank[net] = idx
        }

        return rootOrder.compactMap { root -> RankedGroup? in
            guard let indices = componentIndicesByRoot[root], let minIndex = indices.min() else { return nil }
            let members = indices.map { candidates[$0] }
            let collapsed = collapseSameEndpoint(members)
            let sortedEndpoints = collapsed.sorted { lhs, rhs in
                let leftRank = accountRank[lhs.network] ?? Int.max
                let rightRank = accountRank[rhs.network] ?? Int.max
                if leftRank != rightRank { return leftRank < rightRank }
                if lhs.network != rhs.network { return lhs.network < rhs.network }
                if lhs.accountID != rhs.accountID { return lhs.accountID < rhs.accountID }
                return lhs.userID < rhs.userID
            }
            let primary = pickPrimary(from: sortedEndpoints) ?? sortedEndpoints[0]
            let isNamed = !ContactListOrdering.isNumberOrHandle(primary.name)
            return RankedGroup(
                minIndex: minIndex,
                group: ContactPersonGroup(primary: primary, endpoints: sortedEndpoints, isNamed: isNamed)
            )
        }
    }

    /// Every pair of names is the same or one is the other with more words ("Pat" and "Pat Lee"): not "Mom" and
    /// "Dad", the two people one family landline belongs to.
    private static func namesCouldBeOnePerson(_ names: [String]) -> Bool {
        let words = names.map { name in
            Set(
                NetworkTag.stripped(name)
                    .lowercased()
                    .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    .map(String.init)
            )
        }
        for i in words.indices {
            for j in words.indices where j > i {
                if !(words[i].isSubset(of: words[j]) || words[j].isSubset(of: words[i])) {
                    return false
                }
            }
        }
        return true
    }

    /// One bucket per candidate id (network, account and user ID): the same endpoint seen twice (in Recent and in
    /// Contacts, say) is one. Different user IDs on one account stay apart.
    private struct AccountBucketKey: Hashable {
        let id: String
    }

    private static func collapseSameEndpoint(_ members: [ContactCandidate]) -> [ContactCandidate] {
        var byAccount: [AccountBucketKey: [ContactCandidate]] = [:]
        var keyOrder: [AccountBucketKey] = []
        for candidate in members {
            let key = AccountBucketKey(id: candidate.id)
            if byAccount[key] == nil {
                keyOrder.append(key)
            }
            byAccount[key, default: []].append(candidate)
        }
        return keyOrder.compactMap { key -> ContactCandidate? in
            guard let group = byAccount[key], !group.isEmpty else { return nil }
            guard group.count > 1 else { return group[0] }
            let sorted = group.sorted(by: hasHigherEndpointPriority)
            var best = sorted[0]
            var seenIDs = Set<String>()
            var mergedIdentifiers: [String] = []
            for item in sorted {
                if best.avatarPath.isEmpty, !item.avatarPath.isEmpty {
                    best.avatarPath = item.avatarPath
                }
                if (best.roomID ?? "").isEmpty, let roomID = item.roomID, !roomID.isEmpty {
                    best.roomID = roomID
                }
                for raw in item.identifiers {
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, seenIDs.insert(trimmed).inserted else { continue }
                    mergedIdentifiers.append(raw)
                }
            }
            best.identifiers = mergedIdentifiers
            return best
        }
    }

    private static func pickPrimary(from sortedEndpoints: [ContactCandidate]) -> ContactCandidate? {
        sortedEndpoints.min(by: hasHigherPrimaryPriority)
    }

    private static func hasHigherEndpointPriority(_ lhs: ContactCandidate, _ rhs: ContactCandidate) -> Bool {
        let lhsNamed = !ContactListOrdering.isNumberOrHandle(lhs.name)
        let rhsNamed = !ContactListOrdering.isNumberOrHandle(rhs.name)
        if lhsNamed != rhsNamed { return lhsNamed }
        let lhsHasRoom = !(lhs.roomID ?? "").isEmpty
        let rhsHasRoom = !(rhs.roomID ?? "").isEmpty
        if lhsHasRoom != rhsHasRoom { return lhsHasRoom }
        let lhsHasAvatar = !lhs.avatarPath.isEmpty
        let rhsHasAvatar = !rhs.avatarPath.isEmpty
        if lhsHasAvatar != rhsHasAvatar { return lhsHasAvatar }
        if lhs.identifiers.count != rhs.identifiers.count {
            return lhs.identifiers.count > rhs.identifiers.count
        }
        return lhs.userID < rhs.userID
    }

    private static func hasHigherPrimaryPriority(_ lhs: ContactCandidate, _ rhs: ContactCandidate) -> Bool {
        let lhsNamed = !ContactListOrdering.isNumberOrHandle(lhs.name)
        let rhsNamed = !ContactListOrdering.isNumberOrHandle(rhs.name)
        if lhsNamed != rhsNamed { return lhsNamed }
        let lhsHasAvatar = !lhs.avatarPath.isEmpty
        let rhsHasAvatar = !rhs.avatarPath.isEmpty
        if lhsHasAvatar != rhsHasAvatar { return lhsHasAvatar }
        let lhsHasRoom = !(lhs.roomID ?? "").isEmpty
        let rhsHasRoom = !(rhs.roomID ?? "").isEmpty
        if lhsHasRoom != rhsHasRoom { return lhsHasRoom }
        return false
    }

    private static func alphabetical(_ lhs: ContactPersonGroup, _ rhs: ContactPersonGroup) -> Bool {
        let order = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if order != .orderedSame {
            return order == .orderedAscending
        }
        return lhs.id < rhs.id
    }
}

/// Which edges of a horizontally scrollable chip strip should render a fade mask.
public struct HorizontalOverflowEdges: Equatable, Sendable {
    public let leading: Bool
    public let trailing: Bool

    public init(leading: Bool, trailing: Bool) {
        self.leading = leading
        self.trailing = trailing
    }

    public var hasOverflow: Bool { leading || trailing }

    public static func compute(
        viewportWidth: Double,
        contentMinX: Double,
        contentMaxX: Double,
        tolerance: Double = 1.0
    ) -> HorizontalOverflowEdges {
        guard viewportWidth > 0 else {
            return HorizontalOverflowEdges(leading: false, trailing: false)
        }
        return HorizontalOverflowEdges(
            leading: contentMinX < -tolerance,
            trailing: contentMaxX > viewportWidth + tolerance
        )
    }
}

/// Trailing affordance displayed on a New Chat row.
public enum StartNewChatRowAffordance: Equatable, Sendable {
    case none
    case startChat
    case expand(isExpanded: Bool)
    case selectRecipient(isSelected: Bool)

    public static func forPersonRow(
        isMultiNetwork: Bool,
        isExpanded: Bool,
        isMultiSelectActive: Bool,
        allowsMultiSelect: Bool,
        isRecipientSelected: Bool,
        isHovered: Bool,
        isKeyboardSelected: Bool
    ) -> StartNewChatRowAffordance {
        if isMultiNetwork {
            return .expand(isExpanded: isExpanded)
        }
        if isMultiSelectActive {
            return allowsMultiSelect ? .selectRecipient(isSelected: isRecipientSelected) : .none
        }
        return (isHovered || isKeyboardSelected) ? .startChat : .none
    }

    public static func forEndpointSubRow(
        isMultiSelectActive: Bool,
        allowsMultiSelect: Bool,
        isRecipientSelected: Bool,
        isHovered: Bool,
        isKeyboardSelected: Bool
    ) -> StartNewChatRowAffordance {
        if isMultiSelectActive {
            return allowsMultiSelect ? .selectRecipient(isSelected: isRecipientSelected) : .none
        }
        return (isHovered || isKeyboardSelected) ? .startChat : .none
    }

    public static func forLookupRow(
        isHovered: Bool,
        isKeyboardSelected: Bool
    ) -> StartNewChatRowAffordance {
        (isHovered || isKeyboardSelected) ? .startChat : .none
    }
}
