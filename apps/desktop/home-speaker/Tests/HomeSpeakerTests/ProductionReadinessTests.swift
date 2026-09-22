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

import CryptoKit
import Foundation
import Testing
@testable import HomeSpeakerCore

// Guards for the consumer-readiness fixes: no personal defaults, a real
// sign-in, in-app discovery, a self-contained Claude hook, and secrets kept
// out of the plain-text config.

private func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func json(_ text: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
}

@Suite struct NoPersonalDefaultsTests {
    @Test func freshConfigHasNoHomeOrSpeakers() {
        let cfg = SpeakerConfig()
        #expect(cfg.structureId.isEmpty, "a structure id is per-user and must never be baked in")
        #expect(cfg.defaultTarget.isEmpty)
        #expect(cfg.targets.isEmpty)
        #expect(!cfg.hasSpeakers)
        #expect(cfg.defaultDevice == nil)
    }

    @Test func chatMonitoringIsOptIn() {
        let cfg = ChatMonitorConfig()
        #expect(!cfg.slackEnabled)
        #expect(!cfg.googleChatEnabled)
        #expect(!cfg.anySourceEnabled)
    }

    @Test func hookCommandPointsAtThisBinaryNotAUserPath() {
        let cmd = AgentIntegration.hookCommand(executable: "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker")
        #expect(cmd == "\"/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker\" --claude-stop-hook")
        #expect(!cmd.contains("/Users/"))
        #expect(!cmd.contains("python"))
    }

    @Test func noSourceFileShipsAHomeDirectoryPath() throws {
        // The bug this guards: 1.x wrote "/Users/james/..." into every user's settings.
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = try FileManager.default.subpathsOfDirectory(atPath: sources.path).filter { $0.hasSuffix(".swift") }
        #expect(!files.isEmpty)
        for f in files {
            let text = try String(contentsOf: sources.appendingPathComponent(f), encoding: .utf8)
            #expect(!text.contains("/Users/james"), "\(f) hard-codes a personal path")
            // The 1.x launch-agent label is allowed only where it is being cleaned up.
            for line in text.split(separator: "\n") where line.contains("com.james.") {
                #expect(line.lowercased().contains("legacy"), "\(f) uses a personal identifier outside legacy cleanup: \(line)")
            }
        }
    }
}

@Suite struct AliasTests {
    @Test func aliasIsSafeAndStable() {
        #expect(SpeakerDevice.alias(for: "Lake Office display") == "lake_office_display")
        #expect(SpeakerDevice.alias(for: "Master Bedroom mini pair") == "master_bedroom_mini_pair")
        #expect(SpeakerDevice.alias(for: "  Kitchen  Hub!! ") == "kitchen_hub")
        #expect(SpeakerDevice.alias(for: "Café") == "caf")
        #expect(SpeakerDevice.alias(for: "🔊") == "speaker")
    }
}

@Suite struct DiscoveryParsingTests {
    // Shape captured from a live list_home_resources call.
    static let resources: [[String: Any]] = [
        ["id": "structure@s1", "type": "Structure", "displayName": "Springwood Home",
         "supportedTraits": ["HomeHistory", "AssistantBroadcast"]],
        ["id": "room@s1.r1", "type": "Room", "displayName": "Kitchen", "parentIds": ["structure@s1"]],
        ["id": "room@s1.r2", "type": "Room", "displayName": "Lake Office", "parentIds": ["structure@s1"]],
        ["id": "device@d1", "type": "SpeakerDevice", "displayName": "Kitchen Home", "parentIds": ["room@s1.r1"],
         "supportedTraits": ["Volume", "AssistantBroadcast"]],
        ["id": "device@d2", "type": "GoogleDisplayDevice", "displayName": "Lake Office display", "parentIds": ["room@s1.r2"],
         "supportedTraits": ["Cast", "SpeakerDevice/AssistantBroadcast"]],
        ["id": "device@d3", "type": "GoogleLightDevice", "displayName": "Kitchen Light", "parentIds": ["room@s1.r1"],
         "supportedTraits": ["OnOff"]],
        ["id": "device@d4", "type": "SpeakerDevice", "displayName": "Kitchen Home", "parentIds": ["room@s1.r1"],
         "supportedTraits": ["AssistantBroadcast"]],
    ]

    @Test func onlyBroadcastCapableResourcesBecomeTargets() {
        let targets = GoogleHomeClient.parseBroadcastTargets(resources: Self.resources)
        #expect(targets["kitchen_home"]?.id == "device@d1")
        #expect(targets["kitchen_home"]?.room == "Kitchen")
        #expect(targets["lake_office_display"]?.id == "device@d2", "component-prefixed trait counts")
        #expect(targets["lake_office_display"]?.type == "GoogleDisplayDevice")
        #expect(targets.values.contains(where: { $0.id == "device@d3" }) == false, "lights are not speakers")
    }

    @Test func structureBecomesWholeHomeTarget() {
        let targets = GoogleHomeClient.parseBroadcastTargets(resources: Self.resources)
        #expect(targets["all"]?.id == "structure@s1")
        #expect(targets["all"]?.isWholeHome == true)
    }

    @Test func duplicateNamesGetDistinctAliases() {
        let targets = GoogleHomeClient.parseBroadcastTargets(resources: Self.resources)
        #expect(targets["kitchen_home_2"]?.id == "device@d4")
    }

    @Test func structuresParse() {
        let homes = GoogleHomeClient.parseStructures(json(#"{"structures":[{"displayName":"Springwood Home","structureId":"s1"},{"structureId":""}]}"#))
        #expect(homes == [HomeStructure(id: "s1", name: "Springwood Home")])
    }

    @Test func applyDiscoveryPrefersARealSpeakerAsDefault() {
        var cfg = SpeakerConfig()
        let targets = GoogleHomeClient.parseBroadcastTargets(resources: Self.resources)
        cfg.applyDiscovery(structureId: "s1", structureName: "Home", targets: targets)
        #expect(cfg.hasSpeakers)
        #expect(cfg.defaultTarget != "all", "whole-home is too loud to be the silent default")
        #expect(cfg.defaultDevice != nil)

        // A re-discovery keeps the user's pick when it still exists.
        cfg.defaultTarget = "lake_office_display"
        cfg.applyDiscovery(structureId: "s1", structureName: "Home", targets: targets)
        #expect(cfg.defaultTarget == "lake_office_display")
    }

    @Test func rediscoveryKeepsHandMadeAliasesAndDropsVanishedDevices() {
        // A 1.x config: short alias, same device as the generated one, plus a
        // device that is no longer in the home.
        var cfg = SpeakerConfig(defaultTarget: "lake_office", structureId: "s1", targets: [
            "lake_office": SpeakerDevice(id: "device@d2", type: "GoogleDisplayDevice", name: "Old Name", room: nil),
            "garage": SpeakerDevice(id: "device@gone", type: "SpeakerDevice", name: "Garage"),
        ])
        cfg.applyDiscovery(structureId: "s1", structureName: "Home", targets: GoogleHomeClient.parseBroadcastTargets(resources: Self.resources))
        #expect(cfg.targets["lake_office"]?.id == "device@d2", "hand-made alias survives")
        #expect(cfg.targets["lake_office"]?.name == "Lake Office display", "but its details refresh from the live record")
        #expect(cfg.targets["lake_office_display"] == nil, "no duplicate entry for the same device")
        #expect(cfg.targets["garage"] == nil, "a device that left the home is dropped")
        #expect(cfg.targets["kitchen_home"] != nil, "new devices are added")
        #expect(cfg.defaultTarget == "lake_office")

        // Switching to a different home starts clean.
        cfg.applyDiscovery(structureId: "s2", structureName: "Cabin", targets: ["porch": SpeakerDevice(id: "device@p", type: "SpeakerDevice", name: "Porch")])
        #expect(cfg.targets.keys.sorted() == ["porch"])
        #expect(cfg.defaultTarget == "porch")
    }
}

@Suite struct MCPEnvelopeTests {
    @Test func structuredContentWins() throws {
        let env = json(#"{"jsonrpc":"2.0","id":1,"result":{"structuredContent":{"structures":[]},"content":[{"type":"text","text":"ignored"}]}}"#)
        let payload = try GoogleHomeClient.extractToolPayload(env)
        #expect(payload["structures"] as? [Any] != nil)
    }

    @Test func textContentIsParsedAsJSON() throws {
        let env = json(#"{"result":{"content":[{"type":"text","text":"{\"structures\":[{\"structureId\":\"s1\",\"displayName\":\"H\"}]}"}]}}"#)
        let payload = try GoogleHomeClient.extractToolPayload(env)
        #expect(GoogleHomeClient.parseStructures(payload).first?.id == "s1")
    }

    @Test func errorsSurface() {
        #expect(throws: BroadcastError.mcp("Request contains an invalid argument.")) {
            _ = try GoogleHomeClient.extractToolPayload(json(#"{"error":{"code":-32602,"message":"Request contains an invalid argument."}}"#))
        }
        #expect(throws: BroadcastError.mcp("boom")) {
            _ = try GoogleHomeClient.extractToolPayload(json(#"{"result":{"isError":true,"content":[{"type":"text","text":"boom"}]}}"#))
        }
    }
}

@Suite struct GoogleAuthPureTests {
    @Test func pkceChallengeIsRFC7636() {
        // RFC 7636 appendix B vector.
        let pkce = GoogleAuth.PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let a = GoogleAuth.PKCE.random(), b = GoogleAuth.PKCE.random()
        #expect(a.verifier != b.verifier)
        #expect(a.verifier.count >= 43)
    }

    @Test func authorizationURLCarriesEverythingGoogleNeeds() throws {
        let url = GoogleAuth.authorizationURL(
            client: OAuthClient(clientId: "cid", clientSecret: "sec"),
            scopes: ["openid", GoogleAuth.homeScope], pkce: GoogleAuth.PKCE(verifier: "v"), state: "st", port: 8765)
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let q = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(comps.host == "accounts.google.com")
        #expect(q["client_id"] == "cid")
        #expect(q["redirect_uri"] == "http://127.0.0.1:8765/callback")
        #expect(q["scope"] == "openid \(GoogleAuth.homeScope)")
        #expect(q["code_challenge_method"] == "S256")
        #expect(q["access_type"] == "offline")
        #expect(q["state"] == "st")
        #expect(q["client_secret"] == nil, "the secret never goes in the browser URL")
        #expect(q["include_granted_scopes"] == nil, "merging grants would recreate the forbidden Home+Chat combination")
    }

    @Test func homeAndChatAreNeverRequestedTogether() {
        // Google: "The provided scope combination cannot be used together" (verified live 2026-09-18).
        let home = GoogleAuth.Purpose.home.scopes, chat = GoogleAuth.Purpose.chat.scopes
        #expect(home.contains(GoogleAuth.homeScope))
        #expect(!home.contains(where: { GoogleAuth.chatScopes.contains($0) }))
        #expect(GoogleAuth.chatScopes.allSatisfy(chat.contains))
        #expect(!chat.contains(GoogleAuth.homeScope))
        #expect(home.contains("openid") && chat.contains("openid"), "both learn the user id for own-message muting")
    }

    @Test func chatSlotIsIndependentOfHomeSlot() {
        var s = Secrets(google: GoogleCredentials(clientId: "c", clientSecret: "s", accessToken: "a", refreshToken: "r", scopes: [GoogleAuth.homeScope]))
        #expect(!s.hasChatAccess)
        s.setSlot(.chat, GoogleCredentials(clientId: "c", clientSecret: "s", accessToken: "a2", refreshToken: "r2", scopes: GoogleAuth.chatScopes))
        #expect(s.hasChatAccess)
        #expect(s.slot(.home)?.accessToken == "a")
        s.setSlot(.home, nil)
        #expect(s.hasChatAccess, "signing out of Home leaves Chat alone")
        #expect(OAuthClient.resolve(secrets: s, bundle: Bundle(for: SentinelClass.self))?.clientId == "c", "the chat login can supply the client too")
    }

    @Test func callbackParsing() {
        let ok = GoogleAuth.parseCallback(requestLine: "GET /callback?code=4%2Fabc&state=st HTTP/1.1")
        #expect(ok?.code == "4/abc")
        #expect(ok?.state == "st")
        #expect(ok?.error == nil)
        let denied = GoogleAuth.parseCallback(requestLine: "GET /callback?error=access_denied&state=st HTTP/1.1")
        #expect(denied?.error == "access_denied")
        #expect(GoogleAuth.parseCallback(requestLine: "GET /favicon.ico HTTP/1.1") == nil)
        #expect(GoogleAuth.parseCallback(requestLine: "POST /callback HTTP/1.1") == nil)
    }

    @Test func idTokenClaims() {
        let payload = Data(#"{"sub":"106163","email":"a@b.c"}"#.utf8).base64URLEncoded()
        let claims = GoogleAuth.claims(fromIdToken: "hdr.\(payload).sig")
        #expect(claims.sub == "106163")
        #expect(claims.email == "a@b.c")
        #expect(GoogleAuth.claims(fromIdToken: "garbage").sub == nil)
    }

    @Test func oauthClientResolutionOrder() {
        #expect(OAuthClient.resolve(secrets: Secrets(), bundle: Bundle(for: SentinelClass.self)) == nil,
                "no override and no plist key means no client — sign-in must say so, not crash")
        let override = Secrets(oauthClientIdOverride: "mine", oauthClientSecretOverride: "s")
        #expect(OAuthClient.resolve(secrets: override, bundle: Bundle(for: SentinelClass.self)) == OAuthClient(clientId: "mine", clientSecret: "s"))
    }

    @Test func animportedLoginSuppliesItsOwnClient() {
        // An Antigravity import carries the client that issued the tokens.
        // Without this, Sign In stays greyed out even though a perfectly good
        // client is already on disk, and Settings claims none is configured.
        let imported = Secrets(google: GoogleCredentials(
            clientId: "292687603462-x.apps.googleusercontent.com", clientSecret: "GOCSPX-x",
            accessToken: "a", refreshToken: "r"))
        #expect(OAuthClient.resolve(secrets: imported, bundle: Bundle(for: SentinelClass.self))
                == OAuthClient(clientId: "292687603462-x.apps.googleusercontent.com", clientSecret: "GOCSPX-x"))

        // An explicit override still wins over the imported one.
        var both = imported
        both.oauthClientIdOverride = "mine"
        both.oauthClientSecretOverride = "s"
        #expect(OAuthClient.resolve(secrets: both, bundle: Bundle(for: SentinelClass.self))?.clientId == "mine")

        // A signed-out store with no client anywhere still resolves to nil.
        #expect(OAuthClient.resolve(secrets: Secrets(google: nil), bundle: Bundle(for: SentinelClass.self)) == nil)
    }

    @Test func weeklyExpiryGetsAnActionableHint() {
        #expect(GoogleAuth.refreshFailureMessage("invalid_grant").contains("Testing"))
        #expect(GoogleAuth.refreshFailureMessage("Token has been expired or revoked.").contains("publish"))
        #expect(GoogleAuth.refreshFailureMessage("HTTP 503") == "HTTP 503", "unrelated errors pass through untouched")
    }

    @Test func formEncodingEscapesTokenCharacters() {
        #expect("1//0g+ab/c=".formEncoded == "1%2F%2F0g%2Bab%2Fc%3D")
    }
}

private final class SentinelClass {}

@Suite struct SecretStoreTests {
    @Test func roundTripsWithOwnerOnlyPermissions() throws {
        let store = SecretStore(fileURL: tempDir().appendingPathComponent("secrets.json"))
        try store.update {
            $0.slackToken = "xoxp-test"
            $0.google = GoogleCredentials(clientId: "c", clientSecret: "s", accessToken: "a", refreshToken: "r", expiry: Date(timeIntervalSince1970: 100), scopes: ["x"], userId: "u", email: "e")
        }
        let loaded = store.load()
        #expect(loaded.slackToken == "xoxp-test")
        #expect(loaded.google?.refreshToken == "r")
        #expect(loaded.google?.scopes == ["x"])
        let perms = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test func missingFileIsEmptyNotAnError() {
        let store = SecretStore(fileURL: tempDir().appendingPathComponent("nope.json"))
        #expect(store.load() == Secrets())
    }

    @Test func antigravityImportKeepsClientForRefresh() throws {
        let file = """
        {"https://home.googleapis.com/mcp":{"client_id":"cid","client_secret":"csec",
         "token":{"access_token":"at","token_type":"Bearer","refresh_token":"rt","expiry":"2026-09-18T15:34:45.644315-07:00"},
         "token_url":"https://oauth2.googleapis.com/token"}}
        """
        let creds = try #require(SecretStore.parseAntigravityTokens(Data(file.utf8)))
        #expect(creds.clientId == "cid")
        #expect(creds.clientSecret == "csec")
        #expect(creds.refreshToken == "rt")
        #expect(creds.expiry != nil)
        #expect(creds.hasScope(GoogleAuth.homeScope))
        #expect(SecretStore.parseAntigravityTokens(Data("{}".utf8)) == nil)
    }

    @Test func tokenRefreshWindow() {
        var c = GoogleCredentials(clientId: "c", clientSecret: "s", accessToken: "a", refreshToken: "r", expiry: Date(timeIntervalSinceNow: 3600))
        #expect(!c.needsRefresh())
        c.expiry = Date(timeIntervalSinceNow: 30)
        #expect(c.needsRefresh())
        c.expiry = nil
        #expect(c.needsRefresh(), "unknown expiry means refresh first")
    }

    @Test func configFileNeverContainsSecrets() throws {
        var cfg = SpeakerConfig()
        cfg.chatMonitor = ChatMonitorConfig(slackEnabled: true)
        let text = String(decoding: try JSONEncoder().encode(cfg), as: UTF8.self)
        #expect(!text.contains("token"))
        #expect(!text.contains("secret"))
    }
}

@Suite struct ClaudeHookMergeTests {
    let ours = AgentIntegration.hookCommand(executable: "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker")

    @Test func preservesExistingStopHooks() {
        let existing: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]], "model": "opus"]
        let merged = AgentIntegration.mergeStopHook(into: existing, command: ours)
        let stop = (merged["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        #expect(stop?.count == 2, "the user's hook must survive")
        #expect(merged["model"] as? String == "opus")
        #expect(AgentIntegration.installedHookCommand(in: merged) == ours)
    }

    @Test func isIdempotentAndReplacesStalePaths() {
        let stale = AgentIntegration.hookCommand(executable: "/Users/someone/Downloads/HomeSpeaker.app/Contents/MacOS/HomeSpeaker")
        var s = AgentIntegration.mergeStopHook(into: [:], command: stale)
        s = AgentIntegration.mergeStopHook(into: s, command: ours)
        s = AgentIntegration.mergeStopHook(into: s, command: ours)
        let stop = (s["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        #expect(stop?.count == 1)
        #expect(AgentIntegration.installedHookCommand(in: s) == ours)
    }

    @Test func replacesTheLegacyPythonHook() {
        let legacy: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "python3 /Users/x/.claude/skills/google-home/hooks/stop_broadcast.py", "timeout": 5]]]]]]
        let merged = AgentIntegration.mergeStopHook(into: legacy, command: ours)
        let stop = (merged["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        #expect(stop?.count == 1)
        #expect(AgentIntegration.installedHookCommand(in: merged) == ours)
    }

    @Test func removeLeavesOtherHooksAndTidiesEmptyKeys() {
        let mixed = AgentIntegration.mergeStopHook(
            into: ["hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]], "PreToolUse": []]], command: ours)
        let removed = AgentIntegration.removeStopHook(from: mixed)
        let stop = (removed["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        #expect(stop?.count == 1)
        #expect(AgentIntegration.installedHookCommand(in: removed) == nil)

        let onlyOurs = AgentIntegration.mergeStopHook(into: [:], command: ours)
        #expect(AgentIntegration.removeStopHook(from: onlyOurs)["hooks"] == nil)
    }

    @Test func statusDistinguishesStaleFromInstalled() throws {
        let dir = tempDir()
        let here = AgentIntegration(home: dir, executablePath: "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker")
        #expect(here.hookStatus() == .notInstalled)
        try here.installClaudeCodeHook()
        #expect(here.hookStatus() == .installed)

        let moved = AgentIntegration(home: dir, executablePath: "/opt/HomeSpeaker.app/Contents/MacOS/HomeSpeaker")
        #expect(moved.hookStatus() == .stale(here.hookCommand))
        moved.repairHookIfMoved()
        #expect(moved.hookStatus() == .installed)
        #expect(here.hookStatus() == .stale(moved.hookCommand))

        try moved.removeClaudeCodeHook()
        #expect(moved.hookStatus() == .notInstalled)
    }
}

@Suite struct AntigravityIntegrationTests {
    let exe = "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker"

    @Test func antigravityIsInstructionDrivenNotHooked() {
        #expect(!CodingAgent.antigravity.supportsHook, "agy 1.2.7 never ran a hooks.json hook in any mode we could drive")
        #expect(CodingAgent.claudeCode.supportsHook)
    }

    @Test func existingGeminiSettingsAreNeverTouched() {
        // Even if someone calls the generic writer for Antigravity, the user's
        // own AfterAgent groups (shape from a real ~/.gemini/settings.json) survive.
        let existing: [String: Any] = ["hooks": ["AfterAgent": [["matcher": "*", "hooks": [
            ["name": "stream-to-ui", "type": "command", "command": "/x/stream-hook.py", "timeout": 2000],
        ]]]], "mcpServers": ["slack": ["command": "npx"]]]
        let cmd = AgentIntegration.hookCommand(executable: exe, agent: .antigravity)
        let merged = AgentIntegration.mergeHook(into: existing, command: cmd, agent: .antigravity)
        #expect(((merged["hooks"] as? [String: Any])?["AfterAgent"] as? [[String: Any]])?.count == 1)
        #expect((merged["mcpServers"] as? [String: Any]) != nil)
        let removed = AgentIntegration.removeHook(from: merged, agent: .antigravity)
        #expect(AgentIntegration.installedHookCommand(in: removed, agent: .antigravity) == nil)
    }

    @Test func statusNeverAsksToInstallWhatIsNotThere() throws {
        let home = tempDir()
        let a = AgentIntegration(home: home, executablePath: exe)
        var st = a.status(of: .antigravity)
        #expect(!st.isInstalled)
        #expect(!st.isConfigured)

        // Antigravity present, no instruction yet.
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".gemini/antigravity"), withIntermediateDirectories: true)
        st = a.status(of: .antigravity)
        #expect(st.isInstalled)
        #expect(!st.configuredByInstruction)

        // Adding the instruction makes it configured; doing it twice adds one line.
        try a.addBroadcastInstruction(for: .antigravity)
        try a.addBroadcastInstruction(for: .antigravity)
        let text = try String(contentsOf: home.appendingPathComponent(".gemini/AGENTS.md"), encoding: .utf8)
        #expect(text.components(separatedBy: "home-speaker-broadcast").count == 2, "instruction present exactly once")
        st = a.status(of: .antigravity)
        #expect(st.configuredByInstruction)
        #expect(st.isConfigured)

        // A pre-existing file keeps its content.
        let claudeMd = home.appendingPathComponent(".claude/CLAUDE.md")
        try FileManager.default.createDirectory(at: claudeMd.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Mine\n".write(to: claudeMd, atomically: true, encoding: .utf8)
        try a.addBroadcastInstruction(for: .claudeCode)
        #expect(try String(contentsOf: claudeMd, encoding: .utf8).hasPrefix("# Mine\n"))
        #expect(a.status(of: .claudeCode).configuredByInstruction)
    }

    @Test func aRivalHookFileIsDetectedAndCanBeDisabled() throws {
        let home = tempDir()
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/skills/google-home/hooks"), withIntermediateDirectories: true)
        let rival = home.appendingPathComponent(".claude/skills/google-home/hooks/hooks.json")
        try #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"python3 stop_broadcast.py"}]}]}}"#
            .write(to: rival, atomically: true, encoding: .utf8)

        let a = AgentIntegration(home: home, executablePath: "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker")
        try a.installClaudeCodeHook()
        let st = a.status(of: .claudeCode)
        #expect(st.rivalHook == rival)
        #expect(st.speaksTwice, "our hook plus the skill's hook means every reply plays twice")

        try a.disableRivalHook(for: .claudeCode)
        #expect(!FileManager.default.fileExists(atPath: rival.path))
        #expect(FileManager.default.fileExists(atPath: rival.path + ".disabled-by-homespeaker"), "reversible")
        #expect(!a.status(of: .claudeCode).speaksTwice)
    }

    @Test func repairOnlyTouchesHookCapableAgents() throws {
        let home = tempDir()
        // Write to the path the code itself would use, so this keeps testing
        // the real file if Antigravity's config location moves again.
        let settings = CodingAgent.antigravity.settingsURL(home: home)
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stale: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "\"/old/HomeSpeaker\" --antigravity-hook"]]]]]]
        try JSONSerialization.data(withJSONObject: stale).write(to: settings)
        let a = AgentIntegration(home: home, executablePath: exe)
        #expect(a.status(of: .antigravity).hook == .stale("\"/old/HomeSpeaker\" --antigravity-hook"), "the fixture must be visible to the code under test")
        a.repairHookIfMoved()
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]
        #expect(AgentIntegration.installedHookCommand(in: after ?? [:], agent: .antigravity) == "\"/old/HomeSpeaker\" --antigravity-hook", "left alone")
    }
}

@Suite struct ConfigFileWatchTests {
    /// The Mac agent (acting for the phone) rewrites the config file. The
    /// running app must pick that up, and must NOT treat its own save as an
    /// external edit.
    @Test @MainActor func anExternalEditIsAppliedAndOurOwnSaveIsNot() throws {
        let dir = tempDir()
        let configURL = dir.appendingPathComponent("speaker_broadcast.json")
        let manager = ConfigManager(
            configPath: configURL,
            historyPath: dir.appendingPathComponent("history.json"),
            secrets: SecretStore(fileURL: dir.appendingPathComponent("secrets.json")))
        manager.config.enabled = true
        manager.config.defaultTarget = "kitchen"
        manager.saveConfig()

        // Our own bytes on disk: nothing to do.
        manager.reloadIfChangedExternally()
        #expect(manager.config.defaultTarget == "kitchen")

        // Someone else rewrites the file, the way the agent does: whole-file
        // replace, keys we do not know about left intact.
        var onDisk = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        onDisk["default_target"] = "lake_office"
        onDisk["enabled"] = false
        onDisk["someone_elses_key"] = 1
        try JSONSerialization.data(withJSONObject: onDisk).write(to: configURL, options: .atomic)

        manager.reloadIfChangedExternally()
        #expect(manager.config.defaultTarget == "lake_office")
        #expect(manager.config.enabled == false)
    }

    /// The real path: a directory event, not a test calling reload by hand.
    @Test @MainActor func aRealFileReplacementIsNoticedWithinASecond() async throws {
        let dir = tempDir()
        let configURL = dir.appendingPathComponent("speaker_broadcast.json")
        let manager = ConfigManager(
            configPath: configURL,
            historyPath: dir.appendingPathComponent("history.json"),
            secrets: SecretStore(fileURL: dir.appendingPathComponent("secrets.json")))
        manager.config.defaultTarget = "kitchen"
        manager.saveConfig()
        manager.startWatchingConfigFile()
        defer { manager.stopWatchingConfigFile() }

        var onDisk = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        onDisk["default_target"] = "guest_room"
        try JSONSerialization.data(withJSONObject: onDisk).write(to: configURL, options: .atomic)

        for _ in 0..<40 where manager.config.defaultTarget != "guest_room" {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(manager.config.defaultTarget == "guest_room")
    }
}

@Suite struct SpeechLengthTests {
    /// Five sentences, ~430 characters: longer than a headline, shorter than
    /// the summary cap, so each style has to make a visibly different cut.
    static let reply = """
    The build failed on the macOS lane. The Swift compiler could not find the     SwiftUI macro plugin because the command line tools ship no plugin     directory. Pointing the build at Xcode's own plugin path fixes it.     The same flag is now in the bundle script so releases match.     Nothing else changed.
    """

    @Test func headlineStopsAfterTwoSentences() {
        let spoken = GoogleHomeClient.cleanForSpeech(Self.reply, length: .headline)
        #expect(spoken.hasPrefix("The build failed on the macOS lane."))
        #expect(!spoken.contains("Pointing the build"), "third sentence is dropped")
    }

    @Test func summaryKeepsGoingAndIsTheDefault() {
        let spoken = GoogleHomeClient.cleanForSpeech(Self.reply, length: .summary)
        #expect(spoken.contains("Pointing the build at Xcode"), "the actual answer survives")
        #expect(spoken.count > GoogleHomeClient.cleanForSpeech(Self.reply, length: .headline).count)
        #expect(SpeakerConfig().effectiveSpeechLength == .summary,
                "a config with no speech_length must not fall back to the old two-sentence cut")
    }

    @Test func everyStyleRespectsItsCapAndCutsOnAWord() {
        for style in SpeechLength.allCases {
            let long = String(repeating: "All work and no play makes Jack a dull boy. ", count: 80)
            let spoken = GoogleHomeClient.cleanForSpeech(long, length: style)
            #expect(spoken.count <= style.maxCharacters, "\(style) exceeded its cap")
            #expect(!spoken.contains(" ..."), "no dangling space before the ellipsis")
        }
    }

    @Test func theStoredValueSurvivesAConfigRoundTrip() throws {
        var config = SpeakerConfig()
        config.effectiveSpeechLength = .full
        let data = try JSONEncoder().encode(config)
        #expect(String(data: data, encoding: .utf8)?.contains("\"speech_length\":\"full\"") == true,
                "written under the snake_case key the CLI and skill read")
        #expect(try JSONDecoder().decode(SpeakerConfig.self, from: data).effectiveSpeechLength == .full)
    }
}

@Suite struct ClaudeStopHookTests {
    static let transcript = """
    {"message":{"role":"user","content":[{"type":"text","text":"fix the build"}]}}
    {"message":{"role":"assistant","content":[{"type":"text","text":"Looking."},{"type":"tool_use","input":{"command":"ls"}}]}}
    {"message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}
    {"message":{"role":"assistant","content":[{"type":"text","text":"**Problem.** The build failed. **Fix.** Pinned the SDK.\\n\\nNext: nothing."}]}}
    not json
    """

    @Test func speaksTheLastReplyOfTheCurrentTurn() {
        let entries = ClaudeStopHook.parseTranscript(Self.transcript)
        #expect(entries.count == 4, "unparseable lines are skipped")
        #expect(entries[0].isPlainUserPrompt)
        #expect(!entries[2].isPlainUserPrompt, "a tool_result is not a new prompt")
        let text = ClaudeStopHook.textToSpeak(entries: entries)
        #expect(text?.hasPrefix("**Problem.**") == true)
        #expect(GoogleHomeClient.cleanForSpeech(text ?? "", length: .headline) == "Problem. The build failed.",
                "headline is the first two sentences only")
    }

    @Test func staysQuietWhenTheTurnAlreadySpoke() {
        let spoke = Self.transcript + "\n" + #"{"message":{"role":"assistant","content":[{"type":"tool_use","input":{"command":"speaker-broadcast hi"}}]}}"#
        #expect(ClaudeStopHook.textToSpeak(entries: ClaudeStopHook.parseTranscript(spoke)) == nil)
    }

    /// Regression: a turn that merely *mentions* the broadcaster — editing or
    /// grepping this file, say — must still be spoken. A substring match here
    /// silenced the hook completely on 2026-09-19.
    @Test func codeThatMentionsTheBroadcasterIsNotABroadcast() {
        let code = #"{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"cat > x.swift <<'EOF'\nreturn text.contains(\"speaker-broadcast\")\nEOF"}}]}}"#
        let t = Self.transcript + "\n" + code
        let text = ClaudeStopHook.textToSpeak(entries: ClaudeStopHook.parseTranscript(t))
        #expect(text?.hasPrefix("**Problem.**") == true, "a mention in tool input is data, not a broadcast")
    }

    @Test func onlyRealInvocationsCountAsBroadcasts() {
        #expect(ClaudeStopHook.commandBroadcasts("speaker-broadcast hi"))
        #expect(ClaudeStopHook.commandBroadcasts("cd /tmp && speaker-broadcast hi"))
        #expect(ClaudeStopHook.commandBroadcasts("/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker --say hi"))
        #expect(!ClaudeStopHook.commandBroadcasts(#"grep -n "speaker-broadcast" f.swift"#))
        #expect(!ClaudeStopHook.commandBroadcasts("HomeSpeaker --claude-stop-hook"))
        #expect(!ClaudeStopHook.commandBroadcasts("ls /tmp/claude_broadcast_*.lock"))
    }

    @Test func homeMcpCountsOnlyWithTheBroadcastTrait() {
        #expect(ClaudeStopHook.toolBroadcasts(
            name: "mcp__plugin_google-home_home_mcp__run_home_actions",
            input: ["actions": "SpeakerDevice/AssistantBroadcast"]))
        #expect(!ClaudeStopHook.toolBroadcasts(
            name: "mcp__plugin_google-home_home_mcp__run_home_actions",
            input: ["actions": "OnOff/On"]))
    }

    @Test func earlierTurnsDoNotLeakIn() {
        let t = Self.transcript + "\n" + #"{"message":{"role":"user","content":"and now?"}}"#
        #expect(ClaudeStopHook.textToSpeak(entries: ClaudeStopHook.parseTranscript(t)) == nil,
                "a new prompt with no reply yet means nothing to say")
    }

    @Test func dedupesWithinTheWindow() {
        let dir = tempDir()
        #expect(!ClaudeStopHook.isDuplicate(spoken: "hello", directory: dir))
        #expect(ClaudeStopHook.isDuplicate(spoken: "hello", directory: dir))
        #expect(!ClaudeStopHook.isDuplicate(spoken: "different", directory: dir))
    }

    @Test func sharesTheLegacyPythonHooksLockSoNothingIsSpokenTwice() throws {
        // The 1.x google-home skill still installs stop_broadcast.py, which
        // Claude Code runs alongside ours. It locks on
        // /tmp/claude_broadcast_<sha256(spoken)[:16]>.lock — match it exactly,
        // or both hooks speak the same reply. (Observed live: 15 of 15 replies
        // announced twice before this.)
        let spoken = "Problem. The build failed."
        let digest = SHA256.hash(data: Data(spoken.utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(ClaudeStopHook.dedupeKey(for: spoken) == "claude_broadcast_\(digest.prefix(16)).lock")
        #expect(ClaudeStopHook.lockDirectory.path == "/tmp", "a per-process TMPDIR would never collide with the python hook's")

        // A lock the python hook just wrote silences ours.
        let dir = tempDir()
        let lock = dir.appendingPathComponent(ClaudeStopHook.dedupeKey(for: spoken))
        try String(Date().timeIntervalSince1970).write(to: lock, atomically: true, encoding: .utf8)
        #expect(ClaudeStopHook.isDuplicate(spoken: spoken, directory: dir))
    }

    @Test func runWithoutConfigNeverThrowsOrSpeaks() async {
        // No transcript path -> silent no-op; the hook must never break Claude Code.
        await ClaudeStopHook.run(input: Data("{}".utf8))
        await ClaudeStopHook.run(input: Data("garbage".utf8))
    }
}

@Suite struct ChatMonitorParsingTests {
    @Test func slackMarkupBecomesSpeech() {
        #expect(SlackClient.cleanMarkup("hey <@U123> see <#C1|general> and <https://x.y|the doc> &amp; <https://z.z>") == "hey someone see general and the doc &")
    }

    @Test func slackSearchFiltersBySinceAndSortsOldestFirst() {
        let resp = json(#"{"ok":true,"messages":{"matches":[{"ts":"1700000020.000100","user":"U2","username":"bob","channel":{"name":"dev"},"text":"later"},{"ts":"1700000010.000100","user":"U1","username":"alice","channel":{"name":"general"},"text":"hi <@U9>"},{"ts":"1600000000.0","user":"U0","username":"old","channel":{"name":"x"},"text":"stale"}]}}"#)
        let msgs = SlackClient.parseSearch(resp, after: 1700000000)
        #expect(msgs.map(\.senderName) == ["alice", "bob"])
        #expect(msgs[0].spokenLine == "Slack message from alice in general: hi someone")
        #expect(SlackClient.parseSearch(json(#"{"ok":false,"error":"invalid_auth"}"#), after: 0).isEmpty)
    }

    @Test func googleChatMessagesParse() {
        let space = GoogleChatClient.Space(name: "spaces/A", displayName: "Platform")
        let resp = json(#"{"messages":[{"name":"spaces/A/messages/1","createTime":"2026-09-18T20:00:00.123456Z","sender":{"name":"users/1","displayName":"Ada"},"text":"deploy  done"},{"name":"spaces/A/messages/0","createTime":"2026-09-18T10:00:00Z","sender":{"name":"users/2","displayName":"Old"},"text":"stale"}]}"#)
        let after = ISO8601DateFormatter().date(from: "2026-09-18T12:00:00Z")!
        let msgs = GoogleChatClient.parseMessages(resp, space: space, after: after)
        #expect(msgs.count == 1)
        #expect(msgs[0].senderId == "users/1")
        #expect(msgs[0].spokenLine == "Google Chat message from Ada in Platform: deploy done")
        let spaces = GoogleChatClient.parseSpaces(json(#"{"spaces":[{"name":"spaces/A","displayName":"Platform"},{"name":"spaces/B","spaceType":"DIRECT_MESSAGE"}]}"#))
        #expect(spaces.map(\.displayName) == ["Platform", "a direct message"])
    }
}

@Suite struct GoogleChatSourceTests {
    @Test func selectionFollowsPreferenceAndAvailability() {
        typealias C = ChatMonitorService.ChatSourceChoice
        #expect(ChatMonitorService.chooseChatSource(preference: .auto, hasChatScopes: true, gwsInstalled: true) == C.api, "API wins when both exist")
        #expect(ChatMonitorService.chooseChatSource(preference: .auto, hasChatScopes: false, gwsInstalled: true) == C.gws)
        #expect(ChatMonitorService.chooseChatSource(preference: .auto, hasChatScopes: false, gwsInstalled: false) == C.none(.noGoogleChatSource))
        #expect(ChatMonitorService.chooseChatSource(preference: .gws, hasChatScopes: true, gwsInstalled: false) == C.none(.gwsNotInstalled), "an explicit choice is not silently overridden")
        #expect(ChatMonitorService.chooseChatSource(preference: .api, hasChatScopes: false, gwsInstalled: true) == C.none(.googleChatScopeMissing))
    }

    @Test func ndjsonSpacesParse() {
        let out = """
        {"spaces":[{"name":"spaces/A","displayName":"Platform"}],"nextPageToken":"x"}

        {"spaces":[{"name":"spaces/B","spaceType":"DIRECT_MESSAGE"}]}
        not json
        """
        let spaces = GwsChatClient.parseNDJSONSpaces(out)
        #expect(spaces.map(\.name) == ["spaces/A", "spaces/B"])
    }

    @Test func sourcePreferenceRoundTripsAndDefaultsToAuto() throws {
        var cfg = SpeakerConfig()
        cfg.chatMonitor = ChatMonitorConfig(googleChatEnabled: true, googleChatSource: .gws, gwsAccount: "me@example.com")
        let data = try JSONEncoder().encode(cfg)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let monitor = try #require(json["chat_monitor"] as? [String: Any])
        #expect(monitor["google_chat_source"] as? String == "gws")
        #expect(monitor["gws_account"] as? String == "me@example.com")
        #expect(try JSONDecoder().decode(SpeakerConfig.self, from: data).chatMonitor == cfg.chatMonitor)

        // A config written before these keys existed still decodes.
        let legacy = Data(#"{"enabled":true,"default_target":"k","structure_id":"s","targets":{},"chat_monitor":{"slack_enabled":true,"google_chat_enabled":true,"poll_interval_seconds":30,"mute_own_messages":false}}"#.utf8)
        let old = try JSONDecoder().decode(SpeakerConfig.self, from: legacy).effectiveChatMonitor
        #expect(old.googleChatSource == .auto)
        #expect(old.gwsAccount == "")
        #expect(old.pollIntervalSeconds == 30)
    }

    /// Exercises the real Chat API when this machine has a Chat login in the
    /// default secret store (skips cleanly on CI, which has none).
    @Test func apiListsSpacesWhenChatLoginPresent() async throws {
        guard SecretStore.shared.load().hasChatAccess else { return }
        let client = GoogleChatClient()
        let spaces = try await client.spaces()
        #expect(!spaces.isEmpty, "the Chat API returned no spaces")
        if let first = spaces.first {
            _ = try await client.messages(in: first, after: Date(timeIntervalSinceNow: -7 * 86_400))
        }
    }

    /// Exercises the real gws binary when one is installed on the machine
    /// running the tests (skips cleanly on CI, which has none).
    @Test func gwsListsSpacesWhenInstalled() async throws {
        guard let path = GwsChatClient.locate() else { return }
        let client = GwsChatClient(executable: path, account: "james.nguyen@gmail.com")
        let spaces = try await client.spaces()
        #expect(!spaces.isEmpty, "gws returned no spaces — is it signed in?")
        if let first = spaces.first {
            _ = try await client.messages(in: first, after: Date(timeIntervalSinceNow: -7 * 86_400))
        }
    }
}

@Suite struct VersionConsistencyTests {
    @Test func infoPlistMatchesVersionSwift() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let plist = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let dict = try #require(PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any])
        #expect(dict["CFBundleShortVersionString"] as? String == HomeSpeakerVersion.current,
                "Resources/Info.plist is release-please managed; it must track Version.swift")
        #expect(dict["CFBundleIdentifier"] as? String == "com.vitruviansoftware.homespeaker")
    }
}
