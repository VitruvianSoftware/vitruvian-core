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

// Which HomeSpeaker is in use, when the app and the Vitruvian extension are
// both on this Mac (design section 7).
//
// One file, `~/.gemini/speaker_door.json`, records the person's choice and
// where the extension lives. Each side reads it, works out whether the
// other is installed, and from those two answers whether it runs, runs and
// asks, waits and asks, or stays quiet.

// MARK: - The record

/// What `speaker_door.json` says (design section 7.1):
///
/// ```json
/// {
///   "version": 1,
///   "chosen": "extension",
///   "chosen_at": "2026-10-20T09:12:00Z",
///   "chosen_by": "HomeSpeaker extension 1.19.0",
///   "extension": { "program": "…/bin/tool", "data_folder": "…", "version": "1.19.0", "door": 1 }
/// }
/// ```
///
/// Reading is forgiving: a field that is missing, of the wrong type, or a
/// `chosen` this version does not know reads as absent, rather than making
/// the whole file unreadable.
public struct DoorRecord: Codable, Equatable, Sendable {
    /// The file's format. Always 1 so far.
    public var version: Int
    /// The HomeSpeaker the person picked; nil while nobody has.
    public var chosen: HomeSpeakerProfile.Door?
    /// When they picked.
    public var chosenAt: Date?
    /// Which program recorded the pick, in words, for display.
    public var chosenBy: String?
    /// The extension's own block. Written by an extension that can run
    /// without the app, each time it starts; nil until one has.
    public var installedExtension: ExtensionEntry?

    /// The `extension` block.
    public struct ExtensionEntry: Codable, Equatable, Sendable {
        /// The extension's program, `…/Tools/<id>/bin/tool`.
        public var program: String
        /// Its data folder, `…/ToolData/<id>`.
        public var dataFolder: String?
        /// Its version, for display only: whether it runs alone is `door`.
        public var version: String?
        /// Present, and at least `ExtensionEntry.runsAlone`, when the
        /// extension runs without the app. An extension that only drives
        /// the app never writes this block at all (design section 8); the
        /// mark is what counts, not a version number, which a release could
        /// change.
        public var door: Int?

        /// The `door` an extension that runs without the app writes.
        public static let runsAlone = 1

        public init(program: String, dataFolder: String?, version: String?, door: Int?) {
            self.program = program
            self.dataFolder = dataFolder
            self.version = version
            self.door = door
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case program
            case dataFolder = "data_folder"
            case version
            case door
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            program = try c.decode(String.self, forKey: .program)
            dataFolder = try? c.decodeIfPresent(String.self, forKey: .dataFolder)
            version = try? c.decodeIfPresent(String.self, forKey: .version)
            door = try? c.decodeIfPresent(Int.self, forKey: .door)
        }
    }

    public static let currentVersion = 1

    public init(
        version: Int = DoorRecord.currentVersion, chosen: HomeSpeakerProfile.Door? = nil, chosenAt: Date? = nil,
        chosenBy: String? = nil, installedExtension: ExtensionEntry? = nil
    ) {
        self.version = version
        self.chosen = chosen
        self.chosenAt = chosenAt
        self.chosenBy = chosenBy
        self.installedExtension = installedExtension
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case version
        case chosen
        case chosenAt = "chosen_at"
        case chosenBy = "chosen_by"
        case installedExtension = "extension"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? Self.currentVersion
        chosen = ((try? c.decodeIfPresent(String.self, forKey: .chosen)) ?? nil).flatMap(HomeSpeakerProfile.Door.init(rawValue:))
        chosenAt = ((try? c.decodeIfPresent(String.self, forKey: .chosenAt)) ?? nil).flatMap(Self.dates.date(from:))
        chosenBy = try? c.decodeIfPresent(String.self, forKey: .chosenBy)
        installedExtension = try? c.decodeIfPresent(ExtensionEntry.self, forKey: .installedExtension)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encodeIfPresent(chosen?.rawValue, forKey: .chosen)
        try c.encodeIfPresent(chosenAt.map(Self.dates.string(from:)), forKey: .chosenAt)
        try c.encodeIfPresent(chosenBy, forKey: .chosenBy)
        try c.encodeIfPresent(installedExtension, forKey: .installedExtension)
    }

    /// `2026-10-20T09:12:00Z`. A formatter is not Sendable, so each use
    /// makes its own.
    private static var dates: ISO8601DateFormatter { ISO8601DateFormatter() }
}

// MARK: - The file

public enum DoorFileError: Error, Equatable, LocalizedError {
    /// The file is there but is not a JSON object. Writing over it would
    /// throw away whatever is in it.
    case unreadable(path: String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let path):
            return "\(path) could not be read. HomeSpeaker will not save over it until it reads again; fix or remove the file."
        }
    }
}

/// `~/.gemini/speaker_door.json`, beside the app's settings, in the folder
/// the app already watches. Written under its own lock, merged into what is
/// on disk, never replaced blind: a key this version does not know survives,
/// at the top and inside the `extension` block.
public struct DoorFile: Sendable {
    public static let fileName = "speaker_door.json"

    public let url: URL
    /// `speaker_door.json.lock`: a file of its own, so the atomic replace
    /// of the record never swaps the locked file out from under a writer.
    public var lockURL: URL { url.appendingPathExtension("lock") }

    public init(url: URL = DoorFile.defaultURL()) {
        self.url = url
    }

    /// `<home>/.gemini/speaker_door.json`.
    public static func defaultURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".gemini").appendingPathComponent(fileName)
    }

    /// The record, or nil when there is no file or it does not read.
    public func read() -> DoorRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DoorRecord.self, from: data)
    }

    /// Reads the record (a new one when there is no file), lets `change`
    /// change it, and writes it back merged, all under the lock, so two
    /// writers at once both land. Throws `DoorFileError.unreadable`, writing
    /// nothing, when the file is there but is not a JSON object.
    public func update(_ change: (inout DoorRecord) -> Void) throws {
        try FileLock.withExclusiveLock(at: lockURL) {
            var onDisk: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: url.path) {
                guard let data = try? Data(contentsOf: url),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw DoorFileError.unreadable(path: url.path)
                }
                onDisk = object
            }
            let before = try Self.decode(onDisk)
            var after = before
            change(&after)
            let merged = try Self.merge(Self.object(after), changedFrom: Self.object(before), over: onDisk)
            let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }

    private static func decode(_ object: [String: Any]) throws -> DoorRecord {
        try JSONDecoder().decode(DoorRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private static func object(_ record: DoorRecord) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any] ?? [:]
    }

    static let recordKeys = DoorRecord.CodingKeys.allCases.map(\.rawValue)
    static let extensionKeys = DoorRecord.ExtensionEntry.CodingKeys.allCases.map(\.rawValue)

    /// `onDisk`, with each of the record's keys that `change` changed set
    /// from `after` (removed when `after` has none). A key the change did
    /// not touch keeps what is on disk, even a value this version could not
    /// read; a key that is not the record's is never touched. The
    /// `extension` block follows the same rule, key by key.
    static func merge(_ after: [String: Any], changedFrom before: [String: Any], over onDisk: [String: Any]) -> [String: Any] {
        var out = onDisk
        if out["version"] == nil { out["version"] = after["version"] }
        for key in recordKeys where !same(after[key], before[key]) {
            guard let value = after[key] else {
                out.removeValue(forKey: key)
                continue
            }
            if key == DoorRecord.CodingKeys.installedExtension.rawValue,
               let block = value as? [String: Any], let old = onDisk[key] as? [String: Any] {
                // The same rule inside the block: a key the change touched is
                // set from the record (removed when it has none); a key it did
                // not touch, or one this version could not read, keeps what is
                // on disk, as does anything that is not the block's.
                let was = before[key] as? [String: Any] ?? [:]
                var merged = old
                for k in extensionKeys where !same(block[k], was[k]) {
                    if let v = block[k] { merged[k] = v } else { merged.removeValue(forKey: k) }
                }
                out[key] = merged
            } else {
                out[key] = value
            }
        }
        return out
    }

    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let a?, let b?): return (a as AnyObject).isEqual(b)
        default: return false
        }
    }
}

// MARK: - Who runs

/// What one HomeSpeaker does, given the other and the choice (design 7.3).
public enum DoorRole: Equatable, Sendable {
    /// Runs: the hook, the chat monitor, listening.
    case active
    /// Runs, and asks the person to pick. The app, while nobody has: every
    /// user who has both had the app first, so nothing they rely on stops.
    case activeAsking
    /// Does only what the person asks by hand, and asks them to pick. The
    /// extension, while nobody has: it leaves the hook alone and does not
    /// start the chat monitor.
    case waitingAsking
    /// The other one is chosen: no hook, no monitor, no listening.
    case quiet(other: HomeSpeakerProfile.Door)

    /// Design table 7.3:
    ///
    /// | The other one installed? | `chosen` | This one is |
    /// |---|---|---|
    /// | No | anything | active |
    /// | Yes | this one | active |
    /// | Yes | the other | quiet |
    /// | Yes | absent | the app: active, asking. The extension: waiting, asking |
    public static func decide(
        me: HomeSpeakerProfile.Door, otherInstalled: Bool, chosen: HomeSpeakerProfile.Door?
    ) -> DoorRole {
        guard otherInstalled else { return .active }
        switch chosen {
        case me?: return .active
        case let other?: return .quiet(other: other)
        case nil: return me == .app ? .activeAsking : .waitingAsking
        }
    }

    /// True when this one stays out of the other's way.
    public var isQuiet: Bool {
        if case .quiet = self { return true }
        return false
    }
}

// MARK: - Is the other one installed

/// How each side tells whether the other is installed (design 7.2).
public enum OtherDoorPresence {
    /// A path inside a Trash: the home one (`~/.Trash`) or a volume's
    /// (`/Volumes/<disk>/.Trashes/<uid>`). Launch Services still knows apps
    /// there, and the extension's program could be dragged there too.
    public static func isInTrash(_ path: String) -> Bool {
        path.contains("/.Trash/") || path.contains("/.Trashes/")
    }

    /// A path on a mounted disk image (`/Volumes/…`) or inside a Gatekeeper
    /// AppTranslocation mount (`/AppTranslocation/`). Launching the app from
    /// there before dragging to `/Applications` must not point hooks at the
    /// temporary mount.
    public static func isOnTemporaryVolume(_ path: String) -> Bool {
        path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }

    /// The extension asks: is the app installed? `locate` finds the app's
    /// program as the tool does (`ProcessDriver.locate`); a copy in the
    /// Trash does not count.
    public static func appInstalled(locate: () -> URL?) -> Bool {
        guard let program = locate() else { return false }
        return !isInTrash(program.path)
    }

    /// The app asks: is an extension installed that runs without the app?
    /// Its block is in the choice file, carries the mark
    /// (`ExtensionEntry.runsAlone`), and names a program that exists and is
    /// not in the Trash. An older extension drives the app and writes no
    /// block, so the app treats it as a remote control, as today.
    public static func extensionInstalled(record: DoorRecord?, fileExists: (String) -> Bool) -> Bool {
        guard let entry = record?.installedExtension,
              let door = entry.door, door >= DoorRecord.ExtensionEntry.runsAlone else { return false }
        return !isInTrash(entry.program) && fileExists(entry.program)
    }
}

// MARK: - Putting it together

/// One side's view: the choice file, and how to tell whether the other side
/// is installed. Each check reads the file afresh.
public struct DoorCheck: Sendable {
    public let file: DoorFile
    /// Is the app installed? Asked only when this side is the extension:
    /// `OtherDoorPresence.appInstalled` with the tool's `ProcessDriver.locate`.
    public let appInstalled: @Sendable () -> Bool
    /// Does a file exist at this path? Asked of the extension's program
    /// only when this side is the app.
    public let fileExists: @Sendable (String) -> Bool

    public init(
        file: DoorFile = DoorFile(),
        appInstalled: @escaping @Sendable () -> Bool,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.file = file
        self.appInstalled = appInstalled
        self.fileExists = fileExists
    }

    /// What `me` does now.
    public func role(me: HomeSpeakerProfile.Door) -> DoorRole {
        let record = file.read()
        let otherInstalled: Bool
        switch me {
        case .app: otherInstalled = OtherDoorPresence.extensionInstalled(record: record, fileExists: fileExists)
        case .extension: otherInstalled = appInstalled()
        }
        return DoorRole.decide(me: me, otherInstalled: otherInstalled, chosen: record?.chosen)
    }

    /// The command line's stand-aside check (`HomeSpeakerCommandLine.Parts`):
    /// true exactly when `role(me:)` is quiet, so the hook and `--announce`
    /// say nothing while the other one is chosen and installed.
    public func standsAside(me: HomeSpeakerProfile.Door) -> Bool {
        role(me: me).isQuiet
    }
}
