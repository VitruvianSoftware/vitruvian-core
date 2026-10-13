// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Darwin
import Foundation

/// A tool's download, a zip: read before it is unpacked, unpacked by
/// `/usr/bin/ditto`, and looked over after. Nothing here is on the main
/// thread.
///
/// Before: the zip's central directory is read, and the zip is refused when
/// any entry's name would leave the folder (an absolute path, a part that is
/// `..` or `.`, a backslash), when any entry is a link or encrypted, when it
/// is Zip64, or when it would hold more than a tool's folder may
/// (`ToolLimits.folderBytes` and `folderItems`). After: every file is inside
/// the folder, is no link, and is one the directory named.
package enum CatalogueArchive {
    package enum Problem: Error, Equatable, Sendable {
        /// Not a zip the app reads.
        case notAZip
        /// An entry's name would leave the folder.
        case leavesTheFolder(String)
        /// An entry is a link.
        case link(String)
        /// An entry is encrypted.
        case encrypted(String)
        /// More than a tool's folder may hold.
        case tooBig
    }

    /// What the central directory says the zip holds.
    package struct Listing: Equatable, Sendable {
        /// Each entry's name, as the zip spells it. A folder ends with a slash.
        package let names: [String]
        /// The bytes the entries unpack to, as the zip declares them.
        package let bytes: Int

        package init(names: [String], bytes: Int) {
            self.names = names
            self.bytes = bytes
        }
    }

    /// Reads the central directory of the zip at `url` without unpacking it.
    package static func vet(_ url: URL, limits: ToolLimits) -> Result<Listing, Problem> {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .failure(.notAZip) }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size >= 22 else { return .failure(.notAZip) }
        // The end record is in the last 22 bytes, or up to 65,535 bytes
        // before them when the zip has a comment.
        let tail = min(size, 22 + 65_535)
        guard (try? handle.seek(toOffset: size - tail)) != nil, let end = try? handle.read(upToCount: Int(tail)) else {
            return .failure(.notAZip)
        }
        let bytes = [UInt8](end)
        guard let at = stride(from: bytes.count - 22, through: 0, by: -1).first(where: {
            bytes[$0] == 0x50 && bytes[$0 + 1] == 0x4B && bytes[$0 + 2] == 0x05 && bytes[$0 + 3] == 0x06
        }) else { return .failure(.notAZip) }
        let count = Int(word(bytes, at + 10))
        let directorySize = Int(long(bytes, at + 12))
        let directoryStart = UInt64(long(bytes, at + 16))
        // Zip64 marks its fields with all ones. A tool's zip never needs it.
        guard count != 0xFFFF, directorySize != 0xFFFF_FFFF, directoryStart != 0xFFFF_FFFF else {
            return .failure(.notAZip)
        }
        guard count <= limits.folderItems else { return .failure(.tooBig) }
        guard directoryStart + UInt64(directorySize) <= size, (try? handle.seek(toOffset: directoryStart)) != nil,
              let directory = try? handle.read(upToCount: directorySize), directory.count == directorySize else {
            return .failure(.notAZip)
        }
        let entries = [UInt8](directory)
        var names: [String] = []
        var total = 0
        var offset = 0
        for _ in 0..<count {
            guard offset + 46 <= entries.count, long(entries, offset) == 0x0201_4B50 else { return .failure(.notAZip) }
            let madeBy = entries[offset + 5]
            let flags = word(entries, offset + 8)
            let unpacked = Int(long(entries, offset + 24))
            let nameLength = Int(word(entries, offset + 28))
            let extraLength = Int(word(entries, offset + 30))
            let commentLength = Int(word(entries, offset + 32))
            let mode = long(entries, offset + 38) >> 16
            let next = offset + 46 + nameLength + extraLength + commentLength
            guard next <= entries.count,
                  let name = String(bytes: entries[(offset + 46)..<(offset + 46 + nameLength)], encoding: .utf8) else {
                return .failure(.notAZip)
            }
            guard isInside(name) else { return .failure(.leavesTheFolder(name)) }
            // Made on a Unix system (3): the high bytes are its mode.
            if madeBy == 3, mode & 0o170000 == 0o120000 { return .failure(.link(name)) }
            if flags & 0x1 != 0 { return .failure(.encrypted(name)) }
            total += unpacked
            guard unpacked != 0xFFFF_FFFF, total <= limits.folderBytes else { return .failure(.tooBig) }
            names.append(name)
            offset = next
        }
        return .success(Listing(names: names, bytes: total))
    }

    /// True for a name that stays inside the folder it is unpacked in.
    package static func isInside(_ name: String) -> Bool {
        guard !name.isEmpty, !name.contains("\0"), !name.contains("\\"), !name.hasPrefix("/"),
              !name.hasPrefix("~") else { return false }
        let parts = (name.hasSuffix("/") ? String(name.dropLast()) : name).split(separator: "/",
                                                                                 omittingEmptySubsequences: false)
        return !parts.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    /// Unpacks the zip at `zip` into `folder`, which must not exist yet,
    /// with `/usr/bin/ditto`: no resource forks, no extended attributes, no
    /// quarantine and no access lists. True when it ended well within
    /// `seconds`; it is ended, then killed, when it does not.
    package static func unpack(_ zip: URL, into folder: URL, seconds: TimeInterval = 120) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", "--norsrc", "--noextattr", "--noqtn", "--noacl", zip.path, folder.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        guard (try? process.run()) != nil else { return false }
        if finished.wait(timeout: .now() + seconds) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                finished.wait()
            }
            return false
        }
        return process.terminationReason == .exit && process.terminationStatus == 0
    }

    /// After unpacking: every file is inside `folder`, nothing is a link, the
    /// folder holds no more than a tool's may, and each file is one `listing`
    /// named.
    package static func looksRight(_ folder: URL, listing: Listing, limits: ToolLimits) -> Bool {
        let root = folder.standardizedFileURL.path + "/"
        let named = Set(listing.names)
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [],
                                                        errorHandler: { _, _ in false }) else { return false }
        var items = 0
        var bytes = 0
        for case let url as URL in walk {
            items += 1
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else {
                return false
            }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(root) else { return false }
            if values.isRegularFile == true {
                bytes += values.fileSize ?? 0
                guard named.contains(String(path.dropFirst(root.count))) else { return false }
            }
            guard items <= limits.folderItems, bytes <= limits.folderBytes else { return false }
        }
        return true
    }

    private static func word(_ bytes: [UInt8], _ at: Int) -> UInt16 {
        UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
    }

    private static func long(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(word(bytes, at)) | UInt32(word(bytes, at + 2)) << 16
    }
}
