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
//
// Shared by the standalone Vitruvian Code app and the Code feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian-atrium/UPSTREAM.md).

import Darwin
import Foundation

/// Serves `fs/read_text_file` and `fs/write_text_file` inside allowed workspace folders,
/// using T3 Code's symlink-aware fail-closed path canonicalization (`clientPolicy.ts:41-69`,
/// `AntigravityClientFiles.ts:8-110`).
public struct ACPClientFiles: Sendable {
    /// Matches T3 Code's `CLIENT_FILE_MAX_BYTES = 8 * 1024 * 1024` (`AntigravityClientFiles.ts:8`).
    public static let maxFileBytes = 8 * 1024 * 1024

    public var workingDirectory: String
    public var additionalDirectories: [String]

    public init(workingDirectory: String, additionalDirectories: [String] = []) {
        self.workingDirectory = workingDirectory
        self.additionalDirectories = additionalDirectories
    }

    /// Canonicalizes existing ancestors with `realpath` while allowing non-existent leaf segments,
    /// failing closed on dangling symlinks, permission errors or unresolvable paths.
    /// Ported from `acpCanonicalPathForContainment` (`clientPolicy.ts:41-69`).
    public static func canonicalPathForContainment(_ rawPath: String) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }

        var candidate = trimmed
        while candidate.count > 1 && candidate.hasSuffix("/") {
            candidate.removeLast()
        }
        var missingSuffix: [String] = []

        while true {
            if let resolvedPtr = Darwin.realpath(candidate, nil) {
                defer { free(resolvedPtr) }
                let realBase = String(cString: resolvedPtr)
                return resolveLexicalSegments(base: realBase, suffix: missingSuffix)
            }

            if errno != ENOENT {
                return nil
            }

            // If `lstat` succeeds while `realpath` returned ENOENT, `candidate` is a dangling
            // symlink on disk: fail closed rather than walking past it (`clientPolicy.ts:55-62`).
            var statBuf = stat()
            if Darwin.lstat(candidate, &statBuf) == 0 {
                return nil
            }
            if errno != ENOENT {
                return nil
            }

            guard let slashIndex = candidate.lastIndex(of: "/") else {
                return nil
            }
            let base = String(candidate[candidate.index(after: slashIndex)...])
            let parent = slashIndex == candidate.startIndex ? "/" : String(candidate[..<slashIndex])
            if parent == candidate || base.isEmpty {
                return nil
            }
            missingSuffix.insert(base, at: 0)
            candidate = parent
        }
    }

    /// Mirrors `NodePath.resolve(realBase, ...missingSuffix)` once `realpath` has resolved all
    /// existing path prefixes (`clientPolicy.ts:48`).
    private static func resolveLexicalSegments(base: String, suffix: [String]) -> String {
        var segments = base.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        for rawPart in suffix {
            for part in rawPart.split(separator: "/", omittingEmptySubsequences: true) {
                if part == "." {
                    continue
                }
                if part == ".." {
                    if !segments.isEmpty {
                        segments.removeLast()
                    }
                } else {
                    segments.append(String(part))
                }
            }
        }
        return "/" + segments.joined(separator: "/")
    }

    /// True when `canonicalPath` equals `canonicalRoot` or sits strictly beneath it (`clientPolicy.ts:30-38`).
    public static func pathIsWithinRoot(_ canonicalPath: String, root canonicalRoot: String) -> Bool {
        if canonicalPath == canonicalRoot {
            return true
        }
        let prefix = canonicalRoot == "/" ? "/" : canonicalRoot + "/"
        return canonicalPath.hasPrefix(prefix)
    }

    /// Resolves `requestedPath` (absolute or relative to `workingDirectory`) and verifies it stays
    /// inside `workingDirectory` or `additionalDirectories`. Fails closed on any resolution failure.
    public func resolveContainedPath(_ requestedPath: String) throws -> String {
        let trimmed = requestedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ACPRPCError(code: ACPRPCError.invalidParams, message: "File path must not be empty.")
        }

        let absoluteCandidate: String
        if trimmed.hasPrefix("/") {
            absoluteCandidate = trimmed
        } else {
            let trimmedWorkdir = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedWorkdir.hasPrefix("/") else {
                throw ACPRPCError(
                    code: ACPRPCError.invalidParams,
                    message: "Relative file path requires an absolute session working directory."
                )
            }
            absoluteCandidate = trimmedWorkdir.hasSuffix("/")
                ? trimmedWorkdir + trimmed
                : trimmedWorkdir + "/" + trimmed
        }

        guard let canonicalCandidate = Self.canonicalPathForContainment(absoluteCandidate) else {
            throw ACPRPCError(
                code: ACPRPCError.invalidParams,
                message: "File path could not be resolved safely: \(requestedPath)"
            )
        }

        let allRoots = [workingDirectory] + additionalDirectories
        let canonicalRoots = allRoots.compactMap { root -> String? in
            let clean = root.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return nil }
            return Self.canonicalPathForContainment(clean)
        }
        guard !canonicalRoots.isEmpty else {
            throw ACPRPCError(
                code: ACPRPCError.invalidParams,
                message: "Session has no resolvable allowed root folders."
            )
        }

        guard canonicalRoots.contains(where: { Self.pathIsWithinRoot(canonicalCandidate, root: $0) }) else {
            throw ACPRPCError(
                code: ACPRPCError.invalidParams,
                message: "File path is outside the session's allowed folders: \(requestedPath)"
            )
        }

        return canonicalCandidate
    }

    /// Handles `fs/read_text_file`, enforcing policy, containment, regular-file check, size cap,
    /// and 1-indexed `line` + `limit` slicing (`AntigravityClientFiles.ts:59-110`).
    public func readTextFile(
        _ params: ACPReadTextFileParams,
        policy: ACPClientPolicy
    ) throws -> ACPReadTextFileResult {
        guard policy.readTextFile else {
            throw ACPRPCError(
                code: ACPRPCError.methodNotFound,
                message: "Method not found: fs/read_text_file"
            )
        }
        if let line = params.line, line < 1 {
            throw ACPRPCError(
                code: ACPRPCError.invalidParams,
                message: "Invalid line parameter \(line); line numbers are 1-indexed."
            )
        }
        if let limit = params.limit, limit < 0 {
            throw ACPRPCError(
                code: ACPRPCError.invalidParams,
                message: "Invalid negative limit parameter \(limit)."
            )
        }

        let resolvedPath = try resolveContainedPath(params.path)
        let fd = Darwin.open(resolvedPath, O_RDONLY)
        guard fd >= 0 else {
            throw ACPRPCError(
                code: ACPRPCError.invalidParams,
                message: "Unable to read file at \(params.path): \(String(cString: strerror(errno)))"
            )
        }
        defer { _ = Darwin.close(fd) }

        var statBuf = stat()
        guard Darwin.fstat(fd, &statBuf) == 0 else {
            throw ACPRPCError(
                code: ACPRPCError.invalidParams,
                message: "Unable to read file at \(params.path): \(String(cString: strerror(errno)))"
            )
        }
        guard (statBuf.st_mode & S_IFMT) == S_IFREG else {
            throw ACPRPCError(
                code: ACPRPCError.invalidParams,
                message: "Not a regular file: \(params.path)"
            )
        }
        guard statBuf.st_size <= Self.maxFileBytes else {
            throw ACPRPCError(
                code: ACPRPCError.invalidParams,
                message: "File exceeds \(Self.maxFileBytes) byte limit: \(params.path)"
            )
        }

        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        let data: Data
        do {
            data = try handle.readToEnd() ?? Data()
        } catch {
            throw ACPRPCError(
                code: ACPRPCError.invalidParams,
                message: "Unable to read file at \(params.path): \(error.localizedDescription)"
            )
        }
        guard data.count <= Self.maxFileBytes else {
            throw ACPRPCError(
                code: ACPRPCError.invalidParams,
                message: "File exceeds \(Self.maxFileBytes) byte limit: \(params.path)"
            )
        }

        let content = try Self.decodeValidatedUTF8Text(data, displayPath: params.path)
        if params.line == nil && params.limit == nil {
            return ACPReadTextFileResult(content: content)
        }

        // Split on `\r\n` or `\n` preserving empty lines (`AntigravityClientFiles.ts:104-109`).
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let start = min(lines.count, max(0, (params.line ?? 1) - 1))
        let end: Int
        if let limit = params.limit {
            end = min(lines.count, start + limit)
        } else {
            end = lines.count
        }
        let sliced = start < end ? lines[start..<end].joined(separator: "\n") : ""
        return ACPReadTextFileResult(content: sliced)
    }

    /// Rejects invalid UTF-8 sequences and NUL-containing binary files (`AntigravityClientFiles.ts:88-99`).
    private static func decodeValidatedUTF8Text(_ data: Data, displayPath: String) throws -> String {
        var decoder = Unicode.UTF8()
        var iterator = data.makeIterator()
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(data.count)
        while true {
            switch decoder.decode(&iterator) {
            case .scalarValue(let scalar):
                scalars.append(scalar)
            case .emptyInput:
                let text = String(scalars)
                if text.utf8.contains(0) {
                    throw ACPRPCError(
                        code: ACPRPCError.invalidParams,
                        message: "File '\(displayPath)' contains binary data."
                    )
                }
                return text
            case .error:
                throw ACPRPCError(
                    code: ACPRPCError.invalidParams,
                    message: "File '\(displayPath)' is not a UTF-8 text file."
                )
            }
        }
    }

    /// Handles `fs/write_text_file`, enforcing policy and symlink-aware workspace containment.
    public func writeTextFile(
        _ params: ACPWriteTextFileParams,
        policy: ACPClientPolicy
    ) throws -> ACPEmptyObject {
        guard policy.writeTextFile else {
            throw ACPRPCError(
                code: ACPRPCError.methodNotFound,
                message: "Method not found: fs/write_text_file"
            )
        }

        let resolvedPath = try resolveContainedPath(params.path)
        let parentDir = (resolvedPath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(
                atPath: parentDir,
                withIntermediateDirectories: true
            )
            // Re-verify containment after directory creation to guard against races.
            let verifiedPath = try resolveContainedPath(resolvedPath)
            try Data(params.content.utf8).write(to: URL(fileURLWithPath: verifiedPath), options: .atomic)
            return ACPEmptyObject()
        } catch let rpcError as ACPRPCError {
            throw rpcError
        } catch {
            throw ACPRPCError(
                code: ACPRPCError.internalError,
                message: "Failed to write file \(params.path): \(error.localizedDescription)"
            )
        }
    }
}
