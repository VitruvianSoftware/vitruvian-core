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

import SwiftUI
import VitruvianCodeCore

/// Settings > Providers > "Add from ACP Registry": the registry's agents,
/// each with an Add (or Update) button. Adding installs that agent at the
/// version listed and saves a provider that runs it.
struct RegistryAgentPicker: View {
    @ObservedObject var list: ACPRegistryAgentList
    @ObservedObject var configManager: ConfigManager
    let onClose: () -> Void

    @State private var search = ""

    private var savedProviders: [VitruvianCodeCLIProvider] { configManager.providers.map(\.shared) }

    private var shown: [ACPRegistry.Agent] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return list.agents }
        return list.agents.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
                || $0.description.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ACP Registry").font(.headline)
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
            Text("Agents that speak ACP. Adding one installs it at the version listed, in this app's own folder; nothing is installed until you add it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)

            if list.isLoading && list.agents.isEmpty {
                HStack { ProgressView().controlSize(.small); Text("Loading the registry…").font(.caption) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = list.loadError, list.agents.isEmpty {
                VStack(spacing: 6) {
                    Text(error).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Try again") { Task { await list.load() } }.controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown) { agent in
                    row(agent)
                }
                .listStyle(.inset)
            }
        }
        .padding(16)
        .frame(width: 560, height: 520)
        .task { await list.load() }
    }

    @ViewBuilder
    private func row(_ agent: ACPRegistry.Agent) -> some View {
        let status = list.status(of: agent, providers: savedProviders)
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.name).font(.system(size: 12, weight: .semibold))
                    Text(agent.version).font(.caption2).foregroundStyle(.tertiary)
                    if let kind = ACPRegistry.resolveDistribution(agent)?.kind {
                        Text(kindLabel(kind))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.12)))
                    }
                }
                if !agent.description.isEmpty {
                    Text(agent.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if let error = list.errors[agent.id] {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
                }
            }
            Spacer()
            action(agent, status)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func action(_ agent: ACPRegistry.Agent, _ status: ACPRegistryAgentList.Status) -> some View {
        switch status {
        case .available:
            Button("Add") {
                Task {
                    if let provider = await list.add(agent) {
                        configManager.providers.append(CLIProvider(provider))
                    }
                }
            }
            .controlSize(.small)
        case .installing:
            ProgressView().controlSize(.small)
        case .added:
            Text("Added").font(.caption).foregroundStyle(.secondary)
        case .updateAvailable(_, let latest):
            Button("Update to \(latest)") {
                Task {
                    let saved = savedProviders
                    guard let current = saved.first(where: { $0.registryAgent?.agentID == agent.id }),
                          let moved = await list.update(current, to: agent, others: saved),
                          let index = configManager.providers.firstIndex(where: { $0.id == moved.id }) else { return }
                    configManager.providers[index] = CLIProvider(moved)
                }
            }
            .controlSize(.small)
        case .needsRunner(let runner):
            Text("Needs \(runner)").font(.caption).foregroundStyle(.orange)
                .help("Install \(runner) on this Mac to add \(agent.name).")
        case .noBuildForThisMac:
            Text("No Mac build").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func kindLabel(_ kind: ACPRegistry.DistributionKind) -> String {
        switch kind {
        case .binary: return "Binary"
        case .npx: return "npm"
        case .uvx: return "uv"
        }
    }
}
