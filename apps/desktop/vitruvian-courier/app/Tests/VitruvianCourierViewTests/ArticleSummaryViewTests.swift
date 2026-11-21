// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// "Summarize" on a link card (E1): the button, the panel in each state, and the row growing to fit it.
/// Look at article-summary-*, article-summary-card-*.
@MainActor
final class ArticleSummaryViewTests: XCTestCase {
    private var suites: [String] = []
    private var tempDirs: [URL] = []

    override func tearDown() async throws {
        for name in suites { ScratchDefaults.suite(named: name)?.removePersistentDomain(forName: name) }
        suites = []
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        tempDirs = []
        AppLockGate.shared.resetForTesting()
    }

    private let url = URL(string: "https://www.usatoday.com/story/news/bridge/123/")!
    private let apURL = URL(string: "https://apnews.com/article/bridge-opens-early")!

    private final class Reader: ArticleReading, @unchecked Sendable {
        func readArticle(at url: URL) async throws -> ArticleResult {
            ArticleResult(url: url.absoluteString, title: "Bridge opens early", site: "Example",
                          description: "", text: "Officials said the bridge opens in March.", paywalled: false, needsBrowser: false)
        }
    }

    private final class Provider: AIProvider, @unchecked Sendable {
        var isAvailable = true
        var unavailableReason = ""
        let availableModels = ["m"]
        func draftResponse(context: AIChatContext, draft: String, tone: AIRewriteTone?) async -> AIProviderDisposition { .text("") }
        func translate(text: String, targetLanguage: String) async -> AIProviderDisposition { .text("") }
        func summarize(context: AIChatContext) async -> AIProviderDisposition { .text("") }
        func summarizeArticle(title: String, site: String, text: String) async -> AIProviderDisposition {
            .text("- The bridge opens to traffic in March.\n- It cost 48 million dollars.\n- “We never expected to finish early,” said the lead engineer.")
        }
    }

    private func makeDefaults() -> UserDefaults {
        let name = "courier.articlesummary.\(UUID().uuidString)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("courier-article-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return dir
    }

    private func summary(origin: ArticleSummaryOrigin = .page) -> ArticleSummary {
        ArticleSummary(
            bullets: ["The bridge opens to traffic in March, two months ahead of schedule.",
                      "It cost 48 million dollars, paid for with a federal grant and a state bond.",
                      "“We never expected to finish early,” said Dana Ortiz, the lead engineer."],
            provider: "Anthropic", sourceURL: origin == .page ? url : apURL,
            sourceDomain: origin == .page ? "usatoday.com" : "apnews.com", linkDomain: "usatoday.com", origin: origin)
    }

    private func controls(state: ArticleSummaryState?, offered: Bool = true) -> ArticleSummaryControls {
        var controls = ArticleSummaryControls()
        controls.canSummarize = { _ in offered }
        controls.state = { _ in state }
        controls.hasAny = { state != nil }
        return controls
    }

    private func check(_ sizes: [NSSize], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(sizes.count, 2, file: file, line: line)
        for size in sizes {
            XCTAssertGreaterThan(size.width, 100, file: file, line: line)
            XCTAssertGreaterThan(size.height, 20, file: file, line: line)
        }
    }

    // MARK: The panel, in each state

    func testThePanelDrawsInEveryState() throws {
        let states: [(String, ArticleSummaryState)] = [
            ("working", .working(.reading)),
            ("searching", .working(.searching)),
            ("summary", .summary(summary())),
            ("elsewhere", .summary(summary(origin: .elsewhere(.paywalled)))),
            ("unreadable-elsewhere", .summary(summary(origin: .elsewhere(.unreadable)))),
            ("paywalled-no-match", .failed(.notFoundElsewhere(why: .paywalled, domain: "usatoday.com", detail: nil))),
            ("search-failed", .failed(.notFoundElsewhere(why: .paywalled, domain: "usatoday.com",
                                                        detail: "Rate limit reached. Wait a moment and try again."))),
            ("ai-error", .failed(.aiError(reason: "The API key was rejected. Check your key in Settings ▸ AI."))),
        ]
        for (name, state) in states {
            for onBubble in [false, true] {
                check(try Snapshot.render("article-summary-\(name)\(onBubble ? "-on-bubble" : "")", width: 360) {
                    ArticleSummaryPanel(url: url, state: state, onBubble: onBubble, controls: controls(state: state))
                        .padding(14)
                        .background(onBubble ? Color.accentColor : Color.clear)
                })
            }
        }
    }

    func testAFinishedSummaryOffersOpenArticleAndCopyAndNamesItsProvider() {
        let state = ArticleSummaryState.summary(summary())
        XCTAssertEqual(ArticleSummaryCopy.footer(provider: "Anthropic"), "Summary by Anthropic")
        var copied: [String] = []
        var opened: [URL] = []
        var panelControls = controls(state: state)
        panelControls.copy = { copied.append($0) }
        panelControls.open = { opened.append($0) }
        // The buttons' actions are the controls' own: Copy puts the bullets on the pasteboard, Open article opens the source.
        panelControls.copy(summary().copyText)
        panelControls.open(summary(origin: .elsewhere(.paywalled)).sourceURL)
        XCTAssertEqual(copied, ["• The bridge opens to traffic in March, two months ahead of schedule.\n• It cost 48 million dollars, paid for with a federal grant and a state bond.\n• “We never expected to finish early,” said Dana Ortiz, the lead engineer."])
        XCTAssertEqual(opened, [apURL])
    }

    // MARK: The button

    func testTheSummarizeButtonIsInTheCardOnlyWhenOffered() throws {
        let preview = LinkPreviewItem(matchedURL: url.absoluteString, url: url.absoluteString, title: "Bridge opens early",
                                      siteName: "USA TODAY", description: "Two months ahead of schedule.")
        func height(_ name: String, _ controls: ArticleSummaryControls?) throws -> CGFloat {
            let sizes = try Snapshot.render("article-summary-card-\(name)", width: 360) {
                if let controls {
                    // As the message row fills the card's footer slot.
                    LinkPreviewCardView(preview: preview) {
                        if let request = ArticleSummaryRequest(preview: preview) {
                            ArticleSummarySection(request: request, onBubble: false, controls: controls, inCard: true)
                        }
                    }.padding(14)
                } else {
                    LinkPreviewCardView(preview: preview).padding(14)
                }
            }
            check(sizes)
            return sizes[0].height
        }
        let plain = try height("default", nil)
        let hidden = try height("hidden", controls(state: nil, offered: false))
        let offered = try height("offered", controls(state: nil, offered: true))
        let working = try height("working", controls(state: .working(.reading), offered: true))
        let done = try height("done", controls(state: .summary(summary()), offered: true))
        XCTAssertEqual(hidden, plain, "AI off, no link previews or no https link: the card is as it was")
        XCTAssertGreaterThan(offered, plain + 10, "the button sits under the card")
        XCTAssertGreaterThan(working, plain + 10, "the panel sits under the card")
        XCTAssertGreaterThan(done, working + 20, "three bullets and their footer are taller than the spinner")
    }

    // MARK: The row, end to end through the app's own wiring

    private struct World {
        let conversation: ConversationModel
        let messageActions: MessageActionsModel
        let preferences: ComposerPreferences
        let actions: VitruvianCourier.MessageActions
        let ui: MessageUI
        let env: TimelineRowEnvironment
    }

    private func makeWorld() throws -> World {
        // The cache is the app's one, shared by every model: a summary kept by an earlier test would answer this one.
        ArticleSummaryCache.shared.removeAll()
        let dir = try makeTempDir()
        let app = AppModel(supervisor: EngineSupervisor(enginePath: "/nonexistent/vitruvian-courier-engine", dataDir: dir,
                                                        environment: [:], launcher: FoundationProcessLauncher()))
        let prefs = ComposerPreferences(defaults: makeDefaults())
        let conversation = ConversationModel(appModel: app, preferences: prefs)
        final class NoPasteboard: TextPasteboard { func setString(_: String) {} }
        let messageActions = MessageActionsModel(conversation: conversation, appModel: app, preferences: prefs, pasteboard: NoPasteboard())
        messageActions.articleSummaries.reader = Reader()
        messageActions.aiProvider = Provider()
        conversation.composer.aiProvider = Provider()
        let ui = MessageUI()
        let actions = MessageRowActions.make(conversation: conversation, messageActions: messageActions, preferences: prefs,
                                             composer: conversation.composer, ui: ui, source: .chat, select: { _ in })
        let env = TimelineRowEnvironment(
            appearance: nil, themeRoomID: nil, themeAccentHex: CourierThemePreset.classicTeal.defaultAccentHex,
            redactNamesAndPictures: false, liquidGlass: false, timelineCovered: false, messagePointSize: 13,
            zoomMultiplier: 1.0, colorScheme: .light, reactionCardOverride: nil, clickTargetProbe: nil)
        return World(conversation: conversation, messageActions: messageActions, preferences: prefs, actions: actions, ui: ui, env: env)
    }

    private func linkMessageEvent() -> Event {
        Event(eventID: "$link", roomID: Fixture.room, sender: Fixture.ann, senderName: "Ann Example", mine: false,
              type: "m.room.message",
              content: .object(["msgtype": .string("m.text"), "body": .string(url.absoluteString)]),
              ts: Fixture.millis(5), seq: 9000, status: .sent,
              linkPreviews: [LinkPreviewItem(matchedURL: url.absoluteString, url: url.absoluteString, title: "Bridge opens early",
                                             siteName: "USA TODAY", description: "Two months ahead of schedule.")])
    }

    func testAnOpenSummaryChangesTheRowsHeightSignatureSoTheRowIsMeasuredAgain() async throws {
        let world = try makeWorld()
        let item = try XCTUnwrap(Fixture.items([linkMessageEvent()]).first { $0.id == "$link" })
        func revision() -> Int {
            TimelineContentRevision.compute(item: item, showsSent: false, actions: world.actions, ui: world.ui,
                                            messageActions: world.messageActions,
                                            voiceNoteTranscripts: world.conversation.voiceNoteTranscripts,
                                            timerChoicesCount: 0, envHeightSignature: world.env.heightSignature)
        }
        let before = revision()
        world.messageActions.summarizeLink(ArticleSummaryRequest(url: url, headline: "Bridge opens early"))
        let working = revision()
        XCTAssertNotEqual(before, working, "the spinner is a different height from the button")
        await world.messageActions.articleSummaries.waitForSummary(of: url)
        guard case .summary? = world.messageActions.articleSummaries.state(for: url) else { return XCTFail() }
        XCTAssertNotEqual(working, revision(), "the bullets are a different height from the spinner")

        // The AI going away takes the button away: a different height too.
        let withSummary = revision()
        world.messageActions.articleSummaries.dismiss(url)
        let closed = revision()
        XCTAssertNotEqual(withSummary, closed)
        world.messageActions.aiProvider = UnavailableAIProvider()
        XCTAssertNotEqual(closed, revision(), "AI off hides the button, so the row is measured again")
    }

    func testTheTimelineModelPublishesWhenASummaryMovesOn() async throws {
        let world = try makeWorld()
        var published = 0
        let subscription = world.messageActions.objectWillChange.sink { published += 1 }
        defer { subscription.cancel() }
        world.messageActions.summarizeLink(ArticleSummaryRequest(url: url, headline: "Bridge opens early"))
        await world.messageActions.articleSummaries.waitForSummary(of: url)
        XCTAssertGreaterThanOrEqual(published, 2, "the spinner and the summary each redraw the timeline")
    }

    func testTheButtonFollowsTheAIServiceAndTheLinkPreviewsSetting() throws {
        let world = try makeWorld()
        XCTAssertTrue(world.actions.articleSummary.canSummarize(url))
        world.preferences.showLinkPreviews = false
        XCTAssertFalse(world.actions.articleSummary.canSummarize(url), "'Show link previews' off hides it")
        world.preferences.showLinkPreviews = true
        world.messageActions.aiProvider = UnavailableAIProvider()
        XCTAssertFalse(world.actions.articleSummary.canSummarize(url), "no AI service hides it")
    }

    func testSummarizeLinkIsInTheMessagesMoreMenuOnlyWhenLinkPreviewsAreOn() throws {
        let world = try makeWorld()
        let message = try XCTUnwrap(Fixture.messages([linkMessageEvent()]).first)
        func moreTitles() -> [String] {
            world.actions.menu(message).flatMap { $0 }.first { $0.command == .more }?.children.map(\.title) ?? []
        }
        XCTAssertTrue(moreTitles().contains("Summarize Link"), "\(moreTitles())")
        world.preferences.showLinkPreviews = false
        XCTAssertFalse(moreTitles().contains("Summarize Link"), "the same kind of fetch as a link preview: off means off")

        // A message with no link has no such item.
        world.preferences.showLinkPreviews = true
        let plain = try XCTUnwrap(Fixture.messages([Fixture.text("$p", "no link", mine: false, ts: 4)]).first)
        let titles = world.actions.menu(plain).flatMap { $0 }.first { $0.command == .more }?.children.map(\.title) ?? []
        XCTAssertFalse(titles.contains("Summarize Link"))
    }

    func testSummarizeLinkFromTheMenuShowsItsPanelEvenForALinkWithNoCard() async throws {
        let world = try makeWorld()
        let bare = URL(string: "https://example.com/story")!
        let event = Fixture.text("$bare", "read \(bare.absoluteString)", mine: false, ts: 3)
        let message = try XCTUnwrap(Fixture.messages([event]).first)
        let request = try XCTUnwrap(ArticleSummaryRequest.first(in: message, isEmbed: ArticleSummaryControls.isEmbed))
        XCTAssertEqual(request.url, bare)
        world.messageActions.summarizeLink(request)
        await world.messageActions.articleSummaries.waitForSummary(of: bare)
        XCTAssertTrue(world.actions.articleSummary.hasAny())
        guard case .summary? = world.actions.articleSummary.state(bare) else { return XCTFail("the panel under the message has its summary") }
        // And the message draws with that panel under it.
        var rowActions = world.actions
        rowActions.now = { Fixture.now }
        let sizes = try Snapshot.render("article-summary-bare-link-row", width: 480) {
            MessageRowView(message: message, isSelected: false, showsSent: false, actions: rowActions, ui: world.ui).padding(14)
        }
        check(sizes)
    }

    // MARK: Round 1

    func testGoogleSearchSuggestionsNeverNavigateInsideTheApp() throws {
        let search = try XCTUnwrap(URL(string: "https://www.google.com/search?q=bridge+opens+early"))
        XCTAssertEqual(SearchSuggestionsPolicy.decide(url: search, isLinkClick: true, isMainFrame: true), .openInBrowser(search),
                       "a click on a Google search link opens in the person's browser")
        for refused in ["https://evil.example/search", "http://www.google.com/search?q=x", "javascript:alert(1)",
                        "https://google.com.evil.example/x", "https://user@www.google.com/x", "file:///etc/passwd"] {
            XCTAssertEqual(SearchSuggestionsPolicy.decide(url: URL(string: refused), isLinkClick: true, isMainFrame: true), .cancel, refused)
        }
        XCTAssertEqual(SearchSuggestionsPolicy.decide(url: URL(string: "about:blank"), isLinkClick: false, isMainFrame: true), .allow,
                       "the first load of the HTML Courier hands over")
        XCTAssertEqual(SearchSuggestionsPolicy.decide(url: search, isLinkClick: false, isMainFrame: true), .cancel,
                       "a page that moves itself on is not followed")
        XCTAssertEqual(SearchSuggestionsPolicy.decide(url: search, isLinkClick: false, isMainFrame: false), .cancel, "no frames")
        XCTAssertEqual(SearchSuggestionsPolicy.decide(url: URL(string: "about:blank"), isLinkClick: false, isMainFrame: false), .cancel)

        let configuration = SearchSuggestionsPolicy.makeConfiguration()
        XCTAssertFalse(configuration.defaultWebpagePreferences.allowsContentJavaScript, "JavaScript is off for Google's page")
        XCTAssertFalse(configuration.websiteDataStore.isPersistent, "nothing is stored")
        // Every request the page itself makes is blocked; the rule list is valid JSON that matches everything.
        let rules = try JSONSerialization.jsonObject(with: Data(SearchSuggestionsPolicy.blockEverythingRules.utf8)) as? [[String: Any]]
        XCTAssertEqual((rules?.first?["action"] as? [String: Any])?["type"] as? String, "block")
        XCTAssertEqual((rules?.first?["trigger"] as? [String: Any])?["url-filter"] as? String, ".*")
    }

    func testAnOpenSummaryFromGeminiShowsGoogleSearchSuggestionsUnderIt() throws {
        let html = #"<div class="container"><a href="https://www.google.com/search?q=bridge">bridge opens early</a></div>"#
        var withSuggestions = summary(origin: .elsewhere(.paywalled))
        withSuggestions.searchSuggestionsHTML = html
        var heights: [Int] = []
        var panelControls = controls(state: .summary(withSuggestions))
        panelControls.setSuggestionsHeight = { _, h in heights.append(Int(h)) }
        let state = ArticleSummaryState.summary(withSuggestions)
        let with = try Snapshot.render("article-summary-suggestions", width: 360) {
            ArticleSummaryPanel(url: url, state: state, onBubble: false, controls: panelControls).padding(14)
        }
        let without = try Snapshot.render("article-summary-no-suggestions", width: 360) {
            ArticleSummaryPanel(url: url, state: .summary(summary(origin: .elsewhere(.paywalled))), onBubble: false,
                                controls: controls(state: .summary(summary(origin: .elsewhere(.paywalled))))).padding(14)
        }
        check(with)
        XCTAssertGreaterThanOrEqual(with[0].height, without[0].height + SearchSuggestionsBlock.placeholderHeight - 1,
                                    "Google's suggestions take room under the summary")
    }

    func testTheSummaryModelKeepsTheSuggestionsHeightAndTheRowsSignatureFollowsIt() async throws {
        let world = try makeWorld()
        let item = try XCTUnwrap(Fixture.items([linkMessageEvent()]).first { $0.id == "$link" })
        func revision() -> Int {
            TimelineContentRevision.compute(item: item, showsSent: false, actions: world.actions, ui: world.ui,
                                            messageActions: world.messageActions,
                                            voiceNoteTranscripts: world.conversation.voiceNoteTranscripts,
                                            timerChoicesCount: 0, envHeightSignature: world.env.heightSignature)
        }
        world.messageActions.summarizeLink(ArticleSummaryRequest(url: url, headline: "Bridge opens early"))
        await world.messageActions.articleSummaries.waitForSummary(of: url)
        let before = revision()
        world.actions.articleSummary.setSuggestionsHeight(url, 61.2)
        XCTAssertEqual(world.actions.articleSummary.suggestionsHeight(url), 62)
        XCTAssertNotEqual(before, revision(), "a measured height makes the row measured again")
        world.actions.articleSummary.setSuggestionsHeight(url, 0)
        world.actions.articleSummary.setSuggestionsHeight(url, 100_000)
        XCTAssertEqual(world.actions.articleSummary.suggestionsHeight(url), 62, "an absurd height is ignored")
    }

    func testTheButtonsTooltipNamesTheServiceBeforeTheFirstSend() throws {
        XCTAssertEqual(ArticleSummarySection.help(providerName: "Claude"), "Summarize with Claude")
        XCTAssertEqual(ArticleSummarySection.help(providerName: ""), "Summarize this article with AI")
        let world = try makeWorld()
        world.messageActions.aiProvider = ConfiguredAIProvider(kind: .anthropic, client: AnthropicClient(apiKey: "k"), model: "claude-x")
        XCTAssertEqual(world.actions.articleSummary.providerName(), "Claude")
        world.messageActions.aiProvider = ConfiguredAIProvider(kind: .googleAIStudio, client: GeminiClient(apiKey: "k"), model: "gemini-x")
        XCTAssertEqual(world.actions.articleSummary.providerName(), "Google AI Studio")
    }

    func testLockingTheAppClosesSummariesInFlight() throws {
        let world = try makeWorld()
        world.messageActions.articleSummaries.reader = SlowReader()
        world.messageActions.summarizeLink(ArticleSummaryRequest(url: url, headline: "Bridge opens early"))
        XCTAssertNotNil(world.messageActions.articleSummaries.state(for: url))
        world.messageActions.dismissAllPresentations()
        XCTAssertNil(world.messageActions.articleSummaries.state(for: url), "a lock closes the panel and stops the work")
    }

    private final class SlowReader: ArticleReading, @unchecked Sendable {
        func readArticle(at url: URL) async throws -> ArticleResult {
            try await Task.sleep(for: .seconds(5))
            throw EngineError.notConnected
        }
    }
}
