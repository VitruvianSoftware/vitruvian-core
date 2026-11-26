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

/// A chat with an agent installed from the ACP registry: the shared ACP
/// client, run with the installed copy's own program, arguments and
/// environment.
///
/// As T3 Code's registry adapter (`packages/provider-acp-registry/src/server/adapter.ts`)
/// does for an agent with no quirks of its own, the client offers none of its
/// optional features (`ACPClientPolicy.none`) and passes no MCP servers: the
/// agent uses its own MCP settings. Plan switches to the agent's own plan mode
/// (`ACPConnection.ModeSync.agentPlanMode`). Agents with quirks (Claude's adapter, in
/// step 5f) get their own hooks.
///
/// A chat never installs. The engine checks for the installed copy first
/// (`locateProgram`); if it is gone the turn says so and nothing starts.
public enum ACPRegistryConnection {

    /// The launch for `spec`'s registry agent, or nil when its installed copy is gone.
    public static func launchSpec(spec: AgentConnectionSpec, stateDirectory: String, home: String) -> AgentProcessLaunchSpec? {
        guard let agent = spec.provider.registryAgent,
              let install = ACPRegistryInstaller.installedReceipt(stateDirectory: stateDirectory,
                                                                  agentID: agent.agentID, version: agent.version) else {
            return nil
        }
        let base = VitruvianCodeSupport.childEnvironment(base: spec.environment, home: home)
        return ACPRegistryInstaller.launchSpec(for: install, workingDirectory: spec.workingDirectory, baseEnvironment: base)
    }

    @MainActor
    public static func make(spec: AgentConnectionSpec, environment: VitruvianCodeEngine.Environment,
                            processFactory: @escaping ACPConnection.ProcessFactory = ACPLaunchedProcess.live) -> ACPConnection {
        let launch = launchSpec(spec: spec, stateDirectory: environment.stateDirectory, home: environment.home)
            // Gone since the engine looked: the start fails and the chat shows why.
            ?? AgentProcessLaunchSpec(executable: (environment.stateDirectory as NSString).appendingPathComponent("agents/\(spec.provider.registryAgent?.agentID ?? "missing")/not-installed"),
                                      environment: spec.environment, workingDirectory: spec.workingDirectory)
        let fallbackMode = spec.configuration.approvalMode
        let fallbackPlan = spec.turnModes.plan
        let modeProvider = spec.liveModeProvider ?? { (fallbackMode, fallbackPlan) }
        return ACPConnection(
            launchSpec: launch,
            policy: .none,
            modeProvider: modeProvider,
            hooks: ACPConnection.Hooks(authenticateMethodID: spec.signInMethodID, modeSync: .agentPlanMode),
            stateFolderURL: URL(fileURLWithPath: environment.stateDirectory, isDirectory: true),
            stateDirectoryOverride: environment.stateDirectoryOverride,
            processFactory: processFactory
        )
    }

    // MARK: Claude ACP

    /// The installed Claude ACP adapter: the version the Claude provider recorded when it was
    /// installed, else the newest installed. Never installs.
    public static func claudeAdapterInstall(stateDirectory: String,
                                            recorded: VitruvianCodeRegistryAgent?) -> ACPRegistryInstall? {
        let agentID = ClaudeACPAdapter.registryAgentID
        if let recorded, recorded.agentID == agentID,
           let install = ACPRegistryInstaller.installedReceipt(stateDirectory: stateDirectory, agentID: agentID,
                                                               version: recorded.version) {
            return install
        }
        let folder = ((stateDirectory as NSString).appendingPathComponent("agents") as NSString).appendingPathComponent(agentID)
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
            .compactMap { $0.removingPercentEncoding }
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        for version in versions {
            if let install = ACPRegistryInstaller.installedReceipt(stateDirectory: stateDirectory, agentID: agentID, version: version) {
                return install
            }
        }
        return nil
    }

    /// The launch for the Claude provider's "Claude ACP" connection, or nil when the adapter is
    /// not installed.
    public static func claudeLaunchSpec(spec: AgentConnectionSpec, stateDirectory: String, home: String) -> AgentProcessLaunchSpec? {
        guard let install = claudeAdapterInstall(stateDirectory: stateDirectory, recorded: spec.provider.registryAgent) else {
            return nil
        }
        let base = ClaudeACPAdapter.environment(
            base: VitruvianCodeSupport.childEnvironment(base: spec.environment, home: home),
            configDirectory: spec.provider.claudeConfigDirectory)
        return ACPRegistryInstaller.launchSpec(for: install, workingDirectory: spec.workingDirectory, baseEnvironment: base)
    }

    /// A chat on the Claude ACP adapter: the registry agent's connection with T3 Code's Claude
    /// options (`ClaudeACPAdapter`): subagents from Agent and Task calls, plan through Claude's
    /// own plan mode.
    @MainActor
    public static func makeClaude(spec: AgentConnectionSpec, environment: VitruvianCodeEngine.Environment,
                                  processFactory: @escaping ACPConnection.ProcessFactory = ACPLaunchedProcess.live) -> ACPConnection {
        let launch = claudeLaunchSpec(spec: spec, stateDirectory: environment.stateDirectory, home: environment.home)
            ?? AgentProcessLaunchSpec(executable: (environment.stateDirectory as NSString)
                                        .appendingPathComponent("agents/\(ClaudeACPAdapter.registryAgentID)/not-installed"),
                                      environment: spec.environment, workingDirectory: spec.workingDirectory)
        let fallbackMode = spec.configuration.approvalMode
        let fallbackPlan = spec.turnModes.plan
        let modeProvider = spec.liveModeProvider ?? { (fallbackMode, fallbackPlan) }
        let tracker = ClaudeSubagentTracker()
        let transform: @MainActor @Sendable (ACPSessionNotification) -> (notification: ACPSessionNotification?, extraEvents: [AgentEvent]) = { notification in
            (notification: notification, extraEvents: tracker.event(for: notification).map { [$0] } ?? [])
        }
        return ACPConnection(
            launchSpec: launch,
            policy: .none,
            modeProvider: modeProvider,
            hooks: ACPConnection.Hooks(transformSessionUpdate: transform,
                                       authenticateMethodID: spec.signInMethodID,
                                       modeSync: .agentPlanMode),
            stateFolderURL: URL(fileURLWithPath: environment.stateDirectory, isDirectory: true),
            stateDirectoryOverride: environment.stateDirectoryOverride,
            processFactory: processFactory
        )
    }
}
