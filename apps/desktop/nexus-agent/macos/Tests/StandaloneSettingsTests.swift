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

import Combine
import XCTest

import NexusAgentCore

/// The standalone app's saved providers and its turn notices. The app
/// itself cannot be unit-tested (it has a `@main`), so its rules live in
/// the shared code and are tested here, against samples of what the app
/// stored before its chat and its Settings shared one record.
@MainActor
final class StandaloneSettingsTests: XCTestCase {

    // MARK: - What the old app stored

    /// The built-in list as the old app's `saveProviders` wrote it: all
    /// three, in its order, here with Claude's command edited. `JSONEncoder`
    /// writes a `/` as `\/`, so the samples do too.
    private let storedBuiltIns = #"""
    [{"id":"00000000-0000-0000-0000-000000000001","name":"Antigravity CLI","commandTemplate":"agy -p \"{prompt}\" --output-format stream-json --dangerously-skip-permissions","isBuiltIn":true},{"id":"00000000-0000-0000-0000-000000000003","name":"Claude Code","commandTemplate":"\/opt\/bin\/claude -p \"{prompt}\" --model {model}","isBuiltIn":true},{"id":"00000000-0000-0000-0000-000000000002","name":"Ollama (claude)","commandTemplate":"ollama launch claude --model {model} -- -p \"{prompt}\"","isBuiltIn":true}]
    """#

    /// The user's own list: one provider.
    private let storedCustom = #"""
    [{"id":"8F2B6C1E-5D0A-4E7B-9C3F-1A2B3C4D5E6F","name":"Aider","commandTemplate":"\/usr\/local\/bin\/aider --message \"{prompt}\"","isBuiltIn":false}]
    """#

    /// A built-in list from an older version: Antigravity under the name it
    /// had then, and a provider that has since been taken away.
    private let storedStaleBuiltIns = #"""
    [{"id":"00000000-0000-0000-0000-000000000001","name":"Gemini CLI","commandTemplate":"agy -p \"{prompt}\" --effort high","isBuiltIn":true},{"id":"00000000-0000-0000-0000-000000000009","name":"Retired CLI","commandTemplate":"retired {prompt}","isBuiltIn":true}]
    """#

    private var editedClaude: NexusAgentCLIProvider {
        var claude = NexusAgentCLIProvider.claude
        claude.commandTemplate = "/opt/bin/claude -p \"{prompt}\" --model {model}"
        return claude
    }

    private let aider = NexusAgentCLIProvider(id: UUID(uuidString: "8F2B6C1E-5D0A-4E7B-9C3F-1A2B3C4D5E6F")!,
                                              name: "Aider",
                                              commandTemplate: "/usr/local/bin/aider --message \"{prompt}\"",
                                              isBuiltIn: false)

    private func data(_ text: String) -> Data { Data(text.utf8) }

    /// What Settings lists, from the two stored lists.
    private func listed(builtIn: String?, custom: String?) -> [NexusAgentCLIProvider] {
        NexusAgentCLIProvider.available(saved: NexusAgentCLIProvider.saved(builtIn: builtIn.map(data),
                                                                           custom: custom.map(data)))
    }

    // MARK: - Reading

    func testACustomProviderAndAnEditedBuiltInAreReadAsSettingsShowedThem() {
        XCTAssertEqual(listed(builtIn: storedBuiltIns, custom: storedCustom),
                       [.antigravity, editedClaude, .ollama, aider])
    }

    func testAStaleBuiltInKeepsItsCommandUnderTodaysNameAndARetiredOneIsLeftOut() {
        var antigravity = NexusAgentCLIProvider.antigravity
        antigravity.commandTemplate = "agy -p \"{prompt}\" --effort high"
        XCTAssertEqual(listed(builtIn: storedStaleBuiltIns, custom: storedCustom),
                       [antigravity, .claude, .ollama, aider])
    }

    func testAnEmptyOrMissingListIsNoProvidersOfTheUsersOwn() {
        XCTAssertEqual(listed(builtIn: storedBuiltIns, custom: "[]"), [.antigravity, editedClaude, .ollama])
        XCTAssertEqual(listed(builtIn: storedBuiltIns, custom: nil), [.antigravity, editedClaude, .ollama])
        XCTAssertEqual(listed(builtIn: nil, custom: nil), NexusAgentCLIProvider.builtIns, "a first launch")
    }

    func testOneListThatCannotBeReadDoesNotLoseTheOther() {
        XCTAssertEqual(listed(builtIn: "not json", custom: storedCustom), [.antigravity, .claude, .ollama, aider])
        XCTAssertEqual(listed(builtIn: storedBuiltIns, custom: "{\"id\":1}"), [.antigravity, editedClaude, .ollama])
    }

    func testEachListIsBelievedOnlyAboutItsOwnKind() {
        // The user's list with an entry marked built-in (the old app left
        // those out), and the built-in list with one of the user's own.
        let custom = #"[{"id":"00000000-0000-0000-0000-000000000003","name":"x","commandTemplate":"evil {prompt}","isBuiltIn":true}]"#
        XCTAssertEqual(listed(builtIn: nil, custom: custom), NexusAgentCLIProvider.builtIns)
        XCTAssertEqual(listed(builtIn: storedCustom, custom: nil), NexusAgentCLIProvider.builtIns)
    }

    // MARK: - Writing

    func testSavingTheListWritesTheTwoListsTheOldAppWrote() throws {
        let lists = NexusAgentCLIProvider.storedLists(saving: [.antigravity, editedClaude, .ollama, aider], over: [])
        // The same providers the samples hold, read back by a plain decoder
        // as the old app would read them.
        let decoder = JSONDecoder()
        XCTAssertEqual(lists.builtIn, try decoder.decode([NexusAgentCLIProvider].self, from: data(storedBuiltIns)))
        XCTAssertEqual(lists.custom, try decoder.decode([NexusAgentCLIProvider].self, from: data(storedCustom)))

        // And under the same four names, with the id as the old app's text.
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(lists.custom)) as? [[String: Any]]
        XCTAssertEqual(written?.first.map { Set($0.keys) }, ["id", "name", "commandTemplate", "isBuiltIn"])
        XCTAssertEqual(written?.first?["id"] as? String, "8F2B6C1E-5D0A-4E7B-9C3F-1A2B3C4D5E6F")
        XCTAssertEqual(written?.first?["isBuiltIn"] as? Bool, false)
    }

    func testSavingWithNoProvidersOfTheUsersOwnWritesAnEmptyList() {
        let lists = NexusAgentCLIProvider.storedLists(saving: NexusAgentCLIProvider.builtIns, over: [])
        XCTAssertEqual(lists.builtIn, NexusAgentCLIProvider.builtIns)
        XCTAssertEqual(lists.custom, [])
    }

    /// The trap: a caller that saves only the user's own providers (which is
    /// all the host's contract asks for) must not wipe an edited built-in.
    func testSavingAListWithoutBuiltInsKeepsTheStoredOnes() {
        let previous = NexusAgentCLIProvider.stored(data(storedBuiltIns))
        let lists = NexusAgentCLIProvider.storedLists(saving: [aider], over: previous)
        XCTAssertEqual(lists.builtIn, [.antigravity, editedClaude, .ollama], "the edit to Claude is still there")
        XCTAssertEqual(lists.custom, [aider])

        // One built-in in the new list replaces its stored copy; the others stay.
        var ollama = NexusAgentCLIProvider.ollama
        ollama.commandTemplate = "ollama run {model} {prompt}"
        XCTAssertEqual(NexusAgentCLIProvider.storedLists(saving: [ollama], over: previous).builtIn,
                       [.antigravity, editedClaude, ollama])
        // A built-in handed back as it ships undoes the edit: that is how Settings resets one.
        XCTAssertEqual(NexusAgentCLIProvider.storedLists(saving: [.claude], over: previous).builtIn,
                       NexusAgentCLIProvider.builtIns)
    }

    func testAStaleStoredBuiltInListIsRewrittenAsTodaysThree() {
        let previous = NexusAgentCLIProvider.stored(data(storedStaleBuiltIns))
        var antigravity = NexusAgentCLIProvider.antigravity
        antigravity.commandTemplate = "agy -p \"{prompt}\" --effort high"
        XCTAssertEqual(NexusAgentCLIProvider.storedLists(saving: [], over: previous).builtIn,
                       [antigravity, .claude, .ollama], "today's names, the saved command, no retired entry")
    }

    // MARK: - The chat and Settings share one record

    /// A host that keeps the provider record as the standalone does: three
    /// values under the app's keys, read and written by the shared rules.
    private final class StoreHost: NexusAgentHost {
        var store: [String: Any] = [:]
        var configuredBotDirectory = ""
        var startsBotAtLaunch = false
        var planMode = false
        var hiddenClaudeSessionIDs: [String] = []
        var promptHistory: [String] = []
        var worktreeMode = false
        var strings = NexusAgentHostStrings()

        var chosenProviderID: UUID? {
            get { (store["activeProviderId"] as? String).flatMap(UUID.init(uuidString:)) }
            set { store["activeProviderId"] = newValue?.uuidString }
        }

        var savedProviders: [NexusAgentCLIProvider] {
            get {
                NexusAgentCLIProvider.saved(builtIn: store["builtInProviders_v3"] as? Data,
                                            custom: store["customProviders"] as? Data)
            }
            set {
                let lists = NexusAgentCLIProvider.storedLists(
                    saving: newValue, over: NexusAgentCLIProvider.stored(store["builtInProviders_v3"] as? Data))
                store["builtInProviders_v3"] = try? JSONEncoder().encode(lists.builtIn)
                store["customProviders"] = try? JSONEncoder().encode(lists.custom)
            }
        }

        var storedBuiltIn: [NexusAgentCLIProvider] { NexusAgentCLIProvider.stored(store["builtInProviders_v3"] as? Data) }
        var storedCustom: [NexusAgentCLIProvider] { NexusAgentCLIProvider.stored(store["customProviders"] as? Data) }

        func turnNeedsApproval(_ notice: NexusAgentTurnNotice) {}
        func turnFinished(_ notice: NexusAgentTurnNotice, isChatVisible: Bool) {}
    }

    /// What the standalone's Settings model does with its three members:
    /// read through the engine, write through the host, tell the engine.
    @MainActor
    private struct Settings {
        let engine: NexusAgentEngine
        let host: StoreHost

        var providers: [NexusAgentCLIProvider] {
            get { engine.providers }
            nonmutating set {
                host.savedProviders = newValue
                engine.providersChanged()
            }
        }

        var activeProviderID: UUID {
            get { engine.activeProvider.id }
            nonmutating set {
                host.chosenProviderID = newValue
                engine.providersChanged()
            }
        }

        func saveProviders() {
            host.savedProviders = engine.providers
            host.chosenProviderID = engine.activeProvider.id
            engine.providersChanged()
        }
    }

    /// An outside world in which nothing exists and nothing can be started.
    /// It counts how often the list of conversations was read.
    @MainActor
    private final class World {
        var listings: [NexusAgentCLIProvider] = []

        var environment: NexusAgentEngine.Environment {
            NexusAgentEngine.Environment(
                defaults: UserDefaults(suiteName: "com.vitruviansoftware.nexus-agent.tests.unused")!,
                home: "/Users/rig",
                processEnvironment: ["PATH": "/usr/bin"],
                stateDirectory: "/Users/rig/state",
                isExecutable: { _ in false },
                fileExists: { _ in false },
                readFile: { _ in nil },
                readTail: { _, _ in nil },
                writePrivateFile: { _, _ in false },
                removeFile: { _ in },
                isBotProcess: { _ in false },
                signal: { _, _ in },
                launchBot: { _, _, _, _, _ in throw CocoaError(.fileWriteUnknown) },
                schedule: { _, _ in },
                openFile: { _ in },
                launchAgent: { _, _, _, _, _, _ in throw CocoaError(.fileWriteUnknown) },
                listSessions: { [unowned self] _, provider, _ in
                    listings.append(provider)
                    return []
                })
        }
    }

    private func seededHost() -> StoreHost {
        let host = StoreHost()
        host.store["builtInProviders_v3"] = data(storedBuiltIns)
        host.store["customProviders"] = data(storedCustom)
        return host
    }

    func testAProviderChosenInTheChatIsWhatSettingsShowsAndSurvivesASettingsSave() {
        let world = World()
        let host = seededHost()
        let engine = NexusAgentEngine(environment: world.environment, host: host)
        let settings = Settings(engine: engine, host: host)
        XCTAssertEqual(settings.activeProviderID, NexusAgentCLIProvider.antigravity.id)

        // The chat's picker.
        engine.updateActiveProvider(aider)
        XCTAssertEqual(host.store["activeProviderId"] as? String, "8F2B6C1E-5D0A-4E7B-9C3F-1A2B3C4D5E6F",
                       "the record has it, as the text the old app wrote")
        XCTAssertEqual(settings.activeProviderID, aider.id, "Settings shows it without being told")

        // Settings is saved after the chat chose: the choice is not put back.
        settings.saveProviders()
        XCTAssertEqual(host.chosenProviderID, aider.id)
        XCTAssertEqual(engine.activeProvider, aider)
        XCTAssertEqual(host.storedBuiltIn, [.antigravity, editedClaude, .ollama], "and the lists are as they were")
        XCTAssertEqual(host.storedCustom, [aider])

        // A Settings window opened later, or the next launch, is another model on the same record.
        let relaunched = NexusAgentEngine(environment: world.environment, host: host)
        XCTAssertEqual(relaunched.activeProvider, aider)
        XCTAssertEqual(relaunched.providers, [.antigravity, editedClaude, .ollama, aider])
    }

    func testAProviderAddedInSettingsIsInTheChatWithoutANewEngine() {
        let world = World()
        let host = seededHost()
        let engine = NexusAgentEngine(environment: world.environment, host: host)
        let settings = Settings(engine: engine, host: host)
        let llm = NexusAgentCLIProvider(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-00000000000A")!,
                                        name: "My LLM", commandTemplate: "llm \"{prompt}\"", isBuiltIn: false)

        settings.providers.append(llm)
        XCTAssertEqual(engine.providers, [.antigravity, editedClaude, .ollama, aider, llm])
        XCTAssertEqual(host.storedCustom, [aider, llm], "the user's list holds only the user's own")
        XCTAssertEqual(host.storedBuiltIn, [.antigravity, editedClaude, .ollama])
        XCTAssertEqual(engine.activeProvider, .antigravity, "adding one does not choose it")

        // Settings' picker.
        let listingsBefore = world.listings.count
        settings.activeProviderID = llm.id
        XCTAssertEqual(engine.activeProvider, llm)
        XCTAssertEqual(engine.configuration.activeProvider, llm, "which is what the chat's turns run")
        XCTAssertEqual(host.store["activeProviderId"] as? String, llm.id.uuidString)
        XCTAssertEqual(world.listings.count, listingsBefore + 1, "the chat's conversations are read again")
        XCTAssertEqual(world.listings.last, llm)
    }

    func testAnEditInSettingsReachesTheProviderTheChatIsOn() {
        let world = World()
        let host = seededHost()
        let engine = NexusAgentEngine(environment: world.environment, host: host)
        let settings = Settings(engine: engine, host: host)
        engine.updateActiveProvider(editedClaude)

        // A built-in's command, edited again.
        var providers = settings.providers
        providers[1].commandTemplate = "claude -p \"{prompt}\""
        settings.providers = providers
        XCTAssertEqual(engine.activeProvider, .claude, "the chat has the new command")
        XCTAssertEqual(host.storedBuiltIn, NexusAgentCLIProvider.builtIns)
        XCTAssertEqual(host.chosenProviderID, NexusAgentCLIProvider.claude.id)

        // One of the user's own.
        engine.updateActiveProvider(aider)
        var edited = aider
        edited.commandTemplate = "aider --yes --message \"{prompt}\""
        providers = settings.providers
        providers[3] = edited
        let listingsBefore = world.listings.count
        settings.providers = providers
        XCTAssertEqual(engine.activeProvider, edited)
        XCTAssertEqual(host.storedCustom, [edited])
        XCTAssertEqual(world.listings.count, listingsBefore, "the same provider run the same way keeps its conversations")
    }

    func testRemovingTheChosenProviderFallsBackToAntigravity() {
        let world = World()
        let host = seededHost()
        // Antigravity's own command was edited too, to see which copy the fallback is.
        var antigravity = NexusAgentCLIProvider.antigravity
        antigravity.commandTemplate = "agy -p \"{prompt}\" --effort high"
        host.savedProviders = [antigravity, editedClaude, .ollama, aider]
        let engine = NexusAgentEngine(environment: world.environment, host: host)
        let settings = Settings(engine: engine, host: host)
        engine.updateActiveProvider(aider)

        settings.providers.removeAll { $0.id == aider.id }
        XCTAssertEqual(engine.providers, [antigravity, editedClaude, .ollama])
        XCTAssertEqual(host.storedCustom, [])
        XCTAssertEqual(engine.activeProvider, antigravity, "Antigravity as it is listed")
        XCTAssertEqual(host.store["activeProviderId"] as? String, "00000000-0000-0000-0000-000000000001",
                       "and the record no longer names the removed one")
        XCTAssertEqual(settings.activeProviderID, NexusAgentCLIProvider.antigravity.id)
    }

    func testRemovingAnotherProviderLeavesTheChoiceAlone() {
        let world = World()
        let host = seededHost()
        let engine = NexusAgentEngine(environment: world.environment, host: host)
        let settings = Settings(engine: engine, host: host)
        engine.updateActiveProvider(.ollama)

        settings.providers.removeAll { $0.id == aider.id }
        XCTAssertEqual(engine.activeProvider, .ollama)
        XCTAssertEqual(host.chosenProviderID, NexusAgentCLIProvider.ollama.id)
    }

    func testTellingTheEngineWhenNothingChangedDoesNothing() {
        let world = World()
        let host = seededHost()
        let engine = NexusAgentEngine(environment: world.environment, host: host)
        engine.updateActiveProvider(aider)
        var published = 0
        let watching = engine.$configuration.dropFirst().sink { _ in published += 1 }
        defer { watching.cancel() }
        let listingsBefore = world.listings.count

        engine.providersChanged()
        XCTAssertEqual(published, 0, "nothing is published")
        XCTAssertEqual(world.listings.count, listingsBefore, "and nothing is read")
        XCTAssertEqual(host.chosenProviderID, aider.id)

        // A user who never chose is not given a choice by it either.
        let fresh = StoreHost()
        NexusAgentEngine(environment: world.environment, host: fresh).providersChanged()
        XCTAssertNil(fresh.store["activeProviderId"])
    }

    // MARK: - What the user hears about a finished turn

    private let strings = NexusAgentHostStrings()

    private func notice(_ text: String, failed: Bool = false, endedCleanly: Bool = true,
                        failureDetail: String? = nil) -> NexusAgentTurnNotice {
        NexusAgentTurnNotice(providerName: "Antigravity CLI", text: text, failed: failed, endedCleanly: endedCleanly,
                             failureDetail: failureDetail)
    }

    /// A failed turn as the session reports one: the reply (often none) as
    /// the text, and what went wrong beside it.
    private func failure(_ detail: String?, reply: String = "") -> NexusAgentTurnNotice {
        notice(reply, failed: true, endedCleanly: false, failureDetail: detail)
    }

    func testAReplyThatFinishedOutOfSightIsANotificationAndTheSound() {
        XCTAssertEqual(NexusAgentTurnAnnouncement.finished(notice("All done."), isChatVisible: false, strings: strings),
                       NexusAgentTurnAnnouncement(playsSound: true,
                                                  notificationTitle: "Antigravity CLI — Done",
                                                  notificationBody: "All done."))
    }

    func testAFailureOutOfSightIsANotificationWithoutTheSound() {
        XCTAssertEqual(NexusAgentTurnAnnouncement.finished(failure("The agent stopped with an error.\nquota exceeded"),
                                                           isChatVisible: false, strings: strings),
                       NexusAgentTurnAnnouncement(playsSound: false,
                                                  notificationTitle: "Antigravity CLI — Failed",
                                                  notificationBody: "The agent stopped with an error.\nquota exceeded"))
    }

    func testAFailureAfterPartOfAReplySaysWhatWentWrongNotTheReply() {
        XCTAssertEqual(NexusAgentTurnAnnouncement.finished(failure("Lost the connection", reply: "Half a reply"),
                                                           isChatVisible: false, strings: strings),
                       NexusAgentTurnAnnouncement(playsSound: false,
                                                  notificationTitle: "Antigravity CLI — Failed",
                                                  notificationBody: "Lost the connection"))
        // A failed notice with a text and no words for the failure, which
        // the session does not send, still says something: the text.
        XCTAssertEqual(NexusAgentTurnAnnouncement.finished(failure(nil, reply: "Half a reply"),
                                                           isChatVisible: false, strings: strings).notificationBody,
                       "Half a reply")
        XCTAssertEqual(NexusAgentTurnAnnouncement.finished(failure("", reply: "Half a reply"),
                                                           isChatVisible: false, strings: strings).notificationBody,
                       "Half a reply", "empty words are no words")
    }

    /// What the session sends when the user stops a turn before any of it
    /// arrived: marked failed (the program ended on a signal) with nothing
    /// to say. The user did that themselves, so they are not told "Failed".
    func testATurnStoppedWithNothingToShowSaysNothing() {
        for visible in [true, false] {
            XCTAssertEqual(NexusAgentTurnAnnouncement.finished(failure(nil), isChatVisible: visible, strings: strings),
                           NexusAgentTurnAnnouncement(playsSound: false), "visible: \(visible)")
        }
    }

    func testAReplyTheUserCanSeeIsOnlyTheSound() {
        XCTAssertEqual(NexusAgentTurnAnnouncement.finished(notice("All done."), isChatVisible: true, strings: strings),
                       NexusAgentTurnAnnouncement(playsSound: true))
        XCTAssertEqual(NexusAgentTurnAnnouncement.finished(failure("oops"), isChatVisible: true, strings: strings),
                       NexusAgentTurnAnnouncement(playsSound: false), "and a failure in sight is nothing more")
    }

    func testAnEmptyReplySaysNothing() {
        for visible in [true, false] {
            XCTAssertEqual(NexusAgentTurnAnnouncement.finished(notice(""), isChatVisible: visible, strings: strings),
                           NexusAgentTurnAnnouncement(playsSound: false), "visible: \(visible)")
        }
    }

    func testALongReplyIsCutToItsFirstLineAndTwoHundredCharacters() {
        let longLine = String(repeating: "word ", count: 60)
        XCTAssertEqual(longLine.count, 300)
        let reply = "\n   \n" + longLine + "\nsecond line\nthird line"
        let done = NexusAgentTurnAnnouncement.finished(notice(reply), isChatVisible: false, strings: strings)
        XCTAssertEqual(done.notificationTitle, "Antigravity CLI — Done")
        XCTAssertEqual(done.notificationBody, String(longLine.prefix(200)),
                       "the first line that is not blank, cut as the old chat cut it")

        // A failure is not cut to a line: the start of the whole text, as before.
        let failed = NexusAgentTurnAnnouncement.finished(failure("line one\nline two"),
                                                         isChatVisible: false, strings: strings)
        XCTAssertEqual(failed.notificationBody, "line one\nline two")
        let longFailure = NexusAgentTurnAnnouncement.finished(failure(String(repeating: "x", count: 500)),
                                                              isChatVisible: false, strings: strings)
        XCTAssertEqual(longFailure.notificationBody?.count, 200)
    }

    func testAStoppedTurnWithTextIsDoneWithoutTheSound() {
        // Stopped by the user: not failed, and not ended cleanly.
        XCTAssertEqual(NexusAgentTurnAnnouncement.finished(notice("half a reply", endedCleanly: false),
                                                           isChatVisible: false, strings: strings),
                       NexusAgentTurnAnnouncement(playsSound: false,
                                                  notificationTitle: "Antigravity CLI — Done",
                                                  notificationBody: "half a reply"))
    }

    func testTheTitlesUseTheHostsWords() {
        var german = NexusAgentHostStrings()
        german.doneTitleSuffix = " — Fertig"
        XCTAssertEqual(NexusAgentTurnAnnouncement.finished(notice("ok"), isChatVisible: false, strings: german)
            .notificationTitle, "Antigravity CLI — Fertig")
    }

    /// The app posts the title this rule gives, so these are the words a
    /// user reads. They are the ones this app's own chat always posted.
    func testTheTitlesAreTheOnesTheOldChatPosted() {
        let provider = "Claude Code"
        XCTAssertEqual(NexusAgentTurnAnnouncement.finished(
            NexusAgentTurnNotice(providerName: provider, text: "ok", failed: false, endedCleanly: true),
            isChatVisible: false, strings: strings).notificationTitle, "\(provider) — Done")
        XCTAssertEqual(NexusAgentTurnAnnouncement.finished(
            NexusAgentTurnNotice(providerName: provider, text: "", failed: true, endedCleanly: false,
                                 failureDetail: "boom"),
            isChatVisible: false, strings: strings).notificationTitle, "\(provider) — Failed")
    }

    // MARK: - What the user hears about a turn waiting for approval

    private var waiting: NexusAgentTurnNotice {
        NexusAgentTurnNotice(providerName: "Claude Code", text: "Bash: rm -rf /tmp/cache", failed: false,
                             endedCleanly: false)
    }

    func testATurnWaitingForApprovalOutOfSightIsANotification() {
        XCTAssertEqual(NexusAgentTurnAnnouncement.needsApproval(waiting, isChatVisible: false, strings: strings),
                       NexusAgentTurnAnnouncement(playsSound: false,
                                                  notificationTitle: "Claude Code — Approval Required",
                                                  notificationBody: "Bash: rm -rf /tmp/cache"))
    }

    func testATurnWaitingForApprovalInSightIsNothingMore() {
        XCTAssertEqual(NexusAgentTurnAnnouncement.needsApproval(waiting, isChatVisible: true, strings: strings),
                       NexusAgentTurnAnnouncement(playsSound: false), "the chat itself shows the request")
    }

    func testAnApprovalNoticeUsesTheHostsWordsAndIsCutLikeAnyOther() {
        var german = NexusAgentHostStrings()
        german.approvalRequiredTitleSuffix = " — Freigabe nötig"
        XCTAssertEqual(NexusAgentTurnAnnouncement.needsApproval(waiting, isChatVisible: false, strings: german)
            .notificationTitle, "Claude Code — Freigabe nötig")

        var long = waiting
        long.text = "Bash: " + String(repeating: "x", count: 500)
        XCTAssertEqual(NexusAgentTurnAnnouncement.needsApproval(long, isChatVisible: false, strings: strings)
            .notificationBody?.count, NexusAgentTurnAnnouncement.bodyLimit)
    }
}
