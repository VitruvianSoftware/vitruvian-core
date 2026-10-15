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
            announcer: Announcer(home: home, local: local, media: SharedMediaPause(profile: profile)),
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
