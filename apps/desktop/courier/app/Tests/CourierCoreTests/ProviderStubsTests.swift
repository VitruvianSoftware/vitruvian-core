// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest

@testable import CourierCore

@MainActor
final class ProviderStubsTests: XCTestCase {
    private final class NetworkTrapURLProtocol: URLProtocol {
        nonisolated(unsafe) static var interceptedRequests: [URLRequest] = []

        override class func canInit(with request: URLRequest) -> Bool {
            interceptedRequests.append(request)
            return true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }

        override func stopLoading() {}
    }

    override func tearDown() async throws {
        AppLockGate.shared.resetForTesting()
    }

    func testAllFiveProviderStubsAreCalmOfflineAndNeverSayBeeper() async throws {
        NetworkTrapURLProtocol.interceptedRequests = []
        URLProtocol.registerClass(NetworkTrapURLProtocol.self)
        defer { URLProtocol.unregisterClass(NetworkTrapURLProtocol.self) }

        // 1. UnavailableAIProvider
        let ai: any AIProvider = UnavailableAIProvider()
        XCTAssertFalse(ai.isAvailable)
        XCTAssertTrue(ai.unavailableReason.contains("Courier"))
        XCTAssertFalse(ai.unavailableReason.localizedCaseInsensitiveContains("Beeper"))
        XCTAssertFalse(ai.availableModels.isEmpty)

        let draftDisp = await ai.draftResponse(roomID: "!r1:courier.local", prompt: "Summarize", tone: .moreConcise)
        let translateDisp = await ai.translate(text: "Bonjour", targetLanguage: "English")
        let summarizeDisp = await ai.summarize(roomID: "!r1:courier.local", eventIDs: ["$e1"])
        let transcribeDisp = await ai.transcribeVoiceNote(roomID: "!r1:courier.local", eventID: "$e1")
        let talkDisp = await ai.startTalkToType()

        for disp in [draftDisp, translateDisp, summarizeDisp, transcribeDisp, talkDisp] {
            switch disp {
            case .unavailable(let reason):
                XCTAssertFalse(reason.isEmpty)
                XCTAssertTrue(reason.contains("Courier"))
                XCTAssertFalse(reason.localizedCaseInsensitiveContains("Beeper"))
            case .text(let value):
                XCTFail("Expected .unavailable, got .text(\(value))")
            }
        }

        for choice in AIEngineChoice.allCases {
            XCTAssertFalse(choice.label.isEmpty)
        }
        for tone in AIRewriteTone.allCases {
            XCTAssertFalse(tone.label.isEmpty)
        }

        // 2. StubGIFProvider
        let gif: any GIFProvider = StubGIFProvider()
        XCTAssertFalse(gif.isAvailable)
        XCTAssertTrue(gif.unavailableReason.contains("Courier"))
        XCTAssertFalse(gif.unavailableReason.localizedCaseInsensitiveContains("Beeper"))
        let gifs = try await gif.search("party")
        XCTAssertTrue(gifs.isEmpty)

        // 3. UnavailableReportUploader
        let uploader: any ReportUploader = UnavailableReportUploader()
        XCTAssertFalse(uploader.isAvailable)
        XCTAssertTrue(uploader.unavailableReason.contains("Courier"))
        XCTAssertFalse(uploader.unavailableReason.localizedCaseInsensitiveContains("Beeper"))
        let uploadDisp = await uploader.upload(
            bundleURL: URL(fileURLWithPath: "/tmp/report.zip"),
            description: "Test report"
        )
        XCTAssertEqual(uploadDisp, .unavailable(reason: uploader.unavailableReason))

        // 4. UnavailableThemeFileLoader
        let themeLoader: any ThemeFileLoader = UnavailableThemeFileLoader()
        XCTAssertFalse(themeLoader.isAvailable)
        XCTAssertTrue(themeLoader.unavailableReason.contains("Courier"))
        XCTAssertFalse(themeLoader.unavailableReason.localizedCaseInsensitiveContains("Beeper"))
        XCTAssertEqual(
            themeLoader.loadThemeFile(at: URL(fileURLWithPath: "/tmp/custom.css")),
            .unavailable(reason: themeLoader.unavailableReason)
        )
        XCTAssertEqual(themeLoader.reload(), .unavailable(reason: themeLoader.unavailableReason))
        themeLoader.reset()

        // 5. EntitlementProvider planSummary
        let entitled: any EntitlementProvider = AlwaysEntitled()
        XCTAssertEqual(entitled.planSummary.badgeTitle, "Included")
        XCTAssertTrue(entitled.planSummary.headline.contains("Courier"))
        XCTAssertFalse(entitled.planSummary.headline.localizedCaseInsensitiveContains("Beeper"))

        let noPlan: any EntitlementProvider = NoPlan()
        XCTAssertEqual(noPlan.planSummary.badgeTitle, "Free")
        XCTAssertEqual(noPlan.planSummary.headline, "Available with a plan")
        XCTAssertFalse(noPlan.planSummary.detail.localizedCaseInsensitiveContains("Beeper"))

        XCTAssertTrue(
            NetworkTrapURLProtocol.interceptedRequests.isEmpty,
            "Provider stubs must make zero network requests"
        )
    }

    func testAIPreferencesDefaultsPersistenceAndAppLockGateReversion() {
        let suiteName = "test.courier.ai.prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AIPreferences(defaults: defaults)
        XCTAssertFalse(prefs.enableContextualAI)
        XCTAssertEqual(prefs.selectedEngine, .appleIntelligence)
        XCTAssertFalse(prefs.selectedModel.isEmpty)
        XCTAssertEqual(prefs.responseLanguage, "English")
        XCTAssertEqual(prefs.translationLanguages, ["English"])
        XCTAssertFalse(prefs.mentionAIInChats)
        XCTAssertFalse(prefs.useWhisperForTalkToType)
        XCTAssertFalse(prefs.autoTranscribeVoiceNotes)
        XCTAssertEqual(prefs.transcriptionLanguage, "Auto-Detect")
        XCTAssertTrue(prefs.enableSlashCommands)
        XCTAssertTrue(AIPreferences.supportedTranslationLanguages.contains("Arabic"))
        XCTAssertTrue(AIPreferences.supportedTranslationLanguages.contains("Spanish"))

        // Mutate while unlocked and verify persistence across reload
        prefs.enableContextualAI = true
        prefs.selectedEngine = .openAI
        prefs.selectedModel = "gpt-4o-mini"
        prefs.responseLanguage = "Spanish"
        prefs.translationLanguages = ["English", "Arabic", "Spanish"]
        prefs.mentionAIInChats = true
        prefs.aiMentionsSystemPrompt = "Be concise."
        prefs.useWhisperForTalkToType = true
        prefs.autoTranscribeVoiceNotes = true
        prefs.transcriptionLanguage = "English"
        prefs.enableSlashCommands = false

        let reloaded = AIPreferences(defaults: defaults)
        XCTAssertTrue(reloaded.enableContextualAI)
        XCTAssertEqual(reloaded.selectedEngine, .openAI)
        XCTAssertEqual(reloaded.selectedModel, "gpt-4o-mini")
        XCTAssertEqual(reloaded.responseLanguage, "Spanish")
        XCTAssertEqual(reloaded.translationLanguages, ["English", "Arabic", "Spanish"])
        XCTAssertTrue(reloaded.mentionAIInChats)
        XCTAssertEqual(reloaded.aiMentionsSystemPrompt, "Be concise.")
        XCTAssertTrue(reloaded.useWhisperForTalkToType)
        XCTAssertTrue(reloaded.autoTranscribeVoiceNotes)
        XCTAssertEqual(reloaded.transcriptionLanguage, "English")
        XCTAssertFalse(reloaded.enableSlashCommands)

        // Lock Courier and verify mutations are reverted by AppLockGate
        let lockSuite = "test.courier.ai.lock.\(UUID().uuidString)"
        let lockDefaults = UserDefaults(suiteName: lockSuite)!
        defer { lockDefaults.removePersistentDomain(forName: lockSuite) }
        let lifecycle = SystemLifecycleModel(defaults: lockDefaults)
        AppLockGate.shared.bind(lifecycle)
        lifecycle.lockNow()
        XCTAssertTrue(AppLockGate.shared.isLocked)

        reloaded.enableContextualAI = false
        reloaded.selectedEngine = .customOpenAICompatible
        reloaded.useWhisperForTalkToType = false
        reloaded.translationLanguages = ["French"]

        XCTAssertTrue(reloaded.enableContextualAI, "Locked mutation must revert")
        XCTAssertEqual(reloaded.selectedEngine, .openAI, "Locked mutation must revert")
        XCTAssertTrue(reloaded.useWhisperForTalkToType, "Locked mutation must revert")
        XCTAssertEqual(reloaded.translationLanguages, ["English", "Arabic", "Spanish"], "Locked mutation must revert")
    }
}
