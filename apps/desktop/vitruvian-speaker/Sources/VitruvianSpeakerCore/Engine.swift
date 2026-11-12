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

import Foundation

/// One HomeSpeaker's working parts, built from one profile so they agree:
/// the settings, the secrets, the history, the Google sign-in on those
/// secrets, the speakers on that sign-in, the announcer on those speakers,
/// and the media-pause and volume-restore coordinators. Two engines on two
/// profiles share no file, and send each other no message.
///
/// `HomeSpeakerEngine.app` is the app's engine. Its parts are the existing
/// `.shared` singletons themselves, so every caller of `.shared` keeps
/// using exactly the objects it did.
///
/// Building an engine reads and writes no file. The settings are read the
/// first time `config` is asked for, because reading them can write the
/// defaults (no file) or print a problem (a file that does not read), and a
/// command such as `--version` must do neither.
@MainActor
public final class HomeSpeakerEngine {
    public let profile: HomeSpeakerProfile
    /// The settings, read on first use.
    public private(set) lazy var config: ConfigManager = {
        configLoaded = true
        return makeConfig()
    }()
    /// True once `config` has been asked for: the settings file was read.
    public private(set) var configLoaded = false
    private let makeConfig: @MainActor () -> ConfigManager
    public let secrets: SecretStore
    public let history: BroadcastHistory
    public let auth: GoogleAuth
    public let home: GoogleHomeClient
    public let announcer: Announcer
    /// Holds paused media for the profile's short-lived processes.
    public let mediaPause: MediaPauseCoordinator
    /// Puts speakers back after the profile's announcements.
    public let volumeRestore: VolumeRestoreCoordinator

    /// The app's engine: today's files, and the `.shared` singletons.
    public static let app = HomeSpeakerEngine(
        profile: .app(),
        config: { .shared },
        secrets: .shared,
        history: .shared,
        auth: .shared,
        home: .shared,
        announcer: .shared,
        mediaPause: .shared,
        volumeRestore: .shared)

    /// A new engine on `profile`'s files and message names. `session`
    /// carries the sign-in's and the speakers' requests; `local` speaks on
    /// this Mac.
    public convenience init(
        profile: HomeSpeakerProfile,
        session: URLSession = .shared,
        local: LocalSpeaking = LocalSpeaker.shared
    ) {
        let secrets = SecretStore(fileURL: profile.secretsURL)
        let history = BroadcastHistory(fileURL: profile.historyURL)
        let auth = GoogleAuth(store: secrets, session: session, shippedClient: { profile.shippedClient })
        let home = GoogleHomeClient(auth: auth, session: session, messages: profile)
        self.init(
            profile: profile,
            config: { ConfigManager(configPath: profile.settingsURL, history: history, secrets: secrets) },
            secrets: secrets,
            history: history,
            auth: auth,
            home: home,
            announcer: Announcer(
                home: home, local: local, media: SharedMediaPause(profile: profile),
                geminiKey: { secrets.load().geminiApiKey }, speechLockURL: profile.speechLockURL),
            mediaPause: MediaPauseCoordinator(),
            volumeRestore: VolumeRestoreCoordinator(client: home))
    }

    private init(
        profile: HomeSpeakerProfile,
        config: @escaping @MainActor () -> ConfigManager,
        secrets: SecretStore,
        history: BroadcastHistory,
        auth: GoogleAuth,
        home: GoogleHomeClient,
        announcer: Announcer,
        mediaPause: MediaPauseCoordinator,
        volumeRestore: VolumeRestoreCoordinator
    ) {
        self.profile = profile
        self.makeConfig = config
        self.secrets = secrets
        self.history = history
        self.auth = auth
        self.home = home
        self.announcer = announcer
        self.mediaPause = mediaPause
        self.volumeRestore = volumeRestore
    }

    /// Makes this process the profile's long-lived one: it holds paused
    /// media and puts speakers back for the Stop hook and `--say`, which
    /// exit before an announcement ends. Listens on the profile's names
    /// only. Keep the tokens to stop listening.
    public func listen() -> [NSObjectProtocol] {
        [
            MediaPauseRequest.listen(with: mediaPause, profile: profile),
            VolumeRestoreRequest.listen(with: volumeRestore, profile: profile),
        ]
    }

    /// Signs this HomeSpeaker out of every Google login, or only Google
    /// Chat's, through the one sign-out path (`AppCommandRunner.signOut`).
    ///
    /// `otherSecrets` is the other HomeSpeaker's sign-ins, when it is
    /// installed. Each login is decided on its own (design 7.7): one the
    /// other side shares (`sharedLogins`) is removed here only and never
    /// revoked at Google, because revoking it would end the other side's
    /// sign-in; every other login is revoked, as it always was.
    ///
    /// `notify` is told on success; the default tells no one.
    public func signOut(
        chatOnly: Bool, otherSecrets: Secrets?,
        notify: @Sendable (_ chatOnly: Bool) -> Void = { _ in }
    ) async -> CLIOutput {
        let purposes: [GoogleAuth.Purpose] = chatOnly ? [.chat] : GoogleAuth.Purpose.allCases
        let shared = Self.sharedLogins(secrets.load(), purposes: purposes, with: otherSecrets)
        let store = secrets
        return await AppCommandRunner.signOut(
            chatOnly: chatOnly, revoke: { !shared.contains($0) }, auth: auth,
            signedIn: {
                let stored = store.load()
                return Set(GoogleAuth.Purpose.allCases.filter { stored.slot($0) != nil })
            },
            notify: notify)
    }

    /// Which of `purposes` sign `mine` in with a login the other side
    /// shares, so it must not be revoked.
    ///
    /// Revoking at Google most likely ends the whole grant for that OAuth
    /// client and Google account, not one token, and both sides ship the
    /// same client. So a login here counts as shared when the other side
    /// holds a login (either slot) with the same refresh token, or with the
    /// same client id and an account that is the same or cannot be told
    /// (not stored on either side). Only a login whose client differs, or
    /// whose account is known to differ, is revoked.
    nonisolated static func sharedLogins(
        _ mine: Secrets, purposes: [GoogleAuth.Purpose], with other: Secrets?
    ) -> Set<GoogleAuth.Purpose> {
        guard let other else { return [] }
        let theirs = [other.google, other.googleChat].compactMap { $0 }
        return Set(purposes.filter { purpose in
            guard let login = mine.slot(purpose) else { return false }
            return theirs.contains { Self.sameGrant(login, $0) }
        })
    }

    /// Might revoking `a` end `b`? See `sharedLogins`.
    nonisolated static func sameGrant(_ a: GoogleCredentials, _ b: GoogleCredentials) -> Bool {
        if !a.refreshToken.isEmpty, a.refreshToken == b.refreshToken { return true }
        guard a.clientId == b.clientId else { return false }
        return !knownDifferentAccounts(a, b)
    }

    /// True only when both logins name their account and the accounts
    /// differ: by Google account id when both have one, else by email.
    nonisolated static func knownDifferentAccounts(_ a: GoogleCredentials, _ b: GoogleCredentials) -> Bool {
        func known(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        if let idA = known(a.userId), let idB = known(b.userId) { return idA != idB }
        if let mailA = known(a.email), let mailB = known(b.email) {
            return mailA.caseInsensitiveCompare(mailB) != .orderedSame
        }
        return false
    }

    /// Takes the sign-out and credentials-changed notices on the profile's
    /// names: re-reads the login, then stops, starts or restarts `monitor`.
    /// The engine owns no chat monitor; whoever runs one passes it.
    public func listenForNotices(monitor: any ChatMonitorControlling) -> [NSObjectProtocol] {
        [
            SignOutNotice.listen(
                name: SignOutNotice.notificationName(for: profile), config: config, monitor: monitor),
            CredentialsChangedNotice.listen(
                name: CredentialsChangedNotice.notificationName(for: profile), config: config, monitor: monitor),
        ]
    }
}
