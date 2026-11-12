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

// Where a short-lived HomeSpeaker process sends what only a long-lived one
// can do: hold paused media, put a speaker back.
//
// `speaker-broadcast` always runs the app's program (`HomeSpeaker --say`),
// whichever HomeSpeaker the person picked. With the extension picked, the
// app is quiet or not running, so a pause posted under the app's names
// reached nobody and the media never paused. A request now goes to the
// HomeSpeaker that is in use and alive, under that one's names.

/// Picks the long-lived process that takes a request meant for a profile.
public struct RequestRoute: Sendable {
    /// The profiles whose long-lived process may take `profile`'s requests,
    /// best first.
    public var candidates: @Sendable (HomeSpeakerProfile) -> [HomeSpeakerProfile]
    /// Is that profile's long-lived process running and listening?
    public var alive: @Sendable (HomeSpeakerProfile) -> Bool

    public init(
        candidates: @escaping @Sendable (HomeSpeakerProfile) -> [HomeSpeakerProfile],
        alive: @escaping @Sendable (HomeSpeakerProfile) -> Bool
    ) {
        self.candidates = candidates
        self.alive = alive
    }

    /// The first candidate that is alive; nil when none is.
    public func listener(for profile: HomeSpeakerProfile) -> HomeSpeakerProfile? {
        candidates(profile).first(where: alive)
    }

    /// The real one: the choice file decides the order, and the running
    /// app or the extension's live lock decides who is alive.
    public static func live(
        runningApps: @escaping @Sendable () -> [HomeSpeakerProfile.RunningApp] = HomeSpeakerProfile.runningApps
    ) -> RequestRoute {
        RequestRoute(
            candidates: { profile in
                candidates(
                    for: profile, record: DoorFile(url: doorURL(for: profile)).read(),
                    fileExists: { FileManager.default.fileExists(atPath: $0) })
            },
            alive: { $0.ownerRunning(runningApps: runningApps) })
    }

    /// The choice file a profile reads: beside the app's settings for the
    /// app (so a test's scratch home has its own), the person's for the
    /// extension.
    static func doorURL(for profile: HomeSpeakerProfile) -> URL {
        switch profile.door {
        case .app: return profile.settingsURL.deletingLastPathComponent().appendingPathComponent(DoorFile.fileName)
        case .extension: return DoorFile.defaultURL()
        }
    }

    /// Who may take `profile`'s requests, best first:
    ///
    /// | This side | The choice | Candidates |
    /// |---|---|---|
    /// | app | the extension, installed (the app is quiet and does not listen) | the extension |
    /// | app | anything else | the app, then the extension |
    /// | extension | the app | the app, then the extension |
    /// | extension | the extension (the app is quiet) | the extension |
    /// | extension | nobody yet | the extension, then the app |
    ///
    /// A profile under names of its own (every test's) only ever reaches
    /// itself, so a test never pauses the Mac's real media.
    static func candidates(
        for profile: HomeSpeakerProfile, record: DoorRecord?, fileExists: (String) -> Bool
    ) -> [HomeSpeakerProfile] {
        switch (profile.door, profile.messagePrefix) {
        case (.app, HomeSpeakerProfile.appMessagePrefix):
            let ext = AppStartup.extensionProfile(record: record)
            if AppStartup.role(record: record, fileExists: fileExists).isQuiet, let ext { return [ext] }
            return [profile] + (ext.map { [$0] } ?? [])
        case (.extension, HomeSpeakerProfile.extensionMessagePrefix):
            let app = HomeSpeakerProfile.app(
                home: DoorFile.defaultURL().deletingLastPathComponent().deletingLastPathComponent())
            switch record?.chosen {
            case .app?: return [app, profile]
            case .extension?: return [profile]
            case nil: return [profile, app]
            }
        default:
            return [profile]
        }
    }
}
