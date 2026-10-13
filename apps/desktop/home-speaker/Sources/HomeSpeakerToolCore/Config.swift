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
import HomeSpeakerCore

/// HomeSpeaker's settings file, `~/.gemini/speaker_broadcast.json`: the
/// contract the app, the `speaker-broadcast` command and the Mac agent
/// share. The tool reads it before each page and writes it back whole, as
/// the app does; the app watches the folder and follows within a second.
public protocol ConfigStore: AnyObject {
    /// Nil when there is no file, or none that reads.
    func load() -> SpeakerConfig?
    func save(_ config: SpeakerConfig) throws
}

public final class FileConfigStore: ConfigStore {
    public let url: URL

    public init(url: URL = ConfigManager.defaultConfigURL()) {
        self.url = url
    }

    public func load() -> SpeakerConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SpeakerConfig.self, from: data)
    }

    /// Written as the app writes it: pretty, keys sorted, in one move.
    public func save(_ config: SpeakerConfig) throws {
        let folder = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}

extension SpeakerConfig {
    /// "HH:mm", as the file keeps a quiet hour; nil for anything else.
    public static func quietHour(_ text: String) -> String? {
        Self.minutesSinceMidnight(text) == nil ? nil : text.trimmingCharacters(in: .whitespaces)
    }
}
