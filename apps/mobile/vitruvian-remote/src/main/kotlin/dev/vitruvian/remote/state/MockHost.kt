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

package dev.vitruvian.remote.state

import dev.vitruvian.design.StatusTone
import dev.vitruvian.design.TagTone
import dev.vitruvian.design.TerminalLine
import dev.vitruvian.design.TerminalTone

/**
 * The stand-in for the Mac agent.
 *
 * Everything the app shows comes from here until the Go agent described in the handoff exists on
 * the host side; the shapes are the ones that agent will fill, so swapping it in is a repository
 * change and not a UI one.
 */
public object MockHost {
  public val hosts: List<Host> =
      listOf(
          Host(
              id = "mock-atlas",
              name = "atlas · MacBook Pro M4 Max",
              subtitle = "100.64.0.12 · macOS 26.1 · 64 GB",
              tone = StatusTone.Ok,
              tag = "connected",
              tagTone = TagTone.Ok,
          ),
          Host(
              id = "mock-forge",
              name = "forge · Mac mini M2",
              subtitle = "100.64.0.31 · macOS 26.0 · 16 GB",
              tone = StatusTone.Neutral,
              tag = "asleep",
              tagTone = TagTone.Neutral,
          ),
      )

  public val builtInMacros: List<Macro> =
      listOf(
          Macro("lock", "Lock screen", "pmset displaysleepnow", MacroKind.Ssh),
          Macro("brew", "Brew upgrade", "brew upgrade", MacroKind.Ssh),
          // A shell command, not AppleScript: as AppleScript it ran
          // `osascript -e "screencapture -c"`, which is a syntax error.
          Macro("shot", "Screenshot → clip", "screencapture -c", MacroKind.Ssh),
          // The AppleScript itself. The kind already means "run through
          // osascript"; wrapping it in a second osascript was a syntax error.
          Macro("mute", "Mute", "set volume output muted true", MacroKind.AppleScript),
      )

  public val runningNow: List<RunningItem> =
      listOf(
          RunningItem(
              "claude",
              "Claude Code",
              "2 sessions · web-app · 14.2k tokens",
              StatusTone.Run,
              "running",
              TagTone.Accent,
          ),
          RunningItem(
              "homelab",
              "Homelab · K3s",
              "3/3 nodes ready · v1.32.4",
              StatusTone.Ok,
              "ready",
              TagTone.Ok,
          ),
          RunningItem(
              "lima", "Lima VMs", "2 running · 1 stopped", StatusTone.Warn, "1 down", TagTone.Warn),
          RunningItem(
              "antigravity",
              "Antigravity",
              "build #412 · 3m ago",
              StatusTone.Ok,
              "green",
              TagTone.Ok),
      )

  public val gallery: List<GalleryEntry> =
      listOf(
          GalleryEntry(
              "claude",
              "Claude Code",
              "Sessions, transcript, prompt relay",
              "claude",
              "claude",
              autoShow = true),
          // What agy can actually report. It is an interactive coding agent
          // with no build, eval or queue query; the old subtitle promised
          // three things that do not exist.
          GalleryEntry(
              "antigravity",
              "Antigravity",
              "Version, models, agents",
              "agy",
              "agy",
              autoShow = true),
          // The Mac's own `gh`, not a GitHub token on the phone: the agent
          // already has one authenticated CLI and shipping a second set of
          // credentials to a handset to do the same job would be worse.
          GalleryEntry(
              "prs", "Pull requests", "Open PRs, checks, merge", "gh", "gh", autoShow = true),
          GalleryEntry(
              "homelab",
              "Homelab · K3s",
              "Nodes, workloads, ArgoCD sync",
              "kubectl",
              "kubectl",
              autoShow = false),
          GalleryEntry(
              "lima",
              "Lima VMs",
              "Instances, start / stop, resources",
              "limactl",
              "limactl",
              autoShow = false),
          GalleryEntry(
              "docker", "Docker", "Containers, images, logs", "docker", "docker", autoShow = false),
          GalleryEntry(
              "grafana",
              "Grafana panel",
              "The Mac screen's PromQL, as a table",
              "promql",
              autoShow = false),
          GalleryEntry(
              "ollama",
              "Ollama",
              "Models on disk and in memory",
              "ollama",
              "ollama",
              autoShow = true),
          // Read and driven through the agent, which shares the app's config
          // file: on / off, which speaker, how much of a reply, say this.
          GalleryEntry(
              "speaker",
              "Vitruvian Speaker",
              "On / off, speaker, announce",
              "config",
              "speaker",
              autoShow = true),
          GalleryEntry(
              "tv",
              "Sony TV",
              "Power, 4K Aerials, apps, HDMI, cast URL",
              "adb",
              "adb",
              autoShow = false),
      )

  public fun discoveryRules(): List<Derive.ModuleDiscoveryRule> =
      gallery.map { Derive.ModuleDiscoveryRule(it.id, it.requires, it.autoShow) }

  public val defaultInstalled: Set<String> = setOf("claude")

  /** Pre-installed modules when the user explicitly enters demo mode from the first-run screen. */
  public val demoInstalled: Set<String> =
      setOf("claude", "antigravity", "homelab", "lima", "prs", "speaker", "tv")

  public val processes: List<Process> =
      listOf(
          Process("claude", 38, "1.9 GB"),
          Process("com.apple.Virtualization", 22, "8.4 GB"),
          Process("ollama", 14, "5.1 GB"),
          Process("node", 9, "1.1 GB"),
          Process("WindowServer", 4, "612 MB"),
      )

  public val vms: List<Vm> =
      listOf(
          Vm(
              "default · ubuntu",
              "arm64 · 4 cpu · 8 GiB · running",
              StatusTone.Ok,
              "ready",
              TagTone.Ok),
          Vm(
              "alpine-vm · alpine",
              "arm64 · 2 cpu · 4 GiB · running",
              StatusTone.Ok,
              "ready",
              TagTone.Ok),
          Vm(
              "sandbox · debian",
              "amd64 · 2 cpu · 4 GiB · stopped",
              StatusTone.Warn,
              "stopped",
              TagTone.Warn),
      )

  public val containers: List<Container> =
      listOf(
          Container("grafana", "grafana/grafana:11.3 · :3000", "1.2%"),
          Container("prometheus", "prom/prometheus:v3.0 · :9090", "3.8%"),
          Container("loki", "grafana/loki:3.2 · :3100", "0.9%"),
      )

  public val initialTerminal: List<TerminalLine> =
      listOf(
          TerminalLine("$", "git status", TerminalTone.Text),
          TerminalLine(
              " ", "On branch main · nothing to commit, working tree clean", TerminalTone.Ok),
          TerminalLine("$", "npm test", TerminalTone.Text),
          TerminalLine(" ", "ok  42 suites · 186 tests passed (2.4s)", TerminalTone.Ok),
          TerminalLine("$", "brew upgrade", TerminalTone.Text),
          TerminalLine(" ", "ok  all formulae up to date", TerminalTone.Dim),
      )

  public val initialAgentTranscript: List<TerminalLine> =
      listOf(
          TerminalLine(
              "›", "refactor auth middleware to propagate ctx; add tests", TerminalTone.Text),
          TerminalLine(
              " ",
              "read  middleware/auth.go · handlers/login.go · pkg/jwt/claims.go",
              TerminalTone.Dim,
          ),
          TerminalLine(" ", "edit  middleware/auth.go (+41 −12)", TerminalTone.Dim),
          TerminalLine(" ", "run   go test ./... — ok (1.8s)", TerminalTone.Ok),
          TerminalLine(" ", "! 1 uncommitted file — run git status?", TerminalTone.Warn),
      )

  public val recentCommands: List<String> =
      listOf(
          "git status",
          "npm test",
          "brew upgrade",
          "docker ps",
          "git log --oneline -5",
      )

  /** Canned output for the console's fake shell. */
  public fun output(command: String): String =
      when {
        command.startsWith("docker") -> "grafana  prometheus  loki — Up"
        command == "git status" -> "On branch main · nothing to commit, working tree clean"
        command.startsWith("git") ->
            "e7c2d11 feat(auth): propagate ctx\n2b9a410 test(auth): cover token expiry"
        command.startsWith("npm") -> "ok  42 suites · 186 tests passed (2.4s)"
        command.startsWith("brew") -> "ok  all formulae up to date"
        else -> "ok"
      }

  /** The module dashboards, keyed by the gallery id that installs them. */
  public fun dashboards(
      agentTranscript: List<TerminalLine>,
      agentRunning: Boolean
  ): Map<String, ModuleDashboard> =
      mapOf(
          "claude" to
              ModuleDashboard(
                  id = "claude",
                  name = "Claude Code",
                  meta = "local session · ~/projects/web-app",
                  status = "running",
                  statusTone = StatusTone.Run,
                  metrics =
                      listOf(
                          ModuleMetric("Sessions", "2", "main · feat/auth"),
                          ModuleMetric("Tokens today", "14.2k", "−22% vs limit"),
                          ModuleMetric("Tool calls", "48", "12 files · 4 commands"),
                      ),
                  streamLabel = "Transcript · session 2",
                  lines = agentTranscript,
                  cursor = agentRunning,
                  prompts = true,
                  listLabel = "Sessions",
                  rows =
                      listOf(
                          ModuleRow(
                              "auth middleware refactor",
                              "feat/auth · 18m",
                              "live",
                              StatusTone.Run),
                          ModuleRow("test suite cleanup", "main · idle 2h", "2h", StatusTone.Ok),
                      ),
              ),
          "antigravity" to
              ModuleDashboard(
                  id = "antigravity",
                  name = "Antigravity",
                  meta = "agent runtime · builds & evals",
                  status = "green",
                  statusTone = StatusTone.Ok,
                  metrics =
                      listOf(
                          ModuleMetric("Last build", "#412", "3m ago · 38s"),
                          ModuleMetric("Evals passing", "96%", "48 / 50"),
                          ModuleMetric("Queue", "0", "idle"),
                      ),
                  streamLabel = "Build log",
                  lines =
                      listOf(
                          TerminalLine("$", "antigravity build --target eval", TerminalTone.Text),
                          TerminalLine(" ", "ok  compiled 212 modules (12s)", TerminalTone.Ok),
                          TerminalLine(" ", "ok  evals 48/50 · 2 skipped", TerminalTone.Ok),
                      ),
                  cursor = false,
                  prompts = false,
                  listLabel = "Recent builds",
                  rows =
                      listOf(
                          ModuleRow("#412 · main", "eval · 38s", "ok", StatusTone.Ok),
                          ModuleRow("#411 · main", "eval · 41s", "ok", StatusTone.Ok),
                          ModuleRow("#410 · feat/auth", "eval · failed 2", "err", StatusTone.Crit),
                      ),
              ),
          "homelab" to
              ModuleDashboard(
                  id = "homelab",
                  name = "Homelab · K3s",
                  meta = "kubectl · k3s v1.32.4 · 3 nodes",
                  status = "ready",
                  statusTone = StatusTone.Ok,
                  metrics =
                      listOf(
                          ModuleMetric("Nodes", "3/3", "embedded etcd"),
                          ModuleMetric("Workloads", "41", "+3 today"),
                          ModuleMetric("ArgoCD", "synced", "19 apps"),
                      ),
                  streamLabel = "kubectl get nodes",
                  lines =
                      listOf(
                          TerminalLine("$", "kubectl get nodes", TerminalTone.Text),
                          TerminalLine(
                              " ", "node-1 Ready · node-2 Ready · node-3 Ready", TerminalTone.Ok),
                          TerminalLine(
                              " ", "control-plane healthy · k3s v1.32.4", TerminalTone.Dim),
                      ),
                  cursor = false,
                  prompts = false,
                  listLabel = "Nodes",
                  rows =
                      listOf(
                          ModuleRow("node-1", "server · 2 cpu · 4 GiB", "ready", StatusTone.Ok),
                          ModuleRow("node-2", "server · 2 cpu · 4 GiB", "ready", StatusTone.Ok),
                          ModuleRow("node-3", "server · 4 cpu · 8 GiB", "ready", StatusTone.Ok),
                      ),
              ),
          "lima" to
              ModuleDashboard(
                  id = "lima",
                  name = "Lima VMs",
                  meta = "limactl · VZ · socket_vmnet",
                  status = "1 stopped",
                  statusTone = StatusTone.Warn,
                  metrics =
                      listOf(
                          ModuleMetric("Running", "2", "of 3"),
                          ModuleMetric("vCPU", "8", "allocated"),
                          ModuleMetric("Memory", "16 GiB", "allocated"),
                      ),
                  streamLabel = "limactl list",
                  lines =
                      listOf(
                          TerminalLine("$", "limactl list", TerminalTone.Text),
                          TerminalLine(" ", "default Running · alpine-vm Running", TerminalTone.Ok),
                          TerminalLine(" ", "sandbox Stopped", TerminalTone.Warn),
                      ),
                  cursor = false,
                  prompts = false,
                  listLabel = "Instances",
                  rows =
                      listOf(
                          ModuleRow("default", "arm64 · 4 cpu · 8 GiB", "running", StatusTone.Ok),
                          ModuleRow("alpine-vm", "arm64 · 2 cpu · 4 GiB", "running", StatusTone.Ok),
                          ModuleRow("sandbox", "amd64 · 2 cpu · 4 GiB", "stopped", StatusTone.Warn),
                      ),
              ),
      )
}
