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
/// agent uses its own MCP settings. Agents with quirks (Claude's adapter, in
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
            hooks: ACPConnection.Hooks(authenticateMethodID: spec.signInMethodID),
            stateFolderURL: URL(fileURLWithPath: environment.stateDirectory, isDirectory: true),
            stateDirectoryOverride: environment.stateDirectoryOverride,
            processFactory: processFactory
        )
    }
}
