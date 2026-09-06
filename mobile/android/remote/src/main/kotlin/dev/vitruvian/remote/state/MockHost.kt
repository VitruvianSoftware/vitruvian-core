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
              id = 0,
              name = "atlas · MacBook Pro M4 Max",
              subtitle = "100.64.0.12 · macOS 26.1 · 64 GB",
              tone = StatusTone.Ok,
              tag = "connected",
              tagTone = TagTone.Ok,
          ),
          Host(
              id = 1,
              name = "forge · Mac mini M2",
              subtitle = "100.64.0.31 · macOS 26.0 · 16 GB",
              tone = StatusTone.Neutral,
              tag = "asleep",
              tagTone = TagTone.Neutral,
          ),
      )

  /** The offline variant of the selected host's sub-line. */
  public const val OFFLINE_SUBTITLE: String = "100.64.0.12 · last seen 4 m ago"

  public val builtInMacros: List<Macro> =
      listOf(
          Macro(
              "deploy",
              "Deploy staging",
              "bazel run //tools/gitops:sync -- staging",
              MacroKind.Ssh),
          Macro("tidy", "Tidy repo", "bazel run //:tidy", MacroKind.Ssh),
          Macro("shot", "Screenshot → clip", "screencapture -c", MacroKind.AppleScript),
          Macro(
              "mute",
              "Mute",
              "osascript -e \"set volume output muted true\"",
              MacroKind.AppleScript,
          ),
      )

  public val runningNow: List<RunningItem> =
      listOf(
          RunningItem(
              "claude",
              "Claude Code",
              "2 sessions · vitruvian-core · 14.2k tokens",
              StatusTone.Run,
              "running",
              TagTone.Accent,
          ),
          RunningItem(
              "homelab",
              "Homelab · K3s",
              "3/3 servers ready · v1.32.4",
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
          GalleryEntry("claude", "Claude Code", "Sessions, transcript, prompt relay", "mcp"),
          GalleryEntry("antigravity", "Antigravity", "Builds, evals, queue", "http"),
          GalleryEntry("homelab", "Homelab · K3s", "Nodes, workloads, ArgoCD sync", "ssh"),
          GalleryEntry("lima", "Lima VMs", "Instances, start / stop, resources", "ssh"),
          GalleryEntry("docker", "Docker", "Containers, images, logs", "ssh"),
          GalleryEntry("grafana", "Grafana panel", "Any panel by URL or PromQL", "promql"),
          GalleryEntry("ollama", "Ollama", "Models, ANE load, chat relay", "http"),
          GalleryEntry("xcode", "Xcode builds", "Schemes, last build, warnings", "applescript"),
      )

  public val defaultInstalled: Set<String> = setOf("claude", "antigravity", "homelab", "lima")

  public val processes: List<Process> =
      listOf(
          Process("claude", 38, "1.9 GB"),
          Process("com.apple.Virtualization", 22, "8.4 GB"),
          Process("ollama", 14, "5.1 GB"),
          Process("bazel (java)", 9, "3.2 GB"),
          Process("WindowServer", 4, "612 MB"),
      )

  public val vms: List<Vm> =
      listOf(
          Vm(
              "k8s-node-1 · cp-1",
              "arm64 · 4 cpu · 8 GiB · k3s server",
              StatusTone.Ok,
              "ready",
              TagTone.Ok),
          Vm(
              "k8s-node-2 · cp-2",
              "arm64 · 2 cpu · 4 GiB · k3s server",
              StatusTone.Ok,
              "ready",
              TagTone.Ok),
          Vm(
              "k8s-node-3 · cp-3",
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
          TerminalLine("$", "bazel run //:doctor", TerminalTone.Text),
          TerminalLine(
              " ", "ok  bazelisk 1.22 · node 22.21.1 · pnpm 10.20.0 · go 1.23", TerminalTone.Ok),
          TerminalLine("$", "homelab status", TerminalTone.Text),
          TerminalLine(" ", "3/3 servers ready · k3s v1.32.4 · etcd healthy", TerminalTone.Ok),
          TerminalLine("$", "limactl list", TerminalTone.Text),
          TerminalLine(
              " ",
              "k8s-node-1 Running · k8s-node-2 Running · k8s-node-3 Stopped",
              TerminalTone.Dim,
          ),
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
          TerminalLine(" ", "! tidy check pending — run bazel run //:tidy?", TerminalTone.Warn),
      )

  public val recentCommands: List<String> =
      listOf(
          "homelab status",
          "limactl list",
          "docker ps",
          "bazel run //:doctor",
          "git log --oneline -5",
      )

  /** Canned output for the console's fake shell. */
  public fun output(command: String): String =
      when {
        command.startsWith("docker") -> "grafana  prometheus  loki  minio  zitadel — Up"
        command.startsWith("git") -> "e7c2d11 feat(auth): propagate ctx\n2b9a410 chore: tidy"
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
                  meta = "nexus-agent bridge · ~/code/vitruvian-core",
                  status = "running",
                  statusTone = StatusTone.Run,
                  metrics =
                      listOf(
                          ModuleMetric("Sessions", "2", "main · worktree/auth"),
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
                              "worktree/auth · 18m",
                              "live",
                              StatusTone.Run),
                          ModuleRow("PR #1551 monitor", "main · idle 2h", "2h", StatusTone.Ok),
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
                          ModuleRow("#410 · pr/1551", "eval · failed 2", "err", StatusTone.Crit),
                      ),
              ),
          "homelab" to
              ModuleDashboard(
                  id = "homelab",
                  name = "Homelab · K3s",
                  meta = "my-homelab · 3 servers · Lima VZ",
                  status = "ready",
                  statusTone = StatusTone.Ok,
                  metrics =
                      listOf(
                          ModuleMetric("Nodes", "3/3", "embedded etcd"),
                          ModuleMetric("Workloads", "41", "+3 today"),
                          ModuleMetric("ArgoCD", "synced", "19 apps"),
                      ),
                  streamLabel = "homelab status",
                  lines =
                      listOf(
                          TerminalLine("$", "homelab status", TerminalTone.Text),
                          TerminalLine(
                              " ", "cp-1 ready · cp-2 ready · cp-3 ready", TerminalTone.Ok),
                          TerminalLine(" ", "etcd healthy · last snapshot 02:00", TerminalTone.Dim),
                      ),
                  cursor = false,
                  prompts = false,
                  listLabel = "Nodes",
                  rows =
                      listOf(
                          ModuleRow(
                              "mac-1 · cp-1", "server · 2 cpu · 4 GiB", "ready", StatusTone.Ok),
                          ModuleRow(
                              "mac-2 · cp-2", "server · 2 cpu · 4 GiB", "ready", StatusTone.Ok),
                          ModuleRow(
                              "mac-3 · cp-3", "server · 4 cpu · 8 GiB", "ready", StatusTone.Ok),
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
                          TerminalLine(
                              " ", "k8s-node-1 Running · k8s-node-2 Running", TerminalTone.Ok),
                          TerminalLine(" ", "k8s-node-3 Stopped", TerminalTone.Warn),
                      ),
                  cursor = false,
                  prompts = false,
                  listLabel = "Instances",
                  rows =
                      listOf(
                          ModuleRow(
                              "k8s-node-1", "arm64 · 4 cpu · 8 GiB", "running", StatusTone.Ok),
                          ModuleRow(
                              "k8s-node-2", "arm64 · 2 cpu · 4 GiB", "running", StatusTone.Ok),
                          ModuleRow(
                              "k8s-node-3", "amd64 · 2 cpu · 4 GiB", "stopped", StatusTone.Warn),
                      ),
              ),
      )
}
