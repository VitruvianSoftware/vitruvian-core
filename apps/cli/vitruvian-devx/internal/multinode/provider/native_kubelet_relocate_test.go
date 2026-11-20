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
	"encoding/base64"
	"errors"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/config"
)

// reply maps a command substring to an answer; the first match wins. uses > 0
// limits how many times it answers before later replies take over.
type reply struct {
	match string
	out   string
	err   error
	uses  int
}

// fakeHost records every command and answers by ordered substring match.
type fakeHost struct {
	replies  []reply
	calls    []string
	ctxAware bool             // fail commands run on a cancelled context, like ssh would
	hook     func(cmd string) // called for every command before it is answered
}

func (f *fakeHost) run(ctx context.Context, cmd string) (string, error) {
	f.calls = append(f.calls, cmd)
	if f.hook != nil {
		f.hook(cmd)
	}
	if f.ctxAware && ctx.Err() != nil {
		return "", ctx.Err()
	}
	for i := range f.replies {
		r := &f.replies[i]
		if !strings.Contains(cmd, r.match) || r.uses < 0 {
			continue
		}
		if r.uses > 0 {
			if r.uses--; r.uses == 0 {
				r.uses = -1 // used up
			}
		}
		return r.out, r.err
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

func (f *fakeHost) count(substr string) int {
	n := 0
	for _, c := range f.calls {
		if strings.Contains(c, substr) {
			n++
		}
	}
	return n
}

// prepend puts replies ahead of the defaults so they win.
func (f *fakeHost) prepend(r ...reply) { f.replies = append(r, f.replies...) }

const nodeUnit = "[Service]\nExecStart=/usr/local/bin/k3s server\n"

// nuc9i5Host fakes nuc9i5 as it is today: a k3s server, running, whose config.yaml
// carries root-dir=/home/k3s/kubelet, with /var/lib/kubelet a symlink to it.
func nuc9i5Host() *fakeHost {
	return &fakeHost{replies: []reply{
		{match: "systemctl cat k3s.service", out: "present"},
		{match: "systemctl is-active k3s.service", out: "active"},
		{match: "cat /etc/rancher/k3s/config.yaml", out: nuc9i5ConfigYAML},
		{match: "cat /etc/systemd/system/k3s.service", out: nodeUnit},
		{match: "grep -rls", out: "/etc/rancher/k3s/config.yaml"},
		{match: "echo populated-dir", out: "symlink"},
		{match: "readlink /var/lib/kubelet", out: "/home/k3s/kubelet"},
		{match: "etcd-snapshot save", out: "saved /home/k3s/server/db/snapshots/devx-pre-relocate-kubelet-nuc9i5-1763632800"},
		{match: "date -u", out: "2026-11-20T10:00:00Z"},
		{match: "findmnt -n -o PROPAGATION", out: "shared"},
		{match: "findmnt /var/lib/kubelet", out: "TARGET            SOURCE                       FSTYPE OPTIONS\n/var/lib/kubelet /dev/mapper/fedora-home[/k3s/kubelet] ext4   rw\nbind mount OK: /var/lib/kubelet is /home/k3s/kubelet"},
		{match: "df -B1", out: "479670088000"},
	}}
}

func controlHost() *fakeHost {
	members := "nuc9 True\nnuc10 True\nnuc9i5 True\n"
	return &fakeHost{replies: []reply{
		{match: "get node nuc9i5 --no-headers", out: "nuc9i5 True <none> <none>"},
		// the real class: a folder per volume, reclaimPolicy Delete
		{match: "get storageclass nfs", out: "${pvc.metadata.namespace}/${pvc.metadata.name}/${pv.metadata.name}|"},
		{match: "get namespace devx-kubelet-check", out: ""},
		{match: "get nodes -l node-role.kubernetes.io/control-plane", out: members},
		{match: "get nodes -l node-role.kubernetes.io/etcd", out: members},
		{match: "/readyz/etcd", out: "ok"},
		{match: "get pods -A --field-selector", out: "default web-1 ReplicaSet\nkube-system csi-nfs-node-abc DaemonSet\nmedia jellyfin-0 StatefulSet\n"},
		{match: "get pv --no-headers", out: "local-path media media-config nuc9i5\nnfs media media-data <none>\nlocal-path x y nuc10\n"},
		{match: "jsonpath='{.status.conditions", out: "True 2026-11-20T10:00:42Z"},
		{match: "get pods -A -l app=csi-nfs-node", out: "kube-system csi-nfs-node-abc True"},
		{match: "get csinode nuc9i5", out: "nfs.csi.k8s.io"},
		{match: "kubectl logs", out: "devx-kubelet-check-ok"},
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
		Apply: apply, Control: ctl.run, ControlHost: "nuc9",
		DrainTimeout: 5 * time.Minute, ReadyTimeout: 50 * time.Millisecond, PollInterval: time.Millisecond,
		Out: out, Command: "devx cluster relocate-kubelet --host nuc9i5",
	}
}

// Read-only commands a dry run (or a refusal) may issue.
var readOnlyPrefixes = []string{"systemctl cat ", "systemctl is-active ", "cat /etc/", "grep -rls", "if mountpoint -q", "readlink ", "k3s kubectl get "}

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

func planFor(t *testing.T, role string, node, ctl *fakeHost) *RelocationPlan {
	t.Helper()
	plan, err := relocateProvider(role, node).PlanKubeletRelocation(context.Background(), relocateOpts(ctl, false, &bytes.Buffer{}))
	if err != nil {
		t.Fatalf("plan: %v", err)
	}
	return plan
}

const fullPlan = "cordon,drain,snapshot,gate,stop,killall,unmount,config,bindmount,stamp,start,ready,propagation,csipod,csinode,nfscheck,uncordon"

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

	plan := planFor(t, "server", nuc9i5Host(), controlHost())
	if got := stepIDs(plan); got != fullPlan {
		t.Errorf("steps = %s\nwant    %s", got, fullPlan)
	}
	text := out.String()
	for _, want := range []string{
		"k3s kubectl cordon nuc9i5",
		"k3s kubectl drain nuc9i5 --ignore-daemonsets --delete-emptydir-data --timeout=300s",
		"k3s etcd-snapshot save --name devx-pre-relocate-kubelet",
		"/home/k3s/server/db/snapshots/",
		"/readyz/etcd",
		"systemctl stop k3s.service",
		"systemctl start k3s.service",
		"k3s kubectl uncordon nuc9i5",
		"enable --now var-lib-kubelet.mount",
		"findmnt -n -o PROPAGATION /var/lib/kubelet",
		"app=csi-nfs-node",
		"nfs.csi.k8s.io",
		"devx-kubelet-check",
		"findmnt /var/lib/kubelet",
		"capacity.ephemeral-storage",
		// the drain's effect
		"The drain would evict 2 pod(s): default/web-1, media/jellyfin-0",
		"DaemonSet pods that stay",
		"kube-system/csi-nfs-node-abc",
		"WARNING: these local-path claims are pinned to nuc9i5, so their pods stay Pending while it is down: media/media-config",
		// the config diff
		"Change to /etc/rancher/k3s/config.yaml:",
		"- kubelet-arg:",
		"- root-dir=/home/k3s/kubelet",
		"does not prove every member is in sync",
		"Dry run: only read-only checks were made. Nothing was changed.",
		"--apply",
	} {
		if !strings.Contains(text, want) {
			t.Errorf("dry-run output missing %q", want)
		}
	}
	if strings.Contains(text, "- data-dir") {
		t.Errorf("the diff must show only the root-dir entry:\n%s", text)
	}
	// kubectl runs on another control-plane node; node commands on the node.
	for _, s := range plan.Steps {
		switch s.ID {
		case stepCordon, stepDrain, stepGate, stepReady, stepCSIPod, stepCSINode, stepNFSCheck, stepUncordon:
			if !s.OnControl {
				t.Errorf("%s must run on the control node", s.ID)
			}
		default:
			if s.OnControl {
				t.Errorf("%s must run on the node itself", s.ID)
			}
		}
		shellSafe(t, s.Cmd)
		for _, c := range s.Cmds {
			c, _, _ = strings.Cut(c, "   (") // display-only note after the command
			if !strings.HasPrefix(c, "(") {
				shellSafe(t, c)
			}
		}
	}
	// The config edit removes only root-dir, and keeps mode and owner (I2).
	for _, s := range plan.Steps {
		if s.ID != stepConfig {
			continue
		}
		newCfg := decodeWrites(t, s.Cmd)["/etc/rancher/k3s/config.yaml.devx-new"]
		if newCfg == "" || strings.Contains(newCfg, "root-dir") || decodeMap(t, newCfg)["data-dir"] != "/home/k3s" {
			t.Errorf("bad config rewrite:\n%s", newCfg)
		}
		assertOrdered(t, s.Cmd,
			"cp -p /etc/rancher/k3s/config.yaml /etc/rancher/k3s/config.yaml.pre-relocate-kubelet",
			"base64 -d > /etc/rancher/k3s/config.yaml.devx-new",
			"chmod --reference=/etc/rancher/k3s/config.yaml /etc/rancher/k3s/config.yaml.devx-new",
			"chown --reference=/etc/rancher/k3s/config.yaml /etc/rancher/k3s/config.yaml.devx-new",
			"mv /etc/rancher/k3s/config.yaml.devx-new /etc/rancher/k3s/config.yaml")
	}
}

func assertOrdered(t *testing.T, s string, parts ...string) {
	t.Helper()
	last := -1
	for _, p := range parts {
		i := strings.Index(s, p)
		if i < 0 {
			t.Errorf("missing %q in:\n%s", p, s)
			return
		}
		if i <= last {
			t.Errorf("%q is out of order in:\n%s", p, s)
		}
		last = i
	}
}

func TestRelocate_PlanIncludesExecStartEditWhenPresent(t *testing.T) {
	node := nuc9i5Host()
	node.prepend(
		reply{match: "cat /etc/systemd/system/k3s.service", out: k3sServerUnit},
		reply{match: "grep -rls", out: "/etc/rancher/k3s/config.yaml\n/etc/systemd/system/k3s.service"},
	)
	plan := planFor(t, "server", node, controlHost())
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
	assertOrdered(t, cmd,
		"cp -p /etc/systemd/system/k3s.service /etc/systemd/system/k3s.service.pre-relocate-kubelet",
		"chmod --reference=/etc/systemd/system/k3s.service",
		"chown --reference=/etc/systemd/system/k3s.service",
		"mv /etc/systemd/system/k3s.service.devx-new /etc/systemd/system/k3s.service")
	if plan.UnitDiff == "" {
		t.Error("the dry run must show the unit change too")
	}
}

func TestRelocate_InspectionIgnoresItsOwnLeftovers(t *testing.T) {
	// A config.yaml.devx-new left by an interrupted run (or the backup) must not make
	// inspection refuse: the scan excludes both.
	node := nuc9i5Host()
	planFor(t, "server", node, controlHost())
	var scan string
	for _, c := range node.calls {
		if strings.HasPrefix(c, "grep -rls") {
			scan = c
		}
	}
	for _, want := range []string{"--exclude='*.devx-new'", "--exclude='*.pre-relocate-kubelet'"} {
		if !strings.Contains(scan, want) {
			t.Errorf("root-dir scan must carry %s: %s", want, scan)
		}
	}
}

func TestRelocate_ResumesFromSymlinkAfterTheEdit(t *testing.T) {
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

// C2: a failure inside the bind-mount step leaves an empty /var/lib/kubelet (the
// symlink is already gone) with root-dir already removed. A re-run must finish.
func TestRelocate_ResumesFromEmptyDirAfterAFailedMountStep(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	node.prepend(
		reply{match: "cat /etc/rancher/k3s/config.yaml", out: "data-dir: /home/k3s\n"},
		reply{match: "grep -rls", out: ""},
		reply{match: "echo populated-dir", out: "empty-dir"},
		reply{match: "readlink /var/lib/kubelet", out: ""},
		reply{match: "systemctl is-active k3s.service", out: "inactive"}, // the earlier run stopped it
		reply{match: "get node nuc9i5 --no-headers", out: "nuc9i5 False true cordoned"},
	)
	var out bytes.Buffer
	opts := relocateOpts(ctl, true, &out)
	opts.ReadyTimeout = time.Second
	if err := relocateProvider("server", node).RelocateKubelet(context.Background(), opts); err != nil {
		t.Fatalf("re-run from an empty directory must complete: %v\n%s", err, out.String())
	}
	if !node.ran("systemctl enable --now var-lib-kubelet.mount") || !node.ran("systemctl start k3s.service") {
		t.Errorf("must finish the mount and start k3s:\n%s", strings.Join(node.calls, "\n"))
	}
	if node.ran("systemctl stop") || ctl.ran("drain") {
		t.Error("the node is already down and drained; it must not be drained or stopped again")
	}
	if !ctl.ran("k3s kubectl uncordon nuc9i5") {
		t.Error("must uncordon at the end")
	}
	if !strings.Contains(out.String(), "empty directory") {
		t.Errorf("the plan should say what state it found:\n%s", out.String())
	}
}

// downAndCordoned fakes the state a failure at `systemctl start` (or Ctrl-C, or
// the timeout) leaves: bind mount in place, root-dir gone, k3s down, node cordoned.
func downAndCordoned() (node, ctl *fakeHost) {
	node, ctl = nuc9i5Host(), controlHost()
	node.prepend(
		reply{match: "cat /etc/rancher/k3s/config.yaml", out: "data-dir: /home/k3s\n"},
		reply{match: "grep -rls", out: ""},
		reply{match: "echo populated-dir", out: "bind"},
		reply{match: "readlink /var/lib/kubelet", out: ""},
		reply{match: "systemctl is-active k3s.service", out: "inactive"},
	)
	ctl.prepend(reply{match: "get node nuc9i5 --no-headers", out: "nuc9i5 False true cordoned"})
	return node, ctl
}

// C1: the bind mount is in place and root-dir is gone, but k3s is down and the node
// is cordoned. Re-running must finish the job rather than print "nothing to do".
func TestRelocate_FinishesWhenMountedButK3sIsDownAndCordoned(t *testing.T) {
	node, ctl := downAndCordoned()
	var out bytes.Buffer
	opts := relocateOpts(ctl, true, &out)
	opts.ReadyTimeout = time.Second
	if err := relocateProvider("server", node).RelocateKubelet(context.Background(), opts); err != nil {
		t.Fatalf("must finish: %v\n%s", err, out.String())
	}
	n2, c2 := downAndCordoned()
	if got, want := stepIDs(planFor(t, "server", n2, c2)), "stamp,start,ready,propagation,csipod,csinode,nfscheck,uncordon"; got != want {
		t.Errorf("steps = %s, want %s", got, want)
	}
	if !node.ran("systemctl start k3s.service") || !ctl.ran("kubectl uncordon nuc9i5") {
		t.Errorf("must start k3s and uncordon:\nnode:\n%s\ncontrol:\n%s", strings.Join(node.calls, "\n"), strings.Join(ctl.calls, "\n"))
	}
	// Nothing else is repeated.
	if node.ran("systemctl stop") || node.ran("base64 -d") || node.ran("etcd-snapshot") || ctl.ran("kubectl drain") || ctl.ran("kubectl cordon") {
		t.Error("only start, Ready, the checks and the uncordon may run")
	}
	if strings.Contains(out.String(), "Nothing to do") {
		t.Errorf("a down node is not 'nothing to do':\n%s", out.String())
	}
}

// The same re-run, if it fails again, keeps the node cordoned and says so.
func TestRelocate_FinishingRunThatFailsAgainStaysCordoned(t *testing.T) {
	node, ctl := downAndCordoned()
	node.prepend(reply{match: "systemctl start k3s.service", err: errors.New("Job for k3s.service failed")})
	_, msg := applyErr(t, node, ctl, 0)
	if ctl.ran("kubectl uncordon") || !strings.Contains(msg, "CORDONED") || !strings.Contains(msg, "STOPPED (it was already down") {
		t.Errorf("must stay cordoned and say the unit is down:\n%s", msg)
	}
	if strings.Contains(msg, "not mounted yet") {
		t.Errorf("the bind mount is in place:\n%s", msg)
	}
}

func TestRelocate_FinishesWhenRunningButStillCordoned(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	node.prepend(
		reply{match: "cat /etc/rancher/k3s/config.yaml", out: "data-dir: /home/k3s\n"},
		reply{match: "grep -rls", out: ""},
		reply{match: "echo populated-dir", out: "bind"},
	)
	ctl.prepend(reply{match: "get node nuc9i5 --no-headers", out: "nuc9i5 True true cordoned"})
	plan := planFor(t, "server", node, ctl)
	if got := stepIDs(plan); got != "ready,propagation,csipod,csinode,nfscheck,uncordon" {
		t.Errorf("a running, Ready but cordoned node needs the checks and the uncordon only; got %s", got)
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
	cleanConfig := reply{match: "cat /etc/rancher/k3s/config.yaml", out: "data-dir: /home/k3s\n"}
	noHits := reply{match: "grep -rls", out: ""}
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
			name: "already relocated: bind mount of the backing dir, k3s running, Ready, schedulable",
			mutate: func(node, _ *fakeHost) {
				node.prepend(cleanConfig, noHits, reply{match: "echo populated-dir", out: "bind"}, reply{match: "readlink /var/lib/kubelet", out: ""})
			},
			want: ErrKubeletAlreadyRelocated, mention: "already",
		},
		{
			name: "/var/lib/kubelet is some other mount, not the bind of the backing dir",
			mutate: func(node, _ *fakeHost) {
				node.prepend(cleanConfig, noHits, reply{match: "echo populated-dir", out: "other-mount"})
			},
			want: ErrKubeletNotAtDataDir, mention: "not a bind mount of /home/k3s/kubelet",
		},
		{
			// Live fact for nuc9i5: /var/lib/kubelet is a symlink to /home/k3s/kubelet. A
			// populated REAL directory with root-dir still set must be refused at plan
			// time, before any cordon, drain, stop or edit.
			name: "populated real directory while root-dir is still set",
			mutate: func(node, _ *fakeHost) {
				node.prepend(reply{match: "echo populated-dir", out: "populated-dir"}, reply{match: "readlink /var/lib/kubelet", out: ""})
			},
			want: ErrKubeletNotAtDataDir, mention: "real directory",
		},
		{
			name: "some other mount while root-dir is still set",
			mutate: func(node, _ *fakeHost) {
				node.prepend(reply{match: "echo populated-dir", out: "other-mount"})
			},
			want: ErrKubeletNotAtDataDir, mention: "not a bind mount",
		},
		{
			name: "symlink elsewhere while root-dir is still set",
			mutate: func(node, _ *fakeHost) {
				node.prepend(reply{match: "readlink /var/lib/kubelet", out: "/mnt/other"})
			},
			want: ErrKubeletNotAtDataDir, mention: "/mnt/other",
		},
		{
			name: "NFS class would delete a shared folder (no ${pv.metadata.name} in subDir, onDelete not retain)",
			mutate: func(_, ctl *fakeHost) {
				ctl.prepend(reply{match: "get storageclass nfs", out: "shared/data|delete"})
			},
			want: ErrNFSCheckUnsafe, mention: "shared with real data",
		},
		{
			name: "NFS class has no subDir at all",
			mutate: func(_, ctl *fakeHost) {
				ctl.prepend(reply{match: "get storageclass nfs", out: "|"})
			},
			want: ErrNFSCheckUnsafe,
		},
		{
			name: "NFS class cannot be read",
			mutate: func(_, ctl *fakeHost) {
				ctl.prepend(reply{match: "get storageclass nfs", err: errors.New(`storageclasses.storage.k8s.io "nfs" not found`)})
			},
			want: ErrNFSCheckUnsafe, mention: "cannot read storage class",
		},
		{
			name: "a devx-kubelet-check namespace that is not ours",
			mutate: func(_, ctl *fakeHost) {
				ctl.prepend(reply{match: "get namespace devx-kubelet-check", out: "devx-kubelet-check <none>"})
			},
			want: ErrNFSCheckUnsafe, mention: "not created by this command",
		},
		{
			name: "kubelet is not at dataDir/kubelet (a populated default directory)",
			mutate: func(node, _ *fakeHost) {
				node.prepend(cleanConfig, noHits, reply{match: "echo populated-dir", out: "populated-dir"}, reply{match: "readlink /var/lib/kubelet", out: ""})
			},
			want: ErrKubeletNotAtDataDir, mention: "/home/k3s/kubelet",
		},
		{
			name: "symlink to somewhere else",
			mutate: func(node, _ *fakeHost) {
				node.prepend(cleanConfig, noHits, reply{match: "readlink /var/lib/kubelet", out: "/mnt/other"})
			},
			want: ErrKubeletNotAtDataDir, mention: "/mnt/other",
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
			name: "root-dir in a shape the edit will not touch (multi-line flow list)",
			mutate: func(node, _ *fakeHost) {
				node.prepend(reply{match: "cat /etc/rancher/k3s/config.yaml", out: "data-dir: /home/k3s\nkubelet-arg: [\n  max-pods=150,\n  root-dir=/home/k3s/kubelet\n]\n"})
			},
			want: ErrRootDirUnsupported, mention: "by hand",
		},
		{
			name: "a control-plane node found by label is not Ready",
			mutate: func(_, ctl *fakeHost) {
				ctl.prepend(reply{match: "get nodes -l node-role.kubernetes.io/control-plane", out: "nuc9 True\nnuc10 False\nnuc9i5 True\n"})
			},
			want: ErrQuorumRisk, mention: "nuc10",
		},
		{
			name: "an etcd node the devx config does not know is not Ready",
			mutate: func(_, ctl *fakeHost) {
				ctl.prepend(reply{match: "get nodes -l node-role.kubernetes.io/etcd", out: "nuc9 True\nnuc10 True\nnuc9i5 True\nghost-cp Unknown\n"})
			},
			want: ErrQuorumRisk, mention: "ghost-cp",
		},
		{
			name: "two control-plane nodes: stopping one leaves no majority",
			mutate: func(_, ctl *fakeHost) {
				two := "nuc9 True\nnuc9i5 True\n"
				ctl.prepend(reply{match: "get nodes -l node-role.kubernetes.io/control-plane", out: two}, reply{match: "get nodes -l node-role.kubernetes.io/etcd", out: two})
			},
			want: ErrQuorumRisk, mention: "majority",
		},
		{
			name: "etcd does not report healthy",
			mutate: func(_, ctl *fakeHost) {
				ctl.prepend(reply{match: "/readyz/etcd", out: "[-]etcd failed: reason withheld"})
			},
			want: ErrEtcdUnhealthy,
		},
		{
			name: "etcd health cannot be read",
			mutate: func(_, ctl *fakeHost) {
				ctl.prepend(reply{match: "/readyz/etcd", err: errors.New("connection refused")})
			},
			want: ErrEtcdUnhealthy, mention: "connection refused",
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
	ctl.prepend(reply{match: "get node nuc9i5 --no-headers", err: errors.New(`Error from server (NotFound): nodes "nuc9i5" not found`)})
	err := relocateProvider("server", node).RelocateKubelet(context.Background(), relocateOpts(ctl, true, &bytes.Buffer{}))
	if err == nil || !strings.Contains(err.Error(), "not in the cluster") {
		t.Errorf("err = %v", err)
	}
}

func TestRelocate_AgentIgnoresQuorumAndEtcd(t *testing.T) {
	node := nuc9i5Host()
	node.prepend(
		reply{match: "systemctl cat k3s-agent.service", out: "present"},
		reply{match: "systemctl is-active k3s-agent.service", out: "active"},
		reply{match: "cat /etc/systemd/system/k3s-agent.service", out: nodeUnit},
	)
	ctl := controlHost()
	ctl.prepend(
		reply{match: "get nodes -l node-role.kubernetes.io/control-plane", out: "nuc9 False\n"},
		reply{match: "/readyz/etcd", out: "not ok"},
	)
	plan := planFor(t, "agent", node, ctl)
	if plan.Unit != "k3s-agent.service" {
		t.Errorf("unit = %s", plan.Unit)
	}
	for _, s := range plan.Steps {
		if s.ID == stepGate || s.ID == stepSnapshot {
			t.Errorf("an agent does not touch etcd, but the plan has %s", s.ID)
		}
	}
	if ctl.ran("/readyz/etcd") {
		t.Error("an agent must not be gated on etcd")
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
	order := []string{"etcd-snapshot save", "systemctl stop k3s.service", "k3s-killall.sh", "umount -l", "config.yaml.pre-relocate-kubelet", "enable --now var-lib-kubelet.mount", "date -u", "systemctl start k3s.service", "findmnt -n -o PROPAGATION"}
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
	// Control side: cordon, drain, the re-check before the stop, the NFS check, and
	// only then the uncordon.
	idx := func(s string) int { return ctl.index(s) }
	cordon, drain, uncordon := idx("kubectl cordon nuc9i5"), idx("kubectl drain nuc9i5"), idx("kubectl uncordon nuc9i5")
	apply, logs := idx("kubectl apply -f -"), idx("kubectl logs")
	if !(0 <= cordon && cordon < drain && drain < apply && apply < logs && logs < uncordon) {
		t.Errorf("control order wrong: cordon=%d drain=%d apply=%d logs=%d uncordon=%d\n%s", cordon, drain, apply, logs, uncordon, strings.Join(ctl.calls, "\n"))
	}
	// The etcd check runs at plan time and again before the stop.
	if !ctl.ran("kubectl annotate node nuc9i5 devx-kubelet-relocate=cordoned --overwrite") || !ctl.ran("kubectl annotate node nuc9i5 devx-kubelet-relocate-") {
		t.Error("the cordon must be marked, and the mark removed with the uncordon")
	}
	if n := ctl.count("/readyz/etcd"); n != 2 {
		t.Errorf("etcd health should be checked twice (plan, then right before the stop); got %d", n)
	}
	// The throwaway check objects are removed first and last.
	if n := ctl.count("delete namespace devx-kubelet-check"); n != 2 {
		t.Errorf("the check namespace must be cleaned before and after; got %d deletes", n)
	}
	if ctl.index("delete pod kubelet-check") < 0 || ctl.index("delete pvc kubelet-check-pvc") < 0 {
		t.Error("the check pod and its PVC must be deleted")
	}
	// The check pod is pinned to the node and uses the nfs class.
	manifest := decodeApplied(t, ctl)
	for _, want := range []string{"nodeName: nuc9i5", "storageClassName: nfs", "name: devx-kubelet-check", "claimName: kubelet-check-pvc", "devx-kubelet-check-ok"} {
		if !strings.Contains(manifest, want) {
			t.Errorf("check manifest missing %q:\n%s", want, manifest)
		}
	}
	for _, want := range []string{"etcd snapshot", "devx-pre-relocate-kubelet-nuc9i5", "bind mount OK", "ephemeral-storage OK"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("output missing %q:\n%s", want, out.String())
		}
	}
}

func decodeApplied(t *testing.T, ctl *fakeHost) string {
	t.Helper()
	re := regexp.MustCompile(`echo ([A-Za-z0-9+/=]+) \| base64 -d \| k3s kubectl apply -f -`)
	for _, c := range ctl.calls {
		if m := re.FindStringSubmatch(c); m != nil {
			b, err := base64.StdEncoding.DecodeString(m[1])
			if err != nil {
				t.Fatal(err)
			}
			return string(b)
		}
	}
	t.Fatal("nothing was applied")
	return ""
}

// assertSudoShellOK checks a command the way it travels: remote.Runner.RunSudo sends
// `sudo sh -c %q`, so the login shell first expands the double-quoted string. The
// command must come out of that unchanged, and then parse as shell.
func assertSudoShellOK(t *testing.T, cmd string) {
	t.Helper()
	out, err := exec.Command("sh", "-c", "printf %s "+strconv.Quote(cmd)).Output()
	if err != nil {
		t.Errorf("outer shell rejected the command: %v\n%s", err, cmd)
		return
	}
	if string(out) != cmd {
		t.Errorf("the login shell changes the command on the way to sudo.\nsent: %s\ngot:  %s", cmd, out)
		return
	}
	if msg, err := exec.Command("sh", "-n", "-c", cmd).CombinedOutput(); err != nil {
		t.Errorf("not valid shell: %v\n%s\n%s", err, msg, cmd)
	}
}

// Every command a full run sends, node side and control side, must survive the
// `sudo sh -c %q` wrapping and parse as shell (unquoted parentheses in a
// custom-columns spec, for one, would not).
func TestRelocate_EveryCommandSurvivesTheSudoShell(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	node.prepend(
		reply{match: "cat /etc/systemd/system/k3s.service", out: k3sServerUnit},
		reply{match: "grep -rls", out: "/etc/rancher/k3s/config.yaml\n/etc/systemd/system/k3s.service"},
	)
	opts := relocateOpts(ctl, true, &bytes.Buffer{})
	opts.ReadyTimeout = time.Second
	if err := relocateProvider("server", node).RelocateKubelet(context.Background(), opts); err != nil {
		t.Fatal(err)
	}
	seen := 0
	for _, c := range append(append([]string{}, node.calls...), ctl.calls...) {
		assertSudoShellOK(t, c)
		seen++
	}
	if seen < 40 {
		t.Errorf("expected a full run's worth of commands, saw %d", seen)
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

func applyErr(t *testing.T, node, ctl *fakeHost, ready time.Duration) (*RelocationError, string) {
	t.Helper()
	var out bytes.Buffer
	opts := relocateOpts(ctl, true, &out)
	if ready > 0 {
		opts.ReadyTimeout = ready
	}
	err := relocateProvider("server", node).RelocateKubelet(context.Background(), opts)
	var rerr *RelocationError
	if !errors.As(err, &rerr) {
		t.Fatalf("want a RelocationError, got %v\n%s", err, out.String())
	}
	return rerr, err.Error()
}

func TestRelocate_FailureBeforeStopUncordonsAndTouchesNothing(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	ctl.prepend(reply{match: "drain nuc9i5", err: errors.New("Cannot evict pod: would violate the pod's disruption budget")})
	rerr, msg := applyErr(t, node, ctl, 0)
	if rerr.Step != 2 || !strings.Contains(msg, "disruption budget") {
		t.Errorf("step=%d err=%s", rerr.Step, msg)
	}
	if !ctl.ran("k3s kubectl uncordon nuc9i5") {
		t.Errorf("a failed drain must uncordon the node again; control calls:\n%s", strings.Join(ctl.calls, "\n"))
	}
	if node.ran("systemctl stop") || node.ran("base64 -d") {
		t.Errorf("nothing on the node may change before the drain succeeds:\n%s", strings.Join(node.calls, "\n"))
	}
	if !strings.Contains(msg, "never stopped") || !strings.Contains(msg, "uncordoned again") {
		t.Errorf("the error must say the node is untouched and uncordoned:\n%s", msg)
	}
}

func TestRelocate_SnapshotFailureStopsBeforeTheNodeIsTouched(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	node.prepend(reply{match: "etcd-snapshot save", err: errors.New("etcd: no space left on device")})
	_, msg := applyErr(t, node, ctl, 0)
	if node.ran("systemctl stop") {
		t.Error("without a snapshot the control-plane node must not be stopped")
	}
	if !ctl.ran("kubectl uncordon nuc9i5") || !strings.Contains(msg, "no space left") {
		t.Errorf("must uncordon and say why:\n%s", msg)
	}
}

// I1: the quorum check is repeated right before the stop. A node that went NotReady
// (or etcd that went unhealthy) after the plan was made must stop the run there.
func TestRelocate_QuorumIsRecheckedRightBeforeTheStop(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	ctl.prepend(
		reply{match: "/readyz/etcd", out: "ok", uses: 1}, // the plan-time check
		reply{match: "/readyz/etcd", out: "[-]etcd failed"},
	)
	rerr, msg := applyErr(t, node, ctl, 0)
	if !errors.Is(rerr, ErrEtcdUnhealthy) {
		t.Errorf("want ErrEtcdUnhealthy, got %v", rerr.Err)
	}
	if node.ran("systemctl stop") {
		t.Error("the node must not be stopped when the re-check fails")
	}
	if !ctl.ran("kubectl uncordon nuc9i5") || !strings.Contains(msg, "never stopped") {
		t.Errorf("must uncordon and report an untouched node:\n%s", msg)
	}
	// The same for a control-plane node that dropped out in the meantime.
	node, ctl = nuc9i5Host(), controlHost()
	ok := "nuc9 True\nnuc10 True\nnuc9i5 True\n"
	ctl.prepend(
		reply{match: "get nodes -l node-role.kubernetes.io/control-plane", out: ok, uses: 1},
		reply{match: "get nodes -l node-role.kubernetes.io/control-plane", out: "nuc9 True\nnuc10 False\nnuc9i5 True\n"},
	)
	rerr, _ = applyErr(t, node, ctl, 0)
	if !errors.Is(rerr, ErrQuorumRisk) || node.ran("systemctl stop") {
		t.Errorf("a node that went NotReady must stop the run before the stop: %v", rerr.Err)
	}
}

func TestRelocate_FailureAfterStopSaysWhatStateAndHowToRecover(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	node.prepend(reply{match: "enable --now var-lib-kubelet.mount", err: errors.New("Failed to enable unit")})
	_, msg := applyErr(t, node, ctl, 0)
	for _, want := range []string{
		"k3s.service is STOPPED",
		"config.yaml: root-dir already removed",
		"/etc/rancher/k3s/config.yaml.pre-relocate-kubelet",
		"may be an empty directory",
		"a re-run accepts an empty directory",
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
	if ctl.ran("kubectl uncordon") {
		t.Error("a node that is down must stay cordoned, loudly")
	}
}

// A failure in a resumed run must not claim the config is "not changed yet" when an
// earlier run changed it.
func TestRelocate_ResumedRunFailureDoesNotMisreportTheConfig(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	node.prepend(
		reply{match: "cat /etc/rancher/k3s/config.yaml", out: "data-dir: /home/k3s\n"},
		reply{match: "grep -rls", out: ""},
		reply{match: "enable --now var-lib-kubelet.mount", err: errors.New("Failed to enable unit")},
	)
	_, msg := applyErr(t, node, ctl, 0)
	if strings.Contains(msg, "not changed yet") {
		t.Errorf("an earlier run already removed root-dir:\n%s", msg)
	}
	if !strings.Contains(msg, "root-dir was already removed (by an earlier run)") {
		t.Errorf("should say an earlier run did it:\n%s", msg)
	}
}

func TestRelocate_NotReadyInTimeLeavesItCordonedWithRecovery(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	// A heartbeat older than the start stamp: the previous kubelet's, not the new one's.
	ctl.prepend(reply{match: "jsonpath='{.status.conditions", out: "True 2026-11-20T09:59:00Z"})
	_, msg := applyErr(t, node, ctl, 20*time.Millisecond)
	for _, want := range []string{"k3s.service is STARTED", "CORDONED", "journalctl -u k3s.service", "k3s kubectl uncordon nuc9i5", "bind mount of /home/k3s/kubelet", "re-run devx cluster relocate-kubelet --host nuc9i5 --apply"} {
		if !strings.Contains(msg, want) {
			t.Errorf("missing %q:\n%s", want, msg)
		}
	}
	if ctl.ran("k3s kubectl uncordon") {
		t.Error("must not uncordon a node that never became Ready")
	}
}

func TestRelocate_StopFailureReportsUnknownUnitState(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	node.prepend(reply{match: "systemctl stop k3s.service", err: errors.New("ssh: connection lost")})
	_, msg := applyErr(t, node, ctl, 0)
	for _, want := range []string{"the stop did not complete", "CORDONED"} {
		if !strings.Contains(msg, want) {
			t.Errorf("missing %q:\n%s", want, msg)
		}
	}
}

// I3: every check before the uncordon must fail the run, leave the node cordoned,
// and say how to recover.
func TestRelocate_VerificationFailuresKeepTheNodeCordoned(t *testing.T) {
	cases := []struct {
		name    string
		node    []reply
		ctl     []reply
		mention string
	}{
		{"mount propagation is private", []reply{{match: "findmnt -n -o PROPAGATION", out: "private"}}, nil, `"private", not "shared"`},
		{"mount propagation cannot be read", []reply{{match: "findmnt -n -o PROPAGATION", err: errors.New("findmnt: not a mountpoint")}}, nil, "not a mountpoint"},
		{"the NFS CSI node pod is not Ready", nil, []reply{{match: "get pods -A -l app=csi-nfs-node", out: "kube-system csi-nfs-node-abc False"}}, "timed out"},
		{"the NFS CSI node pod does not exist", nil, []reply{{match: "get pods -A -l app=csi-nfs-node", out: ""}}, "timed out"},
		{"nfs.csi.k8s.io is not in the CSINode", nil, []reply{{match: "get csinode nuc9i5", out: "other.csi.example"}}, "timed out"},
		{"the check pod does not finish", nil, []reply{{match: "kubectl wait", err: errors.New("timed out waiting for the condition")}}, "did not finish"},
		{"the check pod cannot create its PVC", nil, []reply{{match: "kubectl apply -f -", err: errors.New("storageclass nfs not found")}}, "storageclass nfs not found"},
		{"the check pod reads back the wrong thing", nil, []reply{{match: "kubectl logs", out: "something else"}}, "did not read back"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			node, ctl := nuc9i5Host(), controlHost()
			node.prepend(tc.node...)
			ctl.prepend(tc.ctl...)
			_, msg := applyErr(t, node, ctl, 30*time.Millisecond)
			if !strings.Contains(msg, tc.mention) {
				t.Errorf("missing %q:\n%s", tc.mention, msg)
			}
			if ctl.ran("kubectl uncordon") {
				t.Error("a failed check must leave the node cordoned")
			}
			for _, want := range []string{"CORDONED", "k3s.service is STARTED", "re-run devx cluster relocate-kubelet --host nuc9i5 --apply"} {
				if !strings.Contains(msg, want) {
					t.Errorf("recovery text missing %q:\n%s", want, msg)
				}
			}
		})
	}
}

func TestRelocate_NFSCheckObjectsAreRemovedEvenWhenTheCheckFails(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	ctl.prepend(reply{match: "kubectl wait", err: errors.New("timed out waiting for the condition")})
	applyErr(t, node, ctl, 0)
	if n := ctl.count("delete namespace devx-kubelet-check"); n != 2 {
		t.Errorf("the namespace must be deleted before and after, even on failure; got %d", n)
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

func TestLineDiff(t *testing.T) {
	a := "a: 1\nkubelet-arg:\n  - root-dir=/x\nb: 2\n"
	b := "a: 1\nb: 2\n"
	if got := lineDiff(a, b); got != "- kubelet-arg:\n-   - root-dir=/x" {
		t.Errorf("diff = %q", got)
	}
	if got := lineDiff(a, a); got != "" {
		t.Errorf("no change must be an empty diff; got %q", got)
	}
}

// States /var/lib/kubelet may be in at plan time while root-dir is still set.
func TestRelocate_AcceptsTheExpectedStartingStates(t *testing.T) {
	for name, mount := range map[string]string{"symlink to the backing dir": "symlink", "empty directory": "empty-dir", "missing": "absent", "already the bind mount": "bind"} {
		t.Run(name, func(t *testing.T) {
			node := nuc9i5Host()
			node.prepend(reply{match: "echo populated-dir", out: mount})
			plan := planFor(t, "server", node, controlHost())
			if got := stepIDs(plan); got != fullPlan {
				t.Errorf("steps = %s", got)
			}
		})
	}
}

func TestRelocate_MissingKubeletDirWithRootDirGoneResumes(t *testing.T) {
	node := nuc9i5Host()
	node.prepend(
		reply{match: "cat /etc/rancher/k3s/config.yaml", out: "data-dir: /home/k3s\n"},
		reply{match: "grep -rls", out: ""},
		reply{match: "echo populated-dir", out: "absent"},
		reply{match: "readlink /var/lib/kubelet", out: ""},
	)
	plan := planFor(t, "server", node, controlHost())
	if !strings.Contains(plan.Situation, "does not exist yet") {
		t.Errorf("situation = %q", plan.Situation)
	}
}

// A refused plan runs nothing but reads, with the real-looking nuc9i5 state plus a
// populated directory: the point of refusing up front.
func TestRelocate_PopulatedDirIsRefusedBeforeAnythingChanges(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	node.prepend(reply{match: "echo populated-dir", out: "populated-dir"}, reply{match: "readlink /var/lib/kubelet", out: ""})
	var out bytes.Buffer
	err := relocateProvider("server", node).RelocateKubelet(context.Background(), relocateOpts(ctl, true, &out))
	if !errors.Is(err, ErrKubeletNotAtDataDir) {
		t.Fatalf("err = %v", err)
	}
	assertReadOnly(t, "node", node.calls)
	assertReadOnly(t, "control", ctl.calls)
	for _, c := range append(append([]string{}, node.calls...), ctl.calls...) {
		for _, bad := range []string{"cordon", "drain", "etcd-snapshot", "systemctl stop", "killall", "base64 -d"} {
			if strings.Contains(c, bad) {
				t.Errorf("a refusal must not run %q: %s", bad, c)
			}
		}
	}
}

func TestRelocate_NFSClassWithOnDeleteRetainPasses(t *testing.T) {
	ctl := controlHost()
	ctl.prepend(reply{match: "get storageclass nfs", out: "shared/data|retain"})
	planFor(t, "server", nuc9i5Host(), ctl)
	ctl = controlHost()
	ctl.prepend(reply{match: "get storageclass nfs", out: "shared/data|Retain"})
	planFor(t, "server", nuc9i5Host(), ctl)
}

// The guard is repeated when the check runs: a class changed after the plan was made
// stops the check, keeps the node cordoned, and creates nothing.
func TestRelocate_NFSGuardIsRecheckedBeforeTheCheckCreatesAnything(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	ctl.prepend(
		reply{match: "get storageclass nfs", out: "${pv.metadata.name}|", uses: 1},
		reply{match: "get storageclass nfs", out: "shared/data|delete"},
	)
	rerr, msg := applyErr(t, node, ctl, time.Second)
	if !errors.Is(rerr, ErrNFSCheckUnsafe) {
		t.Errorf("want ErrNFSCheckUnsafe, got %v", rerr.Err)
	}
	if ctl.ran("kubectl apply -f -") || ctl.ran("delete namespace") {
		t.Error("nothing may be created or deleted when the guard refuses")
	}
	if ctl.ran("kubectl uncordon") || !strings.Contains(msg, "CORDONED") {
		t.Errorf("the node stays cordoned:\n%s", msg)
	}
}

func TestRelocate_ALeftoverNamespaceOfOursIsCleanedUp(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	ctl.prepend(reply{match: "get namespace devx-kubelet-check", out: "devx-kubelet-check true"})
	var out bytes.Buffer
	opts := relocateOpts(ctl, true, &out)
	opts.ReadyTimeout = time.Second
	if err := relocateProvider("server", node).RelocateKubelet(context.Background(), opts); err != nil {
		t.Fatal(err)
	}
	if n := ctl.count("delete namespace devx-kubelet-check"); n != 2 {
		t.Errorf("our own leftover is removed first and the namespace again after; got %d deletes", n)
	}
	if !strings.Contains(decodeApplied(t, ctl), "devx-kubelet-check: \"true\"") {
		t.Error("the namespace must carry the label that marks it as ours")
	}
}

// The deferred cleanup runs even when the run is cancelled (Ctrl-C / SIGTERM cancel
// the context) and even when the first cleanup attempt fails.
func TestRelocate_CleanupRunsAfterCancellation(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	ctx, cancel := context.WithCancel(context.Background())
	ctl.ctxAware = true
	ctl.hook = func(cmd string) {
		if strings.Contains(cmd, "kubectl wait") {
			cancel() // the operator hits Ctrl-C while the check pod runs
		}
	}
	var out bytes.Buffer
	opts := relocateOpts(ctl, true, &out)
	opts.ReadyTimeout = time.Second
	err := relocateProvider("server", node).RelocateKubelet(ctx, opts)
	if err == nil {
		t.Fatal("expected the cancelled run to fail")
	}
	if n := ctl.count("delete namespace devx-kubelet-check"); n != 2 {
		t.Errorf("cleanup must still run on a fresh context after the cancel; got %d namespace deletes\n%s", n, strings.Join(ctl.calls, "\n"))
	}
	if strings.Contains(out.String(), "could not delete") {
		t.Errorf("the cleanup should have worked:\n%s", out.String())
	}
}

func TestRelocate_CleanupFailureSaysExactlyWhatToRemove(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	ctl.prepend(reply{match: "delete namespace", err: errors.New("the server is down")})
	var out bytes.Buffer
	opts := relocateOpts(ctl, true, &out)
	opts.ReadyTimeout = time.Second
	if err := relocateProvider("server", node).RelocateKubelet(context.Background(), opts); err == nil {
		t.Fatal("a failed pre-cleanup fails the check")
	}
	// The deferred cleanup was registered before the first cleanup attempt, so it ran
	// (and failed too) and the exact commands were printed.
	if n := ctl.count("delete namespace devx-kubelet-check"); n != 2 {
		t.Errorf("both the first attempt and the deferred cleanup must run; got %d", n)
	}
	for _, want := range []string{"Remove them by hand on nuc9", "k3s kubectl delete namespace devx-kubelet-check", "k3s kubectl delete pvc kubelet-check-pvc"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("output missing %q:\n%s", want, out.String())
		}
	}
}

// --- who cordoned the node ---

func TestRelocate_NodeCordonedByAnotherReasonIsLeftCordoned(t *testing.T) {
	// Full move, but the node was cordoned by someone else before we started.
	node, ctl := nuc9i5Host(), controlHost()
	ctl.prepend(reply{match: "get node nuc9i5 --no-headers", out: "nuc9i5 True true <none>"})
	plan := planFor(t, "server", nuc9i5Host(), func() *fakeHost {
		c := controlHost()
		c.prepend(reply{match: "get node nuc9i5 --no-headers", out: "nuc9i5 True true <none>"})
		return c
	}())
	for _, s := range plan.Steps {
		if s.ID == stepCordon || s.ID == stepUncordon {
			t.Errorf("a cordon this command did not make is neither redone nor undone, but the plan has %s", s.ID)
		}
	}
	var out bytes.Buffer
	opts := relocateOpts(ctl, true, &out)
	opts.ReadyTimeout = time.Second
	if err := relocateProvider("server", node).RelocateKubelet(context.Background(), opts); err != nil {
		t.Fatal(err)
	}
	if ctl.ran("kubectl cordon") || ctl.ran("kubectl uncordon") || ctl.ran("kubectl annotate") {
		t.Errorf("must not touch the cordon:\n%s", strings.Join(ctl.calls, "\n"))
	}
	if !strings.Contains(out.String(), "already cordoned") || !strings.Contains(out.String(), "still cordoned") {
		t.Errorf("must say it left the node cordoned:\n%s", out.String())
	}
}

func TestRelocate_FinishingARunLeavesAForeignCordonAlone(t *testing.T) {
	node, ctl := downAndCordoned()
	ctl.prepend(reply{match: "get node nuc9i5 --no-headers", out: "nuc9i5 False true <none>"}) // cordoned, no mark: not ours
	var out bytes.Buffer
	opts := relocateOpts(ctl, true, &out)
	opts.ReadyTimeout = time.Second
	if err := relocateProvider("server", node).RelocateKubelet(context.Background(), opts); err != nil {
		t.Fatal(err)
	}
	if !node.ran("systemctl start k3s.service") {
		t.Error("it still finishes the start")
	}
	if ctl.ran("kubectl uncordon") {
		t.Error("a cordon this command did not make must not be undone")
	}
	if !strings.Contains(out.String(), "still cordoned") {
		t.Errorf("must say so:\n%s", out.String())
	}
}

func TestRelocate_RunningNodeCordonedByAnotherReasonCountsAsDone(t *testing.T) {
	node := nuc9i5Host()
	node.prepend(
		reply{match: "cat /etc/rancher/k3s/config.yaml", out: "data-dir: /home/k3s\n"},
		reply{match: "grep -rls", out: ""},
		reply{match: "echo populated-dir", out: "bind"},
	)
	ctl := controlHost()
	ctl.prepend(reply{match: "get node nuc9i5 --no-headers", out: "nuc9i5 True true <none>"})
	_, err := relocateProvider("server", node).PlanKubeletRelocation(context.Background(), relocateOpts(ctl, false, &bytes.Buffer{}))
	if !errors.Is(err, ErrKubeletAlreadyRelocated) || !strings.Contains(err.Error(), "left that way") {
		t.Errorf("err = %v", err)
	}
}

func TestRelocate_FailureBeforeStopDoesNotUncordonAForeignCordon(t *testing.T) {
	node, ctl := nuc9i5Host(), controlHost()
	ctl.prepend(
		reply{match: "get node nuc9i5 --no-headers", out: "nuc9i5 True true <none>"},
		reply{match: "drain nuc9i5", err: errors.New("Cannot evict pod")},
	)
	_, msg := applyErr(t, node, ctl, 0)
	if ctl.ran("kubectl uncordon") {
		t.Error("must not uncordon a node someone else cordoned")
	}
	if !strings.Contains(msg, "cordoned before this run, by something else") {
		t.Errorf("must say so:\n%s", msg)
	}
}
