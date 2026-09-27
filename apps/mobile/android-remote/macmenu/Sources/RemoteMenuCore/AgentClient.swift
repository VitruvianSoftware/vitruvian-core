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

/// Reads the agent's two read-tier endpoints. Read-only on purpose: it never
/// touches the bearer token, so this app holds no credential of its own.
public struct AgentClient: Sendable {
    public var baseURL: URL
    public var paths: AgentPaths

    public init(baseURL: URL = AgentPaths.baseURL, paths: AgentPaths = AgentPaths()) {
        self.baseURL = baseURL
        self.paths = paths
    }

    public func snapshot() async -> StatusSnapshot {
        let installed = FileManager.default.isExecutableFile(atPath: paths.binary.path)
        let (status, health): (Int?, AgentHealth?) = await fetch("/healthz")
        let state = StatusSnapshot.classify(installed: installed, status: status, health: health)
        var phone: PhoneLink?
        if status != nil {
            let (_, p): (Int?, PhoneLink?) = await fetch("/v1/phone")
            phone = p
        }
        return StatusSnapshot(state: state, health: health, phone: phone)
    }

    private func fetch<T: Decodable>(_ path: String) async -> (Int?, T?) {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.timeoutInterval = 2
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode
            return (code, try? JSONDecoder().decode(T.self, from: data))
        } catch {
            return (nil, nil)
        }
    }
}
