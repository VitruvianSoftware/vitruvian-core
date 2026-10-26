// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct GIFCandidate: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var mediaURL: String
    public var mimeType: String
    public var width: Int?
    public var height: Int?

    public init(
        id: String,
        title: String,
        mediaURL: String,
        mimeType: String,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.mediaURL = mediaURL
        self.mimeType = mimeType
        self.width = width
        self.height = height
    }
}

public protocol GIFProvider: Sendable {
    var isAvailable: Bool { get }
    func trending() async throws -> [GIFCandidate]
    func search(_ query: String) async throws -> [GIFCandidate]
}

public struct StubGIFProvider: GIFProvider {
    public init() {}
    public var isAvailable: Bool { false }
    public func trending() async throws -> [GIFCandidate] { [] }
    public func search(_ query: String) async throws -> [GIFCandidate] { [] }
}
