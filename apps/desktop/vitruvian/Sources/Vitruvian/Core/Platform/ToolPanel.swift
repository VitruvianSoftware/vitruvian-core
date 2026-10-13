// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianToolProtocol

/// Where the app shows a tool's panel. The protocol's list, mapped onto the
/// app's own, so that a placement the app does not have is a refusal that
/// names it.
package enum ToolPanelPlacement: String, CaseIterable, Sendable {
    /// A page in the island's Tools area.
    case island
    /// A part of the tool's detail in Settings.
    case settings
    /// A window the app owns.
    case window
}

/// One panel of a tool from outside, as its manifest describes it.
package struct ToolPanelDescriptor: Equatable, Sendable {
    /// The panel's name within the tool, as the messages name it.
    package let id: String
    /// What it is called, in every language its author wrote.
    package let title: LocalizedText
    package let placement: ToolPanelPlacement
    /// An SF Symbol name: the panel's own, else the tool's.
    package let symbol: String
    /// A web panel's page, as a path inside the tool's folder. Nil for a
    /// panel the app draws from blocks.
    package let entry: String?

    package init(id: String, title: LocalizedText, placement: ToolPanelPlacement, symbol: String,
                 entry: String? = nil) {
        self.id = id
        self.title = title
        self.placement = placement
        self.symbol = symbol
        self.entry = entry
    }

    /// True for a panel that is a web page.
    package var isWeb: Bool { entry != nil }
}

/// Why a page a tool sent is not drawn. The panel keeps the page it had,
/// and the tool's log says which of these it was.
package enum ToolPanelProblem: Error, Equatable, Sendable {
    /// Over `UILimits.maxTreeBytes`, as the app writes it again.
    case tooLarge(bytes: Int)
    /// Not a page: a field missing or of the wrong kind, where.
    case notWellFormed(String)
}

/// Reading a page a tool sent. It can take a while for a large page, so the
/// panel host runs it away from the main thread; it touches nothing but its
/// argument.
package enum ToolPanelTree {
    /// The page in `value`, or why it is not drawn. A page over the limit
    /// is refused before it is read; a block of a kind the app does not
    /// know is kept, to be drawn as its fallback; a block of a kind it knows
    /// with a field missing or of the wrong kind refuses the whole page.
    package static func read(_ value: JSONValue) -> Result<UITree, ToolPanelProblem> {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return .failure(.notWellFormed("not JSON")) }
        guard data.count <= UILimits.maxTreeBytes else { return .failure(.tooLarge(bytes: data.count)) }
        do {
            return .success(try JSONDecoder().decode(UITree.self, from: data))
        } catch let error as DecodingError {
            return .failure(.notWellFormed(location(of: error)))
        } catch {
            return .failure(.notWellFormed("\(error)"))
        }
    }

    /// Where in the page a reading went wrong, as `blocks[2].title`.
    static func location(of error: DecodingError) -> String {
        func path(_ keys: [any CodingKey]) -> String {
            let text = keys.map { key in key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)" }.joined()
            return text.isEmpty ? "the page" : String(text.drop(while: { $0 == "." }))
        }
        switch error {
        case .keyNotFound(let key, let context): return path(context.codingPath + [key])
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return path(context.codingPath)
        @unknown default: return "the page"
        }
    }
}

/// What a web panel may load and go to: files of the tool's own folder, and
/// nothing else. The page's own requests for data (`fetch`) are not
/// navigations and are not asked here: the tool is trusted like an app.
package enum ToolWebPolicy {
    /// True for a page the panel may show: a `file:` address that is, once
    /// every link is followed, inside `folder`, or the empty page WebKit
    /// starts from.
    package static func allows(_ url: URL, in folder: URL) -> Bool {
        if url.absoluteString == "about:blank" { return true }
        guard url.isFileURL else { return false }
        return isInside(url, folder)
    }

    /// The page a panel starts at: `entry` inside `folder`, when it is a
    /// file there, with every link followed.
    package static func entry(_ entry: String, in folder: URL) -> URL? {
        guard ManifestRules.staysInsideFolder(entry) else { return nil }
        let page = folder.appendingPathComponent(entry)
        var isFolder: ObjCBool = false
        guard isInside(page, folder), FileManager.default.fileExists(atPath: page.path, isDirectory: &isFolder),
              !isFolder.boolValue else { return nil }
        return page.resolvingSymlinksInPath().standardizedFileURL
    }

    /// Whether `url`, with every link followed, names something inside
    /// `folder`, also with every link followed: its parts begin with all of
    /// the folder's parts, and have one more at least.
    static func isInside(_ url: URL, _ folder: URL) -> Bool {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let file = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        return file.count > root.count && Array(file.prefix(root.count)) == root
    }
}

/// Where a picture of an `image` block comes from.
package enum ToolPanelImage: Equatable, Sendable {
    /// A file inside the tool's folder.
    case file(URL)
    /// The picture's own bytes, from a `data:` address.
    case bytes(Data)

    /// The picture `source` names, or nil for one the app does not draw: a
    /// path that leaves the folder, a file that is not there, or a `data:`
    /// address that is not a PNG or a JPEG in base64.
    package static func resolve(_ source: String, in folder: URL) -> ToolPanelImage? {
        if source.hasPrefix("data:") {
            for kind in ["data:image/png;base64,", "data:image/jpeg;base64,"] where source.hasPrefix(kind) {
                return Data(base64Encoded: String(source.dropFirst(kind.count))).map(ToolPanelImage.bytes)
            }
            return nil
        }
        guard ManifestRules.staysInsideFolder(source) else { return nil }
        let file = folder.appendingPathComponent(source)
        guard ToolWebPolicy.isInside(file, folder), FileManager.default.fileExists(atPath: file.path) else { return nil }
        return .file(file.resolvingSymlinksInPath().standardizedFileURL)
    }
}
