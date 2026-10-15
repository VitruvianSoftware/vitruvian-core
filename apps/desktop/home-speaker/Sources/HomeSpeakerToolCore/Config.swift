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
/// share. The tool reads it before each page and writes it back through
/// `SpeakerConfigFile`, as the app does: merged into what is there, so keys
/// the tool does not know survive, and never over a file that does not
/// read. The app watches the folder and follows within a second.
public protocol ConfigStore: AnyObject {
    /// Nil when there is no file, or none that reads.
    func load() -> SpeakerConfig?
    func save(_ config: SpeakerConfig) throws
}

public final class FileConfigStore: ConfigStore {
    public let file: SpeakerConfigFile
    public var url: URL { file.url }

    public init(url: URL = ConfigManager.defaultConfigURL(), fileSystem: ConfigFileSystem = LocalConfigFileSystem()) {
        self.file = SpeakerConfigFile(url: url, fileSystem: fileSystem)
    }

    public func load() -> SpeakerConfig? {
        if case .loaded(let config) = file.read() { return config }
        return nil
    }

    /// Throws, writing nothing, when the file there does not read as
    /// HomeSpeaker's settings: the tool would otherwise save its defaults
    /// over them.
    public func save(_ config: SpeakerConfig) throws {
        try file.write(config)
    }
}

extension SpeakerConfig {
    /// "HH:mm", as the file keeps a quiet hour; nil for anything else.
    public static func quietHour(_ text: String) -> String? {
        Self.minutesSinceMidnight(text) == nil ? nil : text.trimmingCharacters(in: .whitespaces)
    }
}
