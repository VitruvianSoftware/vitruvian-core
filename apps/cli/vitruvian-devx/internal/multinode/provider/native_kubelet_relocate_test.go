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

package provider

import (
	"bytes"
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/config"
)

// reply maps a command substring to an answer; the first match wins.
type reply struct {
	match string
	out   string
	err   error
}

// fakeHost records every command and answers by ordered substring match.
type fakeHost struct {
	replies []reply
	calls   []string
}

func (f *fakeHost) run(ctx context.Context, cmd string) (string, error) {
	f.calls = append(f.calls, cmd)
	for _, r := range f.replies {
		if strings.Contains(cmd, r.match) {
			return r.out, r.err
		}
	}
	return "", nil
}

func (f *fakeHost) ran(substr string) bool { return f.index(substr) >= 0 }

func (f *fakeHost) index(substr string) int {
	for i, c := range f.calls {
		if strings.Contains(c, substr) {
			return i
		}
	}
	return -1
}

// prepend puts replies ahead of the defaults so they win.
func (f *fakeHost) prepend(r ...reply) { f.replies = append(r, f.replies...) }

const (
	nodeUnit  = "[Service]\nExecStart=/usr/local/bin/k3s server\n"
	kubeNodes = "nuc9     Ready   control-plane,etcd,master   200d   v1.33.5+k3s1\n" +
		"nuc10    Ready   control-plane,etcd,master   200d   v1.33.5+k3s1\n" +
		"nuc9i5   Ready   control-plane,etcd,master   100d   v1.33.5+k3s1\n"
)

// nuc9i5Host fakes nuc9i5 as it is today: a k3s server whose config.yaml carries
// root-dir=/home/k3s/kubelet, with /var/lib/kubelet a symlink to it.
func nuc9i5Host() *fakeHost {
	return &fakeHost{replies: []reply{
		{match: "systemctl cat k3s.service", out: "present"},
		{match: "cat /etc/rancher/k3s/config.yaml", out: nuc9i5ConfigYAML},
		{match: "cat /etc/systemd/system/k3s.service", out: nodeUnit},
		{match: "grep -rls", out: "/etc/rancher/k3s/config.yaml"},
		{match: "echo mounted || echo not-mounted", out: "not-mounted"},
		{match: "readlink /var/lib/kubelet", out: "/home/k3s/kubelet"},
		{match: "date -u", out: "2026-11-20T10:00:00Z"},
		{match: "findmnt /var/lib/kubelet", out: "TARGET            SOURCE                       FSTYPE OPTIONS\n/var/lib/kubelet /dev/mapper/fedora-home[/k3s/kubelet] ext4   rw\nbind mount OK: /var/lib/kubelet is /home/k3s/kubelet"},
		{match: "df -B1", out: "479670088000"},
	}}
}

func controlHost() *fakeHost {
	return &fakeHost{replies: []reply{
		{match: "get nodes --no-headers", out: kubeNodes},
		{match: "jsonpath='{.status.conditions", out: "True 2026-11-20T10:00:42Z"},
		{match: "capacity.ephemeral-storage", out: "468428992Ki"}, // 479670088000 bytes
	}}
}

func relocateProvider(role string, h *fakeHost) *NativeProvider {
	p := NewNativeProvider(config.NodeConfig{
		Host: "nuc9i5", Kind: "native", Role: role, Pool: "nuc-worker-1", DataDir: "/home/k3s",
	}, &config.Config{})
	p.run = h.run
	return p
}

func relocateOpts(ctl *fakeHost, apply bool, out *bytes.Buffer) RelocateOptions {
	return RelocateOptions{
		Apply: apply, Control: ctl.run, ControlHost: "nuc9", OtherServers: []string{"nuc9", "nuc10"},
		DrainTimeout: 5 * time.Minute, ReadyTimeout: 50 * time.Millisecond, PollInterval: time.Millisecond,
		Out: out, Command: "devx cluster relocate-kubelet --host nuc9i5",
	}
}

// Read-only commands a dry run (or a refusal) may issue.
var readOnlyPrefixes = []string{"systemctl cat ", "cat /etc/", "grep -rls", "mountpoint -q /var/lib/kubelet && echo", "readlink ", "k3s kubectl get nodes --no-headers"}

func assertReadOnly(t *testing.T, name string, calls []string) {
	t.Helper()
	for _, c := range calls {
		ok := false
		for _, p := range readOnlyPrefixes {
			if strings.HasPrefix(c, p) {
				ok = true
			}
		}
		if !ok {
			t.Errorf("%s: issued a non-read-only command: %s", name, c)
		}
	}
}

func stepIDs(plan *RelocationPlan) string {
	var ids []string
	for _, s := range plan.Steps {
		ids = append(ids, s.ID)
	}
	return strings.Join(ids, ",")
}

func TestRelocate_DryRunPlan(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	var out bytes.Buffer
	if err := relocateProvider("server", node).RelocateKubelet(context.Background(), relocateOpts(ctl, false, &out)); err != nil {
		t.Fatalf("dry run: %v", err)
	}
	t.Logf("dry-run output for nuc9i5:\n%s", out.String())

	// A dry run only reads.
	assertReadOnly(t, "node", node.calls)
	assertReadOnly(t, "control", ctl.calls)

	plan, err := relocateProvider("server", nuc9i5Host()).PlanKubeletRelocation(context.Background(), relocateOpts(controlHost(), false, &bytes.Buffer{}))
	if err != nil {
		t.Fatal(err)
	}
	want := strings.Join([]string{stepCordon, stepDrain, stepStop, stepKillall, stepUnmount, stepConfig, stepBindMount, stepStamp, stepStart, stepReady, stepUncordon}, ",")
	if got := stepIDs(plan); got != want {
		t.Errorf("steps = %s\nwant    %s", got, want)
	}
	text := out.String()
	for _, want := range []string{
		"k3s kubectl cordon nuc9i5",
		"k3s kubectl drain nuc9i5 --ignore-daemonsets --delete-emptydir-data --timeout=300s",
		"systemctl stop k3s.service",
		"systemctl start k3s.service",
		"k3s kubectl uncordon nuc9i5",
		"enable --now var-lib-kubelet.mount",
		"findmnt /var/lib/kubelet",
		"capacity.ephemeral-storage",
		"Dry run: only read-only checks were made. Nothing was changed.",
		"--apply",
	} {
		if !strings.Contains(text, want) {
			t.Errorf("dry-run output missing %q", want)
		}
	}
	// kubectl runs on another control-plane node; node commands on the node.
	for _, s := range plan.Steps {
		switch s.ID {
		case stepCordon, stepDrain, stepReady, stepUncordon:
			if !s.OnControl {
				t.Errorf("%s must run on the control node", s.ID)
			}
		default:
			if s.OnControl {
				t.Errorf("%s must run on the node itself", s.ID)
			}
		}
		shellSafe(t, s.Cmd)
	}
	// The config edit removes only root-dir.
	for _, s := range plan.Steps {
		if s.ID != stepConfig {
			continue
		}
		newCfg := decodeWrites(t, s.Cmd)["/etc/rancher/k3s/config.yaml.devx-new"]
		if newCfg == "" || strings.Contains(newCfg, "root-dir") || decodeMap(t, newCfg)["data-dir"] != "/home/k3s" {
			t.Errorf("bad config rewrite:\n%s", newCfg)
		}
		if !strings.Contains(s.Cmd, "cp -p /etc/rancher/k3s/config.yaml /etc/rancher/k3s/config.yaml.pre-relocate-kubelet") {
			t.Errorf("config must be backed up first: %s", s.Cmd)
		}
	}
}

func TestRelocate_PlanIncludesExecStartEditWhenPresent(t *testing.T) {
	node := nuc9i5Host()
	node.prepend(
		reply{match: "cat /etc/systemd/system/k3s.service", out: k3sServerUnit},
		reply{match: "grep -rls", out: "/etc/rancher/k3s/config.yaml\n/etc/systemd/system/k3s.service"},
	)
	plan, err := relocateProvider("server", node).PlanKubeletRelocation(context.Background(), relocateOpts(controlHost(), false, &bytes.Buffer{}))
	if err != nil {
		t.Fatal(err)
	}
	var cmd string
	for _, s := range plan.Steps {
		if s.ID == stepUnit {
			cmd = s.Cmd
		}
	}
	if cmd == "" {
		t.Fatal("expected a unit edit step")
	}
	newUnit := decodeWrites(t, cmd)["/etc/systemd/system/k3s.service.devx-new"]
	if strings.Contains(newUnit, "root-dir") || !strings.Contains(newUnit, "'--node-label=pool=nuc'") {
		t.Errorf("bad unit rewrite:\n%s", newUnit)
	}
	if !strings.Contains(cmd, "cp -p /etc/systemd/system/k3s.service /etc/systemd/system/k3s.service.pre-relocate-kubelet") {
		t.Errorf("unit must be backed up first: %s", cmd)
	}
}

func TestRelocate_ResumesAnInterruptedRun(t *testing.T) {
	// config.yaml no longer has root-dir, /var/lib/kubelet is still the symlink:
	// an earlier run stopped after the edit. The plan skips the edit.
	node := nuc9i5Host()
	node.prepend(
		reply{match: "cat /etc/rancher/k3s/config.yaml", out: "data-dir: /home/k3s\n"},
		reply{match: "grep -rls", out: ""},
	)
	var out bytes.Buffer
	plan, err := relocateProvider("server", node).PlanKubeletRelocation(context.Background(), relocateOpts(controlHost(), false, &out))
	if err != nil {
		t.Fatalf("resume must plan: %v", err)
	}
	for _, s := range plan.Steps {
		if s.ID == stepConfig || s.ID == stepUnit {
			t.Errorf("nothing left to edit, but plan has %s", s.ID)
		}
	}
	plan.Print(&out)
	if !strings.Contains(out.String(), "interrupted") {
		t.Errorf("the plan should say it is resuming:\n%s", out.String())
	}
}

func TestRelocate_Refusals(t *testing.T) {
	plainNode := func(cfg config.NodeConfig) func(*fakeHost) *NativeProvider {
		return func(h *fakeHost) *NativeProvider {
			p := NewNativeProvider(cfg, &config.Config{})
			p.run = h.run
			return p
		}
	}
	cases := []struct {
		name    string
		mutate  func(node, ctl *fakeHost)
		prov    func(*fakeHost) *NativeProvider
		want    error
		mention string
	}{
		{
			name: "no dataDir",
			prov: plainNode(config.NodeConfig{Host: "nuc9i5", Kind: "native", Role: "server"}),
			want: ErrRelocateNoDataDir, mention: "nothing to relocate",
		},
		{
			name: "not a native node",
			prov: plainNode(config.NodeConfig{Host: "mac1", Kind: "lima", Role: "server", DataDir: "/x"}),
			want: ErrNotNative,
		},
		{
			name: "already relocated",
			mutate: func(node, _ *fakeHost) {
				node.prepend(
					reply{match: "cat /etc/rancher/k3s/config.yaml", out: "data-dir: /home/k3s\n"},
					reply{match: "grep -rls", out: ""},
					reply{match: "echo mounted || echo not-mounted", out: "mounted"},
					reply{match: "readlink /var/lib/kubelet", out: ""},
				)
			},
			want: ErrKubeletAlreadyRelocated, mention: "already",
		},
		{
			name: "kubelet is not at dataDir/kubelet (default path, no bind mount)",
			mutate: func(node, _ *fakeHost) {
				node.prepend(
					reply{match: "cat /etc/rancher/k3s/config.yaml", out: "data-dir: /home/k3s\n"},
					reply{match: "grep -rls", out: ""},
					reply{match: "readlink /var/lib/kubelet", out: ""},
				)
			},
			want: ErrKubeletNotAtDataDir, mention: "/home/k3s/kubelet",
		},
		{
			name: "root-dir points somewhere else",
			mutate: func(node, _ *fakeHost) {
				node.prepend(reply{match: "cat /etc/rancher/k3s/config.yaml", out: "data-dir: /home/k3s\nkubelet-arg:\n- root-dir=/mnt/other/kubelet\n"})
			},
			want: ErrKubeletNotAtDataDir, mention: "/mnt/other/kubelet",
		},
		{
			name: "root-dir set in a drop-in devx does not edit",
			mutate: func(node, _ *fakeHost) {
				node.prepend(reply{match: "grep -rls", out: "/etc/rancher/k3s/config.yaml\n/etc/rancher/k3s/config.yaml.d/10-kubelet.yaml"})
			},
			want: ErrRootDirUnsupported, mention: "10-kubelet.yaml",
		},
		{
			name: "another control-plane node is not Ready (etcd quorum)",
			mutate: func(_, ctl *fakeHost) {
				ctl.prepend(reply{match: "get nodes --no-headers", out: "nuc9 Ready control-plane 1d v1\nnuc10 NotReady control-plane 1d v1\nnuc9i5 Ready control-plane 1d v1\n"})
			},
			want: ErrQuorumRisk, mention: "nuc10",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			node, ctl := nuc9i5Host(), controlHost()
			if tc.mutate != nil {
				tc.mutate(node, ctl)
			}
			prov := tc.prov
			if prov == nil {
				prov = func(h *fakeHost) *NativeProvider { return relocateProvider("server", h) }
			}
			var out bytes.Buffer
			err := prov(node).RelocateKubelet(context.Background(), relocateOpts(ctl, true, &out)) // even with --apply
			if !errors.Is(err, tc.want) {
				t.Fatalf("err = %v, want %v", err, tc.want)
			}
			if tc.mention != "" && !strings.Contains(err.Error(), tc.mention) {
				t.Errorf("error should mention %q: %v", tc.mention, err)
			}
			// A refusal changes nothing, even with --apply.
			assertReadOnly(t, "node", node.calls)
			assertReadOnly(t, "control", ctl.calls)
			if strings.Contains(out.String(), "Applying") {
				t.Errorf("a refusal must not start applying:\n%s", out.String())
			}
		})
	}
}

func TestRelocate_NodeMissingFromClusterIsRefused(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	ctl.prepend(reply{match: "get nodes --no-headers", out: "nuc9 Ready control-plane 1d v1\n"})
	err := relocateProvider("server", node).RelocateKubelet(context.Background(), relocateOpts(ctl, true, &bytes.Buffer{}))
	if err == nil || !strings.Contains(err.Error(), "not in the cluster") {
		t.Errorf("err = %v", err)
	}
}

func TestRelocate_AgentIgnoresQuorum(t *testing.T) {
	node := nuc9i5Host()
	node.prepend(
		reply{match: "systemctl cat k3s-agent.service", out: "present"},
		reply{match: "cat /etc/systemd/system/k3s-agent.service", out: nodeUnit},
	)
	ctl := controlHost()
	ctl.prepend(reply{match: "get nodes --no-headers", out: "nuc9 NotReady control-plane 1d v1\nnuc9i5 Ready <none> 1d v1\n"})
	plan, err := relocateProvider("agent", node).PlanKubeletRelocation(context.Background(), relocateOpts(ctl, false, &bytes.Buffer{}))
	if err != nil {
		t.Fatalf("an agent does not affect etcd: %v", err)
	}
	if plan.Unit != "k3s-agent.service" {
		t.Errorf("unit = %s", plan.Unit)
	}
}

func TestRelocate_ApplyRunsEveryStepInOrderAndChecks(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	var out bytes.Buffer
	opts := relocateOpts(ctl, true, &out)
	opts.ReadyTimeout = time.Second
	if err := relocateProvider("server", node).RelocateKubelet(context.Background(), opts); err != nil {
		t.Fatalf("apply: %v\n%s", err, out.String())
	}
	t.Logf("apply output:\n%s", out.String())

	// Node side, in order.
	order := []string{"systemctl stop k3s.service", "k3s-killall.sh", "umount -l", "config.yaml.pre-relocate-kubelet", "enable --now var-lib-kubelet.mount", "date -u", "systemctl start k3s.service"}
	last := -1
	for _, want := range order {
		i := node.index(want)
		if i < 0 {
			t.Fatalf("node never ran %q; calls:\n%s", want, strings.Join(node.calls, "\n"))
		}
		if i <= last {
			t.Errorf("%q ran out of order (at %d, previous at %d)", want, i, last)
		}
		last = i
	}
	// Control side, in order: cordon, drain, uncordon.
	cordon, drain, uncordon := ctl.index("cordon nuc9i5"), ctl.index("drain nuc9i5"), ctl.index("uncordon nuc9i5")
	if !(0 <= cordon && cordon < drain && drain < uncordon) {
		t.Errorf("control order wrong: cordon=%d drain=%d uncordon=%d\n%s", cordon, drain, uncordon, strings.Join(ctl.calls, "\n"))
	}
	if !strings.Contains(out.String(), "bind mount OK") || !strings.Contains(out.String(), "ephemeral-storage OK") {
		t.Errorf("final check missing:\n%s", out.String())
	}
}

func TestRelocate_FinalCheckWarnsWhenCapacityIsNotTheBigVolume(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	ctl.prepend(reply{match: "capacity.ephemeral-storage", out: "30000000Ki"}) // the small root disk
	var out bytes.Buffer
	opts := relocateOpts(ctl, true, &out)
	opts.ReadyTimeout = time.Second
	if err := relocateProvider("server", node).RelocateKubelet(context.Background(), opts); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "WARNING: the node reports ephemeral-storage") {
		t.Errorf("must warn when ephemeral-storage is not the big volume:\n%s", out.String())
	}
}

func TestRelocate_FailureBeforeStopUncordonsAndTouchesNothing(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	ctl.prepend(reply{match: "drain nuc9i5", err: errors.New("Cannot evict pod: would violate the pod's disruption budget")})
	var out bytes.Buffer
	err := relocateProvider("server", node).RelocateKubelet(context.Background(), relocateOpts(ctl, true, &out))
	var rerr *RelocationError
	if !errors.As(err, &rerr) {
		t.Fatalf("want a RelocationError, got %v", err)
	}
	if rerr.Step != 2 || !strings.Contains(err.Error(), "disruption budget") {
		t.Errorf("step=%d err=%v", rerr.Step, err)
	}
	if !ctl.ran("k3s kubectl uncordon nuc9i5") {
		t.Errorf("a failed drain must uncordon the node again; control calls:\n%s", strings.Join(ctl.calls, "\n"))
	}
	if node.ran("systemctl stop") || node.ran("base64 -d") {
		t.Errorf("nothing on the node may change before the drain succeeds:\n%s", strings.Join(node.calls, "\n"))
	}
	if !strings.Contains(err.Error(), "never stopped") || !strings.Contains(err.Error(), "uncordoned again") {
		t.Errorf("the error must say the node is untouched and uncordoned:\n%v", err)
	}
}

func TestRelocate_FailureAfterStopSaysWhatStateAndHowToRecover(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	node.prepend(reply{match: "enable --now var-lib-kubelet.mount", err: errors.New("Failed to enable unit")})
	var out bytes.Buffer
	err := relocateProvider("server", node).RelocateKubelet(context.Background(), relocateOpts(ctl, true, &out))
	var rerr *RelocationError
	if !errors.As(err, &rerr) {
		t.Fatalf("want a RelocationError, got %v", err)
	}
	msg := err.Error()
	for _, want := range []string{
		"k3s.service is STOPPED",
		"config.yaml: root-dir already removed",
		"/etc/rancher/k3s/config.yaml.pre-relocate-kubelet",
		"CORDONED",
		"re-run: devx cluster relocate-kubelet --host nuc9i5 --apply",
		"systemctl start k3s.service",
		"k3s kubectl uncordon nuc9i5",
	} {
		if !strings.Contains(msg, want) {
			t.Errorf("failure report missing %q:\n%s", want, msg)
		}
	}
	if node.ran("systemctl start") {
		t.Error("k3s must not be started after a failed bind mount")
	}
	if ctl.ran("uncordon") {
		t.Error("a node that is down must stay cordoned, loudly")
	}
}

func TestRelocate_NotReadyInTimeLeavesItCordonedWithRecovery(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	// A heartbeat older than the start stamp: the previous kubelet's, not the new one's.
	ctl.prepend(reply{match: "jsonpath='{.status.conditions", out: "True 2026-11-20T09:59:00Z"})
	var out bytes.Buffer
	opts := relocateOpts(ctl, true, &out)
	opts.ReadyTimeout = 20 * time.Millisecond
	err := relocateProvider("server", node).RelocateKubelet(context.Background(), opts)
	var rerr *RelocationError
	if !errors.As(err, &rerr) {
		t.Fatalf("want a RelocationError, got %v", err)
	}
	for _, want := range []string{"k3s.service is STARTED", "CORDONED", "journalctl -u k3s.service", "k3s kubectl uncordon nuc9i5", "/var/lib/kubelet is now the bind mount"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("missing %q:\n%v", want, err)
		}
	}
	if ctl.ran("k3s kubectl uncordon") {
		t.Error("must not uncordon a node that never became Ready")
	}
}

func TestRelocate_StopFailureReportsUnknownUnitState(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	node.prepend(reply{match: "systemctl stop k3s.service", err: errors.New("ssh: connection lost")})
	err := relocateProvider("server", node).RelocateKubelet(context.Background(), relocateOpts(ctl, true, &bytes.Buffer{}))
	if err == nil {
		t.Fatal("expected an error")
	}
	for _, want := range []string{"the stop did not complete", "CORDONED"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("missing %q:\n%v", want, err)
		}
	}
}

func TestReadyAfter(t *testing.T) {
	for _, tc := range []struct {
		out, since string
		want       bool
	}{
		{"True 2026-11-20T10:00:42Z", "2026-11-20T10:00:00Z", true},
		{"True 2026-11-20T10:00:00Z", "2026-11-20T10:00:00Z", true},
		{"True 2026-11-20T09:59:59Z", "2026-11-20T10:00:00Z", false}, // the old kubelet's heartbeat
		{"False 2026-11-20T10:00:42Z", "2026-11-20T10:00:00Z", false},
		{"Unknown", "2026-11-20T10:00:00Z", false},
		{"True", "2026-11-20T10:00:00Z", false},
		{"True", "", true},
		{"", "", false},
	} {
		if got := readyAfter(tc.out, tc.since); got != tc.want {
			t.Errorf("readyAfter(%q, %q) = %v, want %v", tc.out, tc.since, got, tc.want)
		}
	}
}

func TestParseQuantityBytes(t *testing.T) {
	for in, want := range map[string]int64{"479670088Ki": 479670088 << 10, "512Gi": 512 << 30, "100": 100, " 2Mi\n": 2 << 20, "5G": 5_000_000_000} {
		got, err := parseQuantityBytes(in)
		if err != nil || got != want {
			t.Errorf("parseQuantityBytes(%q) = %d, %v; want %d", in, got, err, want)
		}
	}
	if _, err := parseQuantityBytes("lots"); err == nil {
		t.Error("garbage must be an error")
	}
}
