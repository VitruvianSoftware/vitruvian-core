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

/// What Settings shows and does for ACP registry agents: the registry's
/// list, each agent's state on this Mac, and add, update and remove. The
/// view only draws this; the rules live here, where they are tested.
///
/// Adding is the only thing that installs. Opening the list reads the
/// registry and the install folders and nothing more.
@MainActor
public final class ACPRegistryAgentList: ObservableObject {

    /// One agent's row.
    public enum Status: Equatable, Sendable {
        /// Can be added.
        case available
        /// The registry has no install for this Mac.
        case noBuildForThisMac
        /// It needs `npm` or `uv`, which this Mac lacks.
        case needsRunner(String)
        /// Being installed now.
        case installing
        /// A provider runs it, at this version.
        case added(version: String)
        /// A provider runs an older version than the registry lists.
        case updateAvailable(installed: String, latest: String)
    }

    @Published public private(set) var agents: [ACPRegistry.Agent] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var loadError: String?
    /// The last add or update that failed, by agent id.
    @Published public private(set) var errors: [String: String] = [:]
    @Published private var installing: Set<String> = []

    private let installer: ACPRegistryInstaller

    public init(installer: ACPRegistryInstaller) {
        self.installer = installer
    }

    /// Reads the registry's list (or its saved copy when offline). Installs nothing.
    public func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let index = try await installer.loadIndex()
            agents = index.agents.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            loadError = (error as? ACPRegistryError)?.detail ?? error.localizedDescription
        }
    }

    /// `agent`'s row, given the providers saved now.
    public func status(of agent: ACPRegistry.Agent, providers: [VitruvianCodeCLIProvider]) -> Status {
        if installing.contains(agent.id) { return .installing }
        if let added = providers.compactMap(\.registryAgent).first(where: { $0.agentID == agent.id }) {
            return added.version == agent.version ? .added(version: added.version)
                : .updateAvailable(installed: added.version, latest: agent.version)
        }
        guard ACPRegistry.resolveDistribution(agent) != nil else { return .noBuildForThisMac }
        if let runner = installer.missingRunner(for: agent) { return .needsRunner(runner) }
        return .available
    }

    /// Installs `agent` and gives back the provider that runs it, for
    /// Settings to save; nil when the install failed (see `errors`).
    public func add(_ agent: ACPRegistry.Agent) async -> VitruvianCodeCLIProvider? {
        guard await install(agent) else { return nil }
        return VitruvianCodeCLIProvider(
            id: UUID(), name: agent.name, commandTemplate: "", isBuiltIn: false, connection: .acp,
            registryAgent: VitruvianCodeRegistryAgent(agentID: agent.id, version: agent.version))
    }

    /// Installs the registry's version of `provider`'s agent and gives back
    /// the provider moved to it; the old version is removed once no other
    /// provider runs it. Nil when the install failed.
    public func update(_ provider: VitruvianCodeCLIProvider, to agent: ACPRegistry.Agent,
                       others: [VitruvianCodeCLIProvider]) async -> VitruvianCodeCLIProvider? {
        guard let old = provider.registryAgent, old.agentID == agent.id, await install(agent) else { return nil }
        var moved = provider
        moved.registryAgent = VitruvianCodeRegistryAgent(agentID: agent.id, version: agent.version)
        if !others.contains(where: { $0.id != provider.id && $0.registryAgent == old }) {
            try? await installer.uninstall(agentID: old.agentID, version: old.version)
        }
        return moved
    }

    /// Removes `provider`'s installed copy once no provider left runs it.
    /// Call after taking the provider out of the saved list.
    public func removed(_ provider: VitruvianCodeCLIProvider, remaining: [VitruvianCodeCLIProvider]) async {
        guard let agent = provider.registryAgent,
              !remaining.contains(where: { $0.registryAgent == agent }) else { return }
        try? await installer.uninstall(agentID: agent.agentID, version: agent.version)
    }

    private func install(_ agent: ACPRegistry.Agent) async -> Bool {
        installing.insert(agent.id)
        errors[agent.id] = nil
        defer { installing.remove(agent.id) }
        do {
            _ = try await installer.install(agent)
            return true
        } catch {
            errors[agent.id] = (error as? ACPRegistryError)?.detail ?? error.localizedDescription
            return false
        }
    }
}
