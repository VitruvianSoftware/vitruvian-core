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
/// secrets, the speakers on that sign-in, and the announcer on those
/// speakers. Two engines on two profiles share no file.
///
/// `HomeSpeakerEngine.app` is the app's engine. Its parts are the existing
/// `.shared` singletons themselves, so every caller of `.shared` keeps
/// using exactly the objects it did.
@MainActor
public final class HomeSpeakerEngine {
    public let profile: HomeSpeakerProfile
    public let config: ConfigManager
    public let secrets: SecretStore
    public let history: BroadcastHistory
    public let auth: GoogleAuth
    public let home: GoogleHomeClient
    public let announcer: Announcer

    /// The app's engine: today's files, and the `.shared` singletons.
    public static let app = HomeSpeakerEngine(
        profile: .app(),
        config: .shared,
        secrets: .shared,
        history: .shared,
        auth: .shared,
        home: .shared,
        announcer: .shared)

    /// A new engine on `profile`'s files. `session` carries the sign-in's
    /// and the speakers' requests; `local` speaks on this Mac.
    public convenience init(
        profile: HomeSpeakerProfile,
        session: URLSession = .shared,
        local: LocalSpeaking = LocalSpeaker.shared
    ) {
        let secrets = SecretStore(fileURL: profile.secretsURL)
        let history = BroadcastHistory(fileURL: profile.historyURL)
        let auth = GoogleAuth(store: secrets, session: session)
        let home = GoogleHomeClient(auth: auth, session: session)
        self.init(
            profile: profile,
            config: ConfigManager(configPath: profile.settingsURL, history: history, secrets: secrets),
            secrets: secrets,
            history: history,
            auth: auth,
            home: home,
            announcer: Announcer(home: home, local: local))
    }

    private init(
        profile: HomeSpeakerProfile,
        config: ConfigManager,
        secrets: SecretStore,
        history: BroadcastHistory,
        auth: GoogleAuth,
        home: GoogleHomeClient,
        announcer: Announcer
    ) {
        self.profile = profile
        self.config = config
        self.secrets = secrets
        self.history = history
        self.auth = auth
        self.home = home
        self.announcer = announcer
    }
}
