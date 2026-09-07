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

package metrics

import (
	"os"
	"testing"
)

// The fixtures below were captured on the same machine and day as the ones in
// metrics_test.go (MacBook Pro M4 Max, macOS 26.5.2, 2026-09-06). Two are
// noted where they are not: podman and the "wedged node" k8s row, which this
// machine could not produce and which are documented at the fixture.

const fixturePS = ` %CPU    RSS COMM
 96.7  46992 fseventsd
 94.3   7120 top
 14.1 589136 Google Chrome Helper (Renderer)
 12.9 5638688 com.apple.Virtualization.VirtualMachine
  8.5 520512 loginwindow
  6.6 296496 Gemini
  6.0 3744352 Google Chrome
  4.3 445536 WindowServer
`

func TestParseProcessesKeepsNamesWithSpaces(t *testing.T) {
	got, err := ParseProcesses(fixturePS, 8)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 8 {
		t.Fatalf("want 8 rows, got %d: %+v", len(got), got)
	}
	if got[0].Name != "fseventsd" || got[0].CPUPercent != 96.7 {
		t.Errorf("first row: %+v", got[0])
	}
	// The whole tail of the line is the name. A Fields-based parser reports
	// this process as "Google", which is a different process.
	if got[2].Name != "Google Chrome Helper (Renderer)" {
		t.Errorf("name with spaces was truncated: %q", got[2].Name)
	}
	// ps prints RSS in KiB; the API only ever speaks bytes.
	if got[3].MemoryBytes != 5638688*1024 {
		t.Errorf("rss must be KiB -> bytes, got %d", got[3].MemoryBytes)
	}
	// The header must never become a row, whatever the limit.
	for _, p := range got {
		if p.Name == "COMM" {
			t.Fatal("the header line was parsed as a process")
		}
	}
	if got, _ := ParseProcesses(fixturePS, 3); len(got) != 3 {
		t.Errorf("limit ignored: %d rows", len(got))
	}
	if _, err := ParseProcesses(" %CPU    RSS COMM\n", 8); err == nil {
		t.Error("a header with no rows must be an error, not an empty list")
	}
}

func TestParseLimaListIgnoresTheConfigBlob(t *testing.T) {
	// The fixture is `limactl list --json` verbatim, kept in testdata because
	// each line is ~3 KB: limactl prints every instance's fully resolved
	// config -- images, mounts, provisioning scripts -- alongside the seven
	// fields anyone wants. That bulk is exactly what this test pins as
	// ignorable.
	out, err := os.ReadFile("testdata/limactl-list.jsonl")
	if err != nil {
		t.Fatal(err)
	}
	vms, err := ParseLimaList(string(out))
	if err != nil {
		t.Fatal(err)
	}
	if len(vms) != 2 {
		t.Fatalf("want 2 instances (one per line, not a JSON array), got %d", len(vms))
	}
	stopped, running := vms[0], vms[1]
	if stopped.Name != "alice-dev-machine" || stopped.Status != "Stopped" {
		t.Errorf("stopped instance: %+v", stopped)
	}
	if running.Name != "k8s-node" || running.Status != "Running" {
		t.Errorf("running instance: %+v", running)
	}
	if running.VMType != "vz" || running.Arch != "aarch64" || running.CPUs != 2 {
		t.Errorf("shape: %+v", running)
	}
	// memory and disk are already bytes in limactl's JSON, unlike the "4GiB"
	// strings in the nested config -- the wrong one of the two is a factor of
	// a billion out.
	if running.MemoryBytes != 4294967296 || running.DiskBytes != 107374182400 {
		t.Errorf("sizes: %+v", running)
	}
	if _, err := ParseLimaList("{not json}\n"); err == nil {
		t.Error("garbage must be an error, not an empty list")
	}
}

func TestParseDockerPS(t *testing.T) {
	// docker's --format '{{json .}}' emits one object per line and its Names
	// is a comma-separated STRING, not the array the Docker API returns.
	out := `{"Command":"\"/docker-entrypoint.…\"","CreatedAt":"2026-09-06 10:02:11 -0700 PDT","ID":"9f2c1a0b7d31","Image":"nginx:1.27","Names":"proxy,web","Ports":"0.0.0.0:8080->80/tcp","Status":"Up 3 hours"}
{"Command":"\"redis-server\"","CreatedAt":"2026-09-05 22:41:03 -0700 PDT","ID":"2b7e5c9a44de","Image":"redis:7","Names":"cache","Ports":"6379/tcp","Status":"Up 12 hours (healthy)"}
`
	cs, err := ParseDockerPS(out)
	if err != nil {
		t.Fatal(err)
	}
	if len(cs) != 2 {
		t.Fatalf("want 2, got %d", len(cs))
	}
	if cs[0].Name != "proxy" || cs[0].Image != "nginx:1.27" || cs[0].Status != "Up 3 hours" {
		t.Errorf("first: %+v", cs[0])
	}
	if cs[1].Name != "cache" {
		t.Errorf("second: %+v", cs[1])
	}
	if got, err := ParseDockerPS(""); err != nil || len(got) != 0 {
		t.Errorf("no containers is an empty list, not an error: %+v %v", got, err)
	}
}

func TestParsePodmanPS(t *testing.T) {
	// Constructed from podman's documented `ps --format json` schema: this
	// machine has podman installed but no running machine, so its real output
	// is the connection error the sampler turns into a reason string. The
	// shape difference from docker is the point -- one array, Names is a
	// real array of strings.
	out := `[{"Id":"5f0d","Image":"docker.io/library/alpine:3.20","Names":["tidy_hopper"],"Status":"Up 2 minutes"}]`
	cs, err := ParsePodmanPS(out)
	if err != nil {
		t.Fatal(err)
	}
	if len(cs) != 1 || cs[0].Name != "tidy_hopper" || cs[0].Image != "docker.io/library/alpine:3.20" {
		t.Errorf("got %+v", cs)
	}
	if got, err := ParsePodmanPS("[]"); err != nil || len(got) != 0 {
		t.Errorf("empty array: %+v %v", got, err)
	}
}

// fixtureNodes is `kubectl get nodes -o json` from the dev-local k3s cluster,
// reduced to the fields the parser reads plus enough of the ones it must
// ignore to prove it does. The real document is 155 KB for seven nodes.
// The third node is edited: its Ready condition is "Unknown", the state a
// kubelet that has stopped reporting leaves behind. No node on that cluster
// was in it, and it is the state a naive `!= "False"` check paints green.
const fixtureNodes = `{
  "apiVersion": "v1",
  "kind": "List",
  "items": [
    {
      "apiVersion": "v1",
      "kind": "Node",
      "metadata": {
        "name": "fedora",
        "labels": {
          "kubernetes.io/arch": "amd64",
          "kubernetes.io/hostname": "fedora",
          "node-role.kubernetes.io/etcd": "true",
          "node-role.kubernetes.io/control-plane": "true"
        }
      },
      "status": {
        "conditions": [
          {"type": "MemoryPressure", "status": "False"},
          {"type": "Ready", "status": "True"}
        ],
        "nodeInfo": {"kubeletVersion": "v1.35.3+k3s1", "osImage": "Fedora Linux 42"}
      }
    },
    {
      "apiVersion": "v1",
      "kind": "Node",
      "metadata": {
        "name": "james-mbp16",
        "labels": {"kubernetes.io/arch": "arm64"}
      },
      "status": {
        "conditions": [{"type": "Ready", "status": "True"}],
        "nodeInfo": {"kubeletVersion": "v1.35.3+k3s1"}
      }
    },
    {
      "apiVersion": "v1",
      "kind": "Node",
      "metadata": {
        "name": "nuc9i9",
        "labels": {"node-role.kubernetes.io/worker": "true"}
      },
      "status": {
        "conditions": [{"type": "Ready", "status": "Unknown"}],
        "nodeInfo": {"kubeletVersion": "v1.35.3+k3s1"}
      }
    }
  ]
}`

func TestParseKubectlNodes(t *testing.T) {
	nodes, err := ParseKubectlNodes(fixtureNodes)
	if err != nil {
		t.Fatal(err)
	}
	if len(nodes) != 3 {
		t.Fatalf("want 3 nodes, got %d", len(nodes))
	}
	if nodes[0].Name != "fedora" || !nodes[0].Ready || nodes[0].Version != "v1.35.3+k3s1" {
		t.Errorf("first node: %+v", nodes[0])
	}
	// Roles come from labels and are sorted, because Go randomises map order
	// and a client polling this must not see the list reshuffle every tick.
	if len(nodes[0].Roles) != 2 || nodes[0].Roles[0] != "control-plane" || nodes[0].Roles[1] != "etcd" {
		t.Errorf("roles: %+v", nodes[0].Roles)
	}
	// A plain worker has no role labels. Empty list, not nil, so the JSON is
	// [] rather than null.
	if nodes[1].Roles == nil || len(nodes[1].Roles) != 0 {
		t.Errorf("unlabelled node roles: %+v", nodes[1].Roles)
	}
	// Ready="Unknown" is NOT ready. This is the assertion that catches a
	// parser written as `status != "False"`.
	if nodes[2].Ready {
		t.Error(`a node with Ready="Unknown" was reported ready`)
	}
	if _, err := ParseKubectlNodes("Unable to connect to the server"); err == nil {
		t.Error("kubectl's error text must not parse as zero nodes")
	}
}

func TestParseVolumeSettings(t *testing.T) {
	a, err := ParseVolumeSettings("output volume:31, input volume:86, alert volume:50, output muted:false\n")
	if err != nil {
		t.Fatal(err)
	}
	if a.VolumePercent != 31 || a.Muted {
		t.Errorf("got %+v", a)
	}
	// Muted is independent of the volume: a muted Mac still remembers where
	// the slider was, and reporting 0% would lose that on unmute.
	a, err = ParseVolumeSettings("output volume:31, input volume:86, alert volume:50, output muted:true\n")
	if err != nil || !a.Muted || a.VolumePercent != 31 {
		t.Errorf("muted: %+v %v", a, err)
	}
	// Some output devices report no volume at all. That is an error, not 0%.
	if _, err := ParseVolumeSettings("output volume:missing value, output muted:missing value\n"); err == nil {
		t.Error("missing value must be an error")
	}
}

func TestParseEther(t *testing.T) {
	out := `en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	options=6460<TSO4,TSO6,CHANNEL_IO,PARTIAL_CSUM,ZEROINVERT_CSUM>
	ether a2:26:7e:45:c1:2d
	inet6 fe80::c4b:7b0f:5d3c:1a2b%en0 prefixlen 64 secured scopeid 0xe
	inet 192.168.1.44 netmask 0xffffff00 broadcast 192.168.1.255
	media: autoselect
	status: active
`
	mac, err := ParseEther(out)
	if err != nil || mac != "a2:26:7e:45:c1:2d" {
		t.Errorf("got %q %v", mac, err)
	}
	if _, err := ParseEther("lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384\n"); err == nil {
		t.Error("an interface with no ether line must be an error")
	}
}

func TestParseWomp(t *testing.T) {
	// Trimmed from `pmset -g` on this machine; the womp line is the one that
	// decides whether Wake-on-LAN is worth offering at all.
	on := `System-wide power settings:
Currently in use:
 standby              1
 womp                 1
 halfdim              1
`
	if !ParseWomp(on) {
		t.Error("womp 1 means Wake-on-LAN works")
	}
	if ParseWomp("Currently in use:\n womp                 0\n") {
		t.Error("womp 0 means a magic packet will not wake this Mac")
	}
	// A machine that cannot do it at all prints no womp line. Absence is
	// false, not an error and not true.
	if ParseWomp("Currently in use:\n standby              1\n") {
		t.Error("no womp line must be false")
	}
}

func TestCountProcessesNamedMatchesTheBasenameOnly(t *testing.T) {
	// Verbatim `ps -Axo comm= | grep -i claude` from this machine, which had
	// exactly two Claude Code sessions running. Six lines contain "claude";
	// a substring match reports three times the truth.
	out := `/Applications/Claude.app/Contents/Helpers/chrome-native-host
/Users/alice/.vscode-insiders/extensions/anthropic.claude-code-2.1.263-darwin-arm64/resources/native-binary/claude
/Users/alice/Library/Application Support/Claude/Claude Extensions/ant.dir.gh.grafana.grafana-mcp/server/darwin-arm64/mcp-grafana
/Users/alice/.vscode-insiders/extensions/anthropic.claude-code-2.1.263-darwin-arm64/resources/native-binary/claude
/Users/alice/.claude/telegram-bot/.venv/bin/python
/Users/alice/Library/Application Support/Claude/Claude Extensions/ant.dir.gh.grafana.grafana-mcp/server/darwin-arm64/mcp-grafana
`
	if n := CountProcessesNamed(out, "claude"); n != 2 {
		t.Errorf("want 2 claude processes, got %d", n)
	}
	if n := CountProcessesNamed("", "claude"); n != 0 {
		t.Errorf("empty output: %d", n)
	}
}

func TestProjectFromDirName(t *testing.T) {
	if got := ProjectFromDirName("-Users-james-Workspace-vitruvian"); got != "Users/james/Workspace/vitruvian" {
		t.Errorf("got %q", got)
	}
	// The encoding is lossy and this pins the loss rather than pretending it
	// away: the real directory is .../vitruvian/vitruvian-core, and the
	// hyphen inside "vitruvian-core" is indistinguishable from a separator.
	// A client must treat this as a label, never as a path to open.
	got := ProjectFromDirName("-Users-james-Workspace-vitruvian-vitruvian-core")
	if got != "Users/james/Workspace/vitruvian/vitruvian/core" {
		t.Errorf("got %q", got)
	}
	if ProjectFromDirName("-private-tmp") != "private/tmp" {
		t.Errorf("got %q", ProjectFromDirName("-private-tmp"))
	}
}

func TestCwdFromTranscriptBeatsTheLossyDirName(t *testing.T) {
	// Real head of a transcript for a worktree whose path contains both
	// hyphens and a dot-directory. The dir name encodes it as
	// -Users-alice-src-acme--claude-worktrees-new-android-app-setup-355ad3
	// which no decoder can turn back into the path below.
	head := `{"type":"user","cwd":"/Users/alice/src/acme/.claude/worktrees/new-android-app-setup-355ad3","sessionId":"b4d0"}` + "\n" +
		`{"type":"assistant","cwd":"/somewhere/else"}`
	got := CwdFromTranscript(head)
	want := "/Users/alice/src/acme/.claude/worktrees/new-android-app-setup-355ad3"
	if got != want {
		t.Errorf("got %q want %q", got, want)
	}
	if CwdFromTranscript(`{"type":"user"}`) != "" {
		t.Error("no cwd must give empty, not a guess")
	}
}

func TestParseOllamaListAndPs(t *testing.T) {
	// Verbatim `ollama list` from a Mac with three models (columns are
	// space-padded; a cell may contain one space, so the split is on two+).
	list := "NAME                        ID              SIZE      MODIFIED     \n" +
		"qwen3.6:35b-a3b-q4_K_M      07d35212591f    23 GB     4 months ago    \n" +
		"gemma4:e4b-it-q4_K_M        c6eb396dbd59    9.6 GB    5 months ago    \n" +
		"gemma4:26b-a4b-it-q4_K_M    5571076f3d70    17 GB     5 months ago    \n"
	m, err := ParseOllamaList(list)
	if err != nil || len(m) != 3 {
		t.Fatalf("got %d models, err %v", len(m), err)
	}
	if m[1].Name != "gemma4:e4b-it-q4_K_M" || m[1].SizeBytes != 9_600_000_000 || m[1].Modified != "5 months ago" {
		t.Errorf("row 1 wrong: %+v", m[1])
	}
	// Idle ollama: header only. That is the normal state, not an error, and
	// must not come back as available:false.
	ps, err := ParseOllamaPs("NAME    ID    SIZE    PROCESSOR    CONTEXT    UNTIL \n")
	if err != nil || len(ps) != 0 {
		t.Errorf("idle ps: got %v %v", ps, err)
	}
	loaded := "NAME                    ID              SIZE     PROCESSOR    CONTEXT    UNTIL              \n" +
		"gemma4:e4b-it-q4_K_M    c6eb396dbd59    11 GB    100% GPU     4096       4 minutes from now    \n"
	ps, err = ParseOllamaPs(loaded)
	if err != nil || len(ps) != 1 || ps[0].Processor != "100% GPU" || ps[0].Context != 4096 || ps[0].Until != "4 minutes from now" {
		t.Errorf("loaded ps wrong: %+v %v", ps, err)
	}
	if ParseOllamaSize("512 MB") != 512_000_000 || ParseOllamaSize("garbage") != 0 {
		t.Error("size parsing")
	}
	if _, err := ParseOllamaList("Error: could not connect to ollama app"); err == nil {
		t.Error("a non-table response must be an error, not zero models")
	}
}
