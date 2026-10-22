// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

@MainActor
final class ForwardPickerModelTests: XCTestCase {
    private func rows(_ names: [String]) -> [InboxRow] {
        names.enumerated().map { chatRow("!\($0.offset)", name: $0.element) }
    }

    func testTypingFindsChatsAndAnOldAnswerIsDropped() async throws {
        let gate = AnswerGate()
        let asked = Asked()
        let model = ForwardPickerModel { text in
            asked.add(text)
            if text == "a" { await gate.wait() } // the first answer comes last
            return text.isEmpty ? [] : [chatRow("!\(text)", name: "Chat \(text)")]
        }
        model.query = "a"
        model.query = "ab"
        try await waitUntil { model.results.map(\.roomID) == ["!ab"] }
        await gate.open()
        try await waitUntil { model.answersSeen == 2 }
        XCTAssertEqual(asked.list, ["a", "ab"])
        XCTAssertEqual(model.results.map(\.roomID), ["!ab"], "the older answer, for \"a\", is dropped")
    }

    func testAtMostTwentyChatsAreChosen() {
        let model = ForwardPickerModel { _ in [] }
        let all = rows((0 ..< 21).map { "Chat \($0)" })
        for row in all.prefix(20) { XCTAssertTrue(model.toggle(row)) }
        XCTAssertTrue(model.isFull)
        XCTAssertFalse(model.toggle(all[20]), "a forward takes 20 chats at most")
        XCTAssertEqual(model.selected.count, 20)
        XCTAssertTrue(model.toggle(all[3]), "unchoosing one")
        XCTAssertFalse(model.isSelected(all[3]))
        XCTAssertTrue(model.toggle(all[20]))
    }
}

/// What the picker looked up.
@MainActor
private final class Asked {
    var list: [String] = []
    func add(_ text: String) { list.append(text) }
}

/// Holds a task until opened.
private actor AnswerGate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }
}
