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
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/config"
	"github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/util"
)

// Refusals. Each is a state the command will not touch, wrapped with the detail.
var (
	// ErrRelocateNoDataDir: the node has no dataDir in the devx config.
	ErrRelocateNoDataDir = errors.New("node has no dataDir in the devx config")
	// ErrKubeletAlreadyRelocated: /var/lib/kubelet is the bind mount of
	// <dataDir>/kubelet, no root-dir argument remains, k3s is running and the node
	// is Ready and schedulable. Nothing to do.
	ErrKubeletAlreadyRelocated = errors.New("kubelet is already at /var/lib/kubelet")
	// ErrKubeletNotAtDataDir: the kubelet is not currently at <dataDir>/kubelet.
	ErrKubeletNotAtDataDir = errors.New("kubelet is not currently at <dataDir>/kubelet")
	// ErrRootDirUnsupported: a root-dir setting lives somewhere this command does
	// not edit (a drop-in), or in a shape it will not edit safely.
	ErrRootDirUnsupported = errors.New("root-dir is set somewhere devx does not edit")
	// ErrQuorumRisk: stopping this control-plane node would endanger etcd quorum.
	ErrQuorumRisk = errors.New("stopping this control-plane node is unsafe right now")
	// ErrNotNative: only native Linux nodes can be switched.
	ErrNotNative = errors.New("only native nodes can be switched")
)

const (
	k3sConfigPath = "/etc/rancher/k3s/config.yaml"
	// backupSuffix marks the copies made before a file is edited; tmpSuffix the
	// file a rewrite is staged in. Both are excluded from the root-dir scan so a
	// re-run is not confused by its own leftovers.
	backupSuffix = ".pre-relocate-kubelet"
	tmpSuffix    = ".devx-new"
	// snapshotName prefixes the etcd snapshot taken before a control-plane node stops.
	snapshotName = "devx-pre-relocate-kubelet"
)

// CommandRunner runs one command as root on a host and returns combined output.
type CommandRunner = func(ctx context.Context, command string) (string, error)

// ControlRunner returns a CommandRunner that runs commands as root on a
// control-plane node (ssh-sudo for native hosts, limactl-shell-sudo for Lima VMs),
// so kubectl can be driven from a node other than the one being changed.
func ControlRunner(node config.NodeConfig) CommandRunner {
	r := util.NewRunner(node)
	if node.GetKind() == "native" {
		return r.RunSudo
	}
	vm := node.GetVMName()
	return func(ctx context.Context, cmd string) (string, error) { return r.LimaShellSudo(ctx, vm, cmd) }
}

// RelocateOptions configures RelocateKubelet.
type RelocateOptions struct {
	// Apply executes the plan. False (the default) only inspects and prints it.
	Apply bool
	// Control runs kubectl as root on a control-plane node, and ControlHost names it.
	Control     CommandRunner
	ControlHost string
	// Timeouts. Zero values take the defaults.
	DrainTimeout time.Duration // default 5m
	ReadyTimeout time.Duration // default 5m
	PollInterval time.Duration // default 5s
	// Out receives the plan and progress. Default os.Stdout.
	Out io.Writer
	// Command is the command line to print in recovery hints.
	Command string
}

func (o *RelocateOptions) defaults() {
	if o.DrainTimeout == 0 {
		o.DrainTimeout = 5 * time.Minute
	}
	if o.ReadyTimeout == 0 {
		o.ReadyTimeout = 5 * time.Minute
	}
	if o.PollInterval == 0 {
		o.PollInterval = 5 * time.Second
	}
	if o.Out == nil {
		o.Out = os.Stdout
	}
	if o.Command == "" {
		o.Command = "devx cluster relocate-kubelet --host <host>"
	}
}

// Step identifiers, in plan order. They let a failure report say exactly how far
// the node got.
const (
	stepCordon      = "cordon"
	stepDrain       = "drain"
	stepSnapshot    = "snapshot"
	stepGate        = "gate"
	stepStop        = "stop"
	stepKillall     = "killall"
	stepUnmount     = "unmount"
	stepConfig      = "config"
	stepUnit        = "unit"
	stepBindMount   = "bindmount"
	stepStamp       = "stamp"
	stepStart       = "start"
	stepReady       = "ready"
	stepPropagation = "propagation"
	stepCSIPod      = "csipod"
	stepCSINode     = "csinode"
	stepNFSCheck    = "nfscheck"
	stepUncordon    = "uncordon"
)

// RelocationStep is one action of the plan. Cmd is the exact command run as root
// on the host named by OnControl; steps made of several commands list them in Cmds
// (display) and do their work in Run.
type RelocationStep struct {
	ID        string
	Desc      string
	Cmd       string
	Cmds      []string
	OnControl bool // run on the control-plane node; otherwise on the node itself
	// PollTimeout > 0 makes the step poll Cmd every interval until Done accepts the
	// output.
	PollTimeout time.Duration
	Done        func(out string) bool
	// Capture, when set, receives the step's output (used to timestamp the start).
	Capture func(out string)
	// Validate, when set, judges the output of a one-shot command.
	Validate func(out string) error
	// ShowOutput prints the command's output after it runs.
	ShowOutput bool
	// Run, when set, replaces Cmd.
	Run func(ctx context.Context) error
}

// RelocationPlan is what `relocate-kubelet` would do to a node.
type RelocationPlan struct {
	Host        string
	Role        string
	Unit        string
	DataDir     string
	Backing     string // <dataDir>/kubelet
	Found       []string
	ControlHost string
	Situation   string // one line on where the node is now
	Steps       []RelocationStep

	// What a dry run reports beyond the steps.
	Evict      []string // pods that would be evicted
	Stay       []string // DaemonSet pods that stay
	LocalPath  []string // local-path claims pinned to the node
	ConfigDiff string
	UnitDiff   string

	unitActive    bool // k3s was running when the plan was made
	configPlanned bool
	unitPlanned   bool
	mountPlanned  bool
	startPlanned  bool

	// Verify commands for the final check.
	verifyMount, verifyCapacity, verifyDisk string

	startedAt string
}

// mount states reported by mountStateCmd.
const (
	mountBind       = "bind"
	mountOther      = "other-mount"
	mountSymlink    = "symlink"
	mountPopulated  = "populated-dir"
	mountEmptyDir   = "empty-dir"
	mountAbsent     = "absent"
	propagationWant = "shared"
)

// mountStateCmd classifies /var/lib/kubelet in one read-only command: the bind
// mount of the backing directory (same device and inode), some other mount, a
// symlink, a populated or empty directory, or absent.
func mountStateCmd(backing string) string {
	p := kubeletStdPath
	return "if mountpoint -q " + p + "; then if [ " + p + " -ef " + backing + " ]; then echo " + mountBind + "; else echo " + mountOther + "; fi; " +
		"elif [ -L " + p + " ]; then echo " + mountSymlink + "; " +
		"elif [ -d " + p + " ]; then if find " + p + " -mindepth 1 -maxdepth 1 | grep -q .; then echo " + mountPopulated + "; else echo " + mountEmptyDir + "; fi; " +
		"else echo " + mountAbsent + "; fi"
}

// kubeletNodeState is what the read-only inspections found on the node; it decides
// whether the node can be switched and feeds the edits.
type kubeletNodeState struct {
	unitPresent bool
	unitActive  bool
	configYAML  string
	unitText    string
	rootDirHits []string
	mount       string
	symlinkTo   string
}

func (p *NativeProvider) inspectKubelet(ctx context.Context, unit, backing string) (kubeletNodeState, error) {
	var st kubeletNodeState
	fail := func(what string, err error) (kubeletNodeState, error) {
		return st, fmt.Errorf("[%s] %s: %w", p.spec.Host, what, err)
	}
	out, err := p.run(ctx, "systemctl cat "+unit+" >/dev/null 2>&1 && echo present || echo missing")
	if err != nil {
		return fail("checking "+unit, err)
	}
	st.unitPresent = strings.Contains(out, "present")
	if out, err = p.run(ctx, "systemctl is-active "+unit+" || true"); err != nil {
		return fail("checking whether "+unit+" is running", err)
	}
	st.unitActive = strings.TrimSpace(out) == "active"
	if st.configYAML, err = p.run(ctx, "cat "+k3sConfigPath+" 2>/dev/null || true"); err != nil {
		return fail("reading "+k3sConfigPath, err)
	}
	if st.unitText, err = p.run(ctx, "cat /etc/systemd/system/"+unit+" 2>/dev/null || true"); err != nil {
		return fail("reading "+unit, err)
	}
	hits, err := p.run(ctx, "grep -rls --exclude='*"+backupSuffix+"' --exclude='*"+tmpSuffix+"' root-dir /etc/rancher/k3s /etc/systemd/system/"+unit+" /etc/systemd/system/"+unit+".d 2>/dev/null || true")
	if err != nil {
		return fail("scanning for root-dir", err)
	}
	for _, l := range strings.Split(hits, "\n") {
		if l = strings.TrimSpace(l); l != "" {
			st.rootDirHits = append(st.rootDirHits, l)
		}
	}
	m, err := p.run(ctx, mountStateCmd(backing))
	if err != nil {
		return fail("checking "+kubeletStdPath, err)
	}
	st.mount = strings.TrimSpace(m)
	if st.symlinkTo, err = p.run(ctx, "readlink "+kubeletStdPath+" || true"); err != nil {
		return fail("reading "+kubeletStdPath, err)
	}
	st.symlinkTo = strings.TrimSpace(st.symlinkTo)
	return st, nil
}

// PlanKubeletRelocation inspects the node and the cluster (read-only) and returns
// the plan to move the kubelet from <dataDir>/kubelet to the standard
// /var/lib/kubelet bind mount, or to finish a move that stopped half way. It
// refuses, with a wrapped sentinel error, when the node should not be touched.
func (p *NativeProvider) PlanKubeletRelocation(ctx context.Context, o RelocateOptions) (*RelocationPlan, error) {
	o.defaults()
	if p.spec.Kind != "native" {
		return nil, fmt.Errorf("[%s] %w (kind is %q)", p.spec.Host, ErrNotNative, p.spec.Kind)
	}
	if p.spec.DataDir == "" {
		return nil, fmt.Errorf("[%s] %w: nothing to relocate", p.spec.Host, ErrRelocateNoDataDir)
	}
	if o.Control == nil {
		return nil, fmt.Errorf("[%s] no control-plane runner configured", p.spec.Host)
	}
	host := p.spec.Host
	unit := k3sUnitFor(p.spec.Role)
	want := kubeletBackingDir(p.spec.DataDir)
	st, err := p.inspectKubelet(ctx, unit, want)
	if err != nil {
		return nil, err
	}
	if !st.unitPresent {
		return nil, fmt.Errorf("[%s] %s is not installed on the host", host, unit)
	}

	// Where is root-dir set, and to what?
	cfgVals, err := rootDirValuesInConfig(st.configYAML)
	if err != nil {
		return nil, fmt.Errorf("[%s] %w", host, err)
	}
	found := append(append([]string{}, cfgVals...), rootDirValuesInUnit(st.unitText)...)
	handled := map[string]bool{k3sConfigPath: true, "/etc/systemd/system/" + unit: true}
	for _, f := range st.rootDirHits {
		if !handled[f] {
			return nil, fmt.Errorf("[%s] %w: %s mentions root-dir; remove it by hand, then re-run", host, ErrRootDirUnsupported, f)
		}
	}
	for _, v := range found {
		if !samePath(v, want) {
			return nil, fmt.Errorf("[%s] %w: root-dir is %q but dataDir implies %q; the node does not match the devx config", host, ErrKubeletNotAtDataDir, v, want)
		}
	}

	// Which state is the node in? finishOnly: the bind mount is in place and
	// root-dir is gone, so only start / Ready / checks / uncordon may remain.
	finishOnly := false
	situation := "kubelet at " + want + " (root-dir kubelet-arg)"
	if len(found) == 0 {
		switch st.mount {
		case mountBind:
			finishOnly = true
			situation = kubeletStdPath + " is already the bind mount of " + want // finishing an earlier run
		case mountSymlink:
			if st.symlinkTo == "" || !samePath(st.symlinkTo, want) {
				return nil, fmt.Errorf("[%s] %w: no root-dir argument remains and %s is a symlink to %q, not %q", host, ErrKubeletNotAtDataDir, kubeletStdPath, st.symlinkTo, want)
			}
			situation = "root-dir already removed; " + kubeletStdPath + " still symlinked to " + want + " (an earlier run was interrupted; resuming)"
		case mountEmptyDir:
			situation = "root-dir already removed; " + kubeletStdPath + " is an empty directory, not yet mounted (an earlier run was interrupted; resuming)"
		case mountOther:
			return nil, fmt.Errorf("[%s] %w: %s is a mount, but not a bind mount of %s", host, ErrKubeletNotAtDataDir, kubeletStdPath, want)
		default:
			return nil, fmt.Errorf("[%s] %w: no root-dir argument in %s or %s, and %s is %s (not a mount of or symlink to %s)", host, ErrKubeletNotAtDataDir, k3sConfigPath, unit, kubeletStdPath, st.mount, want)
		}
	}

	node, err := p.kubeNode(ctx, o)
	if err != nil {
		return nil, fmt.Errorf("[%s] %w", host, err)
	}
	if finishOnly {
		if st.unitActive && node.exists && node.ready && !node.cordoned {
			return nil, fmt.Errorf("[%s] %w: bind mount of %s in place, %s running, node Ready and schedulable", host, ErrKubeletAlreadyRelocated, want, unit)
		}
		situation += fmt.Sprintf("; %s is %s, node is %s", unit, map[bool]string{true: "running", false: "not running"}[st.unitActive], nodeWords(node))
	} else {
		if !node.exists {
			return nil, fmt.Errorf("[%s] node is not in the cluster (kubectl on %s does not know it)", host, o.ControlHost)
		}
		if st.unitActive {
			if err := p.checkQuorum(ctx, o); err != nil {
				return nil, fmt.Errorf("[%s] %w", host, err)
			}
		}
	}

	plan := &RelocationPlan{
		Host: host, Role: p.spec.Role, Unit: unit, DataDir: p.spec.DataDir, Backing: want,
		Found: found, ControlHost: o.ControlHost, Situation: situation,
		unitActive: st.unitActive, mountPlanned: !finishOnly,
		startPlanned: !finishOnly || !st.unitActive,
	}
	ctl := func(id, desc, cmd string) RelocationStep {
		return RelocationStep{ID: id, Desc: desc, Cmd: cmd, OnControl: true}
	}
	onNode := func(id, desc, cmd string) RelocationStep {
		return RelocationStep{ID: id, Desc: desc, Cmd: cmd}
	}

	if !finishOnly {
		plan.Steps = append(plan.Steps, ctl(stepCordon, "cordon "+host+" so nothing new is scheduled on it", "k3s kubectl cordon "+host))
		if st.unitActive {
			plan.Steps = append(plan.Steps, ctl(stepDrain,
				fmt.Sprintf("drain %s (ignore DaemonSets, delete emptyDir data, respect PodDisruptionBudgets, %s timeout)", host, o.DrainTimeout),
				fmt.Sprintf("k3s kubectl drain %s --ignore-daemonsets --delete-emptydir-data --timeout=%ds", host, int(o.DrainTimeout.Seconds()))))
			if p.spec.Role == "server" {
				snap := onNode(stepSnapshot, "take an etcd snapshot on "+host+" before stopping it (kept under "+p.spec.DataDir+"/server/db/snapshots/)",
					"k3s etcd-snapshot save --name "+snapshotName)
				snap.ShowOutput = true
				plan.Steps = append(plan.Steps, snap, RelocationStep{
					ID: stepGate, OnControl: true,
					Desc: "check again, right before the stop, that every other control-plane node is Ready, a majority remains, and etcd is healthy",
					Cmds: []string{membersCmd("control-plane"), membersCmd("etcd"), etcdReadyCmd},
					Run:  func(c context.Context) error { return p.checkQuorum(c, o) },
				})
			}
			plan.Steps = append(plan.Steps, onNode(stepStop, "stop "+unit, "systemctl stop "+unit))
		}
		plan.Steps = append(
			plan.Steps,
			onNode(stepKillall, "stop the containers that outlive the unit (DaemonSet pods still hold the old mounts)",
				"if [ -x /usr/local/bin/k3s-killall.sh ]; then /usr/local/bin/k3s-killall.sh; fi"),
			onNode(stepUnmount, "unmount leftover mounts under "+want+" so the new bind mount starts clean",
				"findmnt -rn -o TARGET | grep '^"+want+"/' | sort -r | xargs -r -n1 umount -l || true"),
		)
		if newCfg, changed, err := removeRootDirFromConfig(st.configYAML); err != nil {
			if errors.Is(err, errUnsafeEdit) {
				return nil, fmt.Errorf("[%s] %w: %v; edit %s by hand, then re-run", host, ErrRootDirUnsupported, err, k3sConfigPath)
			}
			return nil, fmt.Errorf("[%s] %w", host, err)
		} else if changed {
			plan.configPlanned = true
			plan.ConfigDiff = lineDiff(st.configYAML, newCfg)
			plan.Steps = append(plan.Steps, onNode(stepConfig,
				"remove the root-dir entry from kubelet-arg in "+k3sConfigPath+" (every other line is kept; mode and owner are preserved; backup at "+k3sConfigPath+backupSuffix+")",
				rewriteCmd(k3sConfigPath, newCfg)))
		}
		if newUnit, changed := removeRootDirFromUnit(st.unitText); changed {
			upath := "/etc/systemd/system/" + unit
			plan.unitPlanned = true
			plan.UnitDiff = lineDiff(st.unitText, newUnit)
			plan.Steps = append(plan.Steps, onNode(stepUnit,
				"remove the root-dir argument from ExecStart in "+upath+" (mode and owner are preserved; backup at "+upath+backupSuffix+")",
				rewriteCmd(upath, newUnit)))
		}
		plan.Steps = append(plan.Steps, onNode(stepBindMount,
			"bind-mount "+want+" at "+kubeletStdPath+" (replaces the symlink; persistent systemd mount unit ordered before "+unit+")",
			kubeletBindMountCmd(p.spec.DataDir, unit)))
	}

	if plan.startPlanned {
		plan.Steps = append(
			plan.Steps,
			RelocationStep{
				ID: stepStamp, Desc: "note the time on the node, to tell the restarted kubelet's heartbeat from the old one",
				Cmd: "date -u +%Y-%m-%dT%H:%M:%SZ", Capture: func(out string) { plan.startedAt = strings.TrimSpace(out) },
			},
			onNode(stepStart, "start "+unit, "systemctl start "+unit),
		)
	}
	readyCmd := fmt.Sprintf(`k3s kubectl get node %s -o jsonpath='{.status.conditions[?(@.type=="Ready")].status} {.status.conditions[?(@.type=="Ready")].lastHeartbeatTime}'`, host)
	plan.Steps = append(
		plan.Steps,
		RelocationStep{
			ID: stepReady, OnControl: true, Cmd: readyCmd, PollTimeout: o.ReadyTimeout,
			Desc: fmt.Sprintf("wait up to %s for %s to be Ready (with a heartbeat newer than the start, when it was restarted); polling every %s", o.ReadyTimeout, host, o.PollInterval),
			Done: func(out string) bool { return readyAfter(out, plan.startedAt) },
		},
		RelocationStep{
			ID: stepPropagation, Cmd: "findmnt -n -o PROPAGATION " + kubeletStdPath,
			Desc: "check that " + kubeletStdPath + " is a shared mount, so mounts made by the kubelet reach the CSI node plugin",
			Validate: func(out string) error {
				for _, f := range strings.Split(strings.TrimSpace(out), ",") {
					if strings.TrimSpace(f) == propagationWant {
						return nil
					}
				}
				return fmt.Errorf("%s has mount propagation %q, not %q: the CSI node plugin would not see the kubelet's mounts", kubeletStdPath, strings.TrimSpace(out), propagationWant)
			},
		},
		RelocationStep{
			ID: stepCSIPod, OnControl: true, PollTimeout: o.ReadyTimeout,
			Cmd:  "k3s kubectl get pods -A -l " + csiNFSNodeSelector + " --field-selector spec.nodeName=" + host + " --no-headers -o 'custom-columns=NS:.metadata.namespace,NAME:.metadata.name," + readyColumns + "'",
			Desc: "wait for the NFS CSI node plugin pod (" + csiNFSNodeSelector + ") on " + host + " to be Ready",
			Done: func(out string) bool {
				for _, l := range strings.Split(out, "\n") {
					if f := strings.Fields(l); len(f) >= 3 && f[len(f)-1] == "True" {
						return true
					}
				}
				return false
			},
		},
		RelocationStep{
			ID: stepCSINode, OnControl: true, PollTimeout: o.ReadyTimeout,
			Cmd:  "k3s kubectl get csinode " + host + " -o jsonpath='{.spec.drivers[*].name}'",
			Desc: "wait for " + csiNFSDriver + " to be registered in " + host + "'s CSINode",
			Done: func(out string) bool { return strings.Contains(out, csiNFSDriver) },
		},
	)
	cleanup, apply, wait, logs := p.nfsCheckCmds()
	plan.Steps = append(
		plan.Steps,
		RelocationStep{
			ID: stepNFSCheck, OnControl: true,
			Desc: fmt.Sprintf("prove it: a pod pinned to %s mounts a throwaway %q PVC in namespace %s, writes and reads a file; the pod and PVC are deleted after (the node stays cordoned until this passes)", host, checkStorageClass, checkNamespace),
			Cmds: append(append(append([]string{}, cleanup...), apply, wait, logs), "(after: the same delete commands again)"),
			Run:  func(c context.Context) error { return p.runNFSCheck(c, o) },
		},
		ctl(stepUncordon, "uncordon "+host, "k3s kubectl uncordon "+host),
	)
	plan.verifyMount = "findmnt " + kubeletStdPath + " && { [ " + kubeletStdPath + " -ef " + want + " ] && echo 'bind mount OK: " + kubeletStdPath + " is " + want + "' || echo 'WARNING: " + kubeletStdPath + " is not " + want + "'; }"
	plan.verifyCapacity = "k3s kubectl get node " + host + " -o jsonpath='{.status.capacity.ephemeral-storage}'"
	plan.verifyDisk = "df -B1 --output=size " + want + " | tail -n 1"

	p.describeImpact(ctx, o, plan, st.unitActive && !finishOnly)
	return plan, nil
}

func nodeWords(n kubeNodeInfo) string {
	switch {
	case !n.exists:
		return "not registered"
	case n.ready && n.cordoned:
		return "Ready but cordoned"
	case n.ready:
		return "Ready"
	case n.cordoned:
		return "not Ready and cordoned"
	}
	return "not Ready"
}

// rewriteCmd replaces a root-owned file with new contents: back it up, stage the
// new version, give it the original's mode, owner and SELinux label, then move it
// into place. The staging name is overwritten, so a leftover from an interrupted
// run is harmless.
func rewriteCmd(path, contents string) string {
	tmp := path + tmpSuffix
	return "cp -p " + path + " " + path + backupSuffix +
		" && echo " + util.Base64Encode(contents) + " | base64 -d > " + tmp +
		" && chmod --reference=" + path + " " + tmp +
		" && chown --reference=" + path + " " + tmp +
		" && { chcon --reference=" + path + " " + tmp + " 2>/dev/null || true; }" +
		" && mv " + tmp + " " + path
}

// describeImpact fills in what a dry run shows about the effect on the cluster:
// the pods the drain would evict, and local-path claims that pin pods to the node.
// Both reads are informational; a failure only leaves the list empty.
func (p *NativeProvider) describeImpact(ctx context.Context, o RelocateOptions, plan *RelocationPlan, willDrain bool) {
	if !willDrain {
		return
	}
	out, err := o.Control(ctx, "k3s kubectl get pods -A --field-selector spec.nodeName="+p.spec.Host+" --no-headers -o 'custom-columns=NS:.metadata.namespace,NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].kind'")
	if err == nil {
		for _, l := range strings.Split(out, "\n") {
			f := strings.Fields(l)
			if len(f) < 2 {
				continue
			}
			name := f[0] + "/" + f[1]
			if len(f) >= 3 && f[2] == "DaemonSet" {
				plan.Stay = append(plan.Stay, name)
			} else {
				plan.Evict = append(plan.Evict, name)
			}
		}
	}
	out, err = o.Control(ctx, "k3s kubectl get pv --no-headers -o 'custom-columns=SC:.spec.storageClassName,CLAIMNS:.spec.claimRef.namespace,CLAIM:.spec.claimRef.name,NODE:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]'")
	if err == nil {
		for _, l := range strings.Split(out, "\n") {
			f := strings.Fields(l)
			if len(f) >= 4 && f[0] == "local-path" && f[3] == p.spec.Host {
				plan.LocalPath = append(plan.LocalPath, f[1]+"/"+f[2])
			}
		}
	}
}

// readyAfter reports whether a "<status> <heartbeat>" reading shows the node
// Ready with a heartbeat at or after since (both RFC 3339 UTC, so they compare as
// strings).
func readyAfter(out, since string) bool {
	f := strings.Fields(out)
	if len(f) < 1 || f[0] != "True" {
		return false
	}
	if since == "" {
		return true
	}
	return len(f) >= 2 && f[1] >= since
}

// Print writes the plan with the exact commands, as a dry run shows it.
func (pl *RelocationPlan) Print(w io.Writer) {
	fmt.Fprintf(w, "Switch %s (%s, unit %s) to the standard kubelet path\n", pl.Host, pl.Role, pl.Unit)
	fmt.Fprintf(w, "  dataDir:       %s\n", pl.DataDir)
	fmt.Fprintf(w, "  now:           %s\n", pl.Situation)
	fmt.Fprintf(w, "  kubelet after: %s, a bind mount of %s (the files stay on the same volume)\n", kubeletStdPath, pl.Backing)
	fmt.Fprintf(w, "  kubectl runs:  on %s\n", pl.ControlHost)
	fmt.Fprintf(w, "  Each command runs as root over ssh (sudo sh -c '<command>').\n")
	if len(pl.Evict) > 0 || len(pl.Stay) > 0 {
		fmt.Fprintf(w, "\nThe drain would evict %d pod(s): %s\n", len(pl.Evict), strings.Join(pl.Evict, ", "))
		if len(pl.Stay) > 0 {
			fmt.Fprintf(w, "DaemonSet pods that stay (stopped with k3s, back after the start): %s\n", strings.Join(pl.Stay, ", "))
		}
	}
	if len(pl.LocalPath) > 0 {
		fmt.Fprintf(w, "WARNING: these local-path claims are pinned to %s, so their pods stay Pending while it is down: %s\n", pl.Host, strings.Join(pl.LocalPath, ", "))
	}
	if pl.ConfigDiff != "" {
		fmt.Fprintf(w, "\nChange to %s:\n%s\n", k3sConfigPath, indentLines(pl.ConfigDiff, "    "))
	}
	if pl.UnitDiff != "" {
		fmt.Fprintf(w, "\nChange to /etc/systemd/system/%s:\n%s\n", pl.Unit, indentLines(pl.UnitDiff, "    "))
	}
	fmt.Fprintln(w)
	for i, s := range pl.Steps {
		where := pl.Host
		if s.OnControl {
			where = pl.ControlHost
		}
		fmt.Fprintf(w, "%2d. [%s] %s\n", i+1, where, s.Desc)
		if len(s.Cmds) > 0 {
			for _, c := range s.Cmds {
				fmt.Fprintf(w, "      %s\n", c)
			}
		} else {
			fmt.Fprintf(w, "      %s\n", s.Cmd)
		}
	}
	fmt.Fprintf(w, "%2d. [%s] final check: the bind mount is in place\n      %s\n", len(pl.Steps)+1, pl.Host, pl.verifyMount)
	fmt.Fprintf(w, "    [%s] final check: the node still reports the big volume's size as ephemeral-storage\n      %s\n      %s (on %s)\n", pl.ControlHost, pl.verifyCapacity, pl.verifyDisk, pl.Host)
}

func indentLines(s, prefix string) string {
	return prefix + strings.ReplaceAll(s, "\n", "\n"+prefix)
}

// RelocateKubelet inspects the node, prints the plan, and (with o.Apply) runs it.
// Without Apply it makes only read-only calls and changes nothing.
func (p *NativeProvider) RelocateKubelet(ctx context.Context, o RelocateOptions) error {
	o.defaults()
	plan, err := p.PlanKubeletRelocation(ctx, o)
	if err != nil {
		return err
	}
	plan.Print(o.Out)
	if !o.Apply {
		fmt.Fprintf(o.Out, "\nDry run: only read-only checks were made. Nothing was changed.\nRe-run with --apply to switch %s.\n", plan.Host)
		return nil
	}
	fmt.Fprintf(o.Out, "\nApplying...\n")
	return p.executeRelocation(ctx, plan, o)
}

// RelocationError describes a failed run: what failed, where the node is now, and
// how to recover.
type RelocationError struct {
	Host     string
	Step     int // 1-based
	Total    int
	StepDesc string
	Err      error
	State    []string
	Recovery []string
}

func (e *RelocationError) Error() string {
	var b strings.Builder
	fmt.Fprintf(&b, "relocating the kubelet on %s failed at step %d of %d (%s): %v\n", e.Host, e.Step, e.Total, e.StepDesc, e.Err)
	b.WriteString("\nState of " + e.Host + " now:\n")
	for _, s := range e.State {
		b.WriteString("  - " + s + "\n")
	}
	b.WriteString("\nHow to recover:\n")
	for i, r := range e.Recovery {
		fmt.Fprintf(&b, "  %d. %s\n", i+1, r)
	}
	return strings.TrimRight(b.String(), "\n")
}

func (e *RelocationError) Unwrap() error { return e.Err }

func (p *NativeProvider) executeRelocation(ctx context.Context, plan *RelocationPlan, o RelocateOptions) error {
	done := map[string]bool{}
	stopIdx := indexOf(plan.Steps, stepStop)
	for i, s := range plan.Steps {
		fmt.Fprintf(o.Out, "[%d/%d] %s\n", i+1, len(plan.Steps), s.Desc)
		run := p.run
		if s.OnControl {
			run = o.Control
		}
		var out string
		var err error
		switch {
		case s.Run != nil:
			err = s.Run(ctx)
		case s.PollTimeout > 0:
			out, err = pollUntil(ctx, run, s.Cmd, s.Done, s.PollTimeout, o.PollInterval)
		default:
			out, err = run(ctx, s.Cmd)
		}
		if err == nil && s.Validate != nil {
			err = s.Validate(out)
		}
		if err == nil && s.Capture != nil {
			s.Capture(out)
		}
		if err == nil && s.ShowOutput && strings.TrimSpace(out) != "" {
			fmt.Fprintf(o.Out, "      %s\n", indent(strings.TrimSpace(out)))
		}
		if err != nil {
			rerr := &RelocationError{Host: plan.Host, Step: i + 1, Total: len(plan.Steps), StepDesc: s.Desc, Err: err}
			describeFailure(rerr, plan, s.ID, o, done, stopIdx < len(plan.Steps) && i < stopIdx)
			return rerr
		}
		done[s.ID] = true
	}
	p.finalCheck(ctx, plan, o)
	fmt.Fprintf(o.Out, "\n%s now runs its kubelet at %s (bind mount of %s), served an NFS volume, and is schedulable again.\n", plan.Host, kubeletStdPath, plan.Backing)
	return nil
}

func indexOf(steps []RelocationStep, id string) int {
	for i, s := range steps {
		if s.ID == id {
			return i
		}
	}
	return len(steps)
}

// describeFailure fills in the node's state and the recovery steps. A failure
// before k3s was stopped leaves the node running, so it is uncordoned right away;
// a failure after that leaves the node cordoned on purpose and says so.
func describeFailure(e *RelocationError, plan *RelocationPlan, failed string, o RelocateOptions, done map[string]bool, beforeStop bool) {
	host := plan.Host
	if beforeStop {
		uctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		_, uerr := o.Control(uctx, "k3s kubectl uncordon "+host)
		e.State = append(e.State, plan.Unit+" was never stopped and nothing on the node was changed")
		if uerr != nil {
			e.State = append(e.State, "kubernetes: the node may still be CORDONED (automatic uncordon failed: "+uerr.Error()+")")
			e.Recovery = append(e.Recovery, "on "+plan.ControlHost+": k3s kubectl uncordon "+host)
		} else {
			e.State = append(e.State, "kubernetes: uncordoned again (it may be partly drained; its pods are being rescheduled)")
		}
		e.Recovery = append(e.Recovery, "fix the cause shown above (a PodDisruptionBudget that blocks the drain, or an unhealthy control-plane node, are the usual ones), then re-run: "+o.Command+" --apply")
		return
	}
	startedHere := done[stepStart]
	switch {
	case startedHere:
		e.State = append(e.State, plan.Unit+" is STARTED")
	case done[stepStop]:
		e.State = append(e.State, plan.Unit+" is STOPPED (its containers were stopped too)")
	case !plan.unitActive:
		e.State = append(e.State, plan.Unit+" is STOPPED (it was already down when this run began)")
	case plan.startPlanned && failed != stepStop:
		e.State = append(e.State, plan.Unit+" is running (this run did not stop it)")
	case failed == stepStop:
		e.State = append(e.State, plan.Unit+": the stop did not complete, so it may be running or half stopped (check systemctl status "+plan.Unit+")")
	default:
		e.State = append(e.State, plan.Unit+" is running")
	}
	switch {
	case !plan.configPlanned:
		e.State = append(e.State, "config.yaml: root-dir was already removed (by an earlier run)")
	case done[stepConfig]:
		e.State = append(e.State, "config.yaml: root-dir already removed (original kept at "+k3sConfigPath+backupSuffix+")")
	default:
		e.State = append(e.State, "config.yaml: not changed yet by this run")
	}
	if plan.unitPlanned && done[stepUnit] {
		e.State = append(e.State, "ExecStart: root-dir already removed (original kept at /etc/systemd/system/"+plan.Unit+backupSuffix+")")
	}
	switch {
	case !plan.mountPlanned || done[stepBindMount]:
		e.State = append(e.State, kubeletStdPath+" is the bind mount of "+plan.Backing)
	case failed == stepBindMount:
		e.State = append(e.State, kubeletStdPath+" is unknown: that step replaces the symlink first, so it may be an empty directory or missing (check with ls -ld "+kubeletStdPath+"); a re-run accepts an empty directory and finishes the mount")
	default:
		e.State = append(e.State, kubeletStdPath+" is not mounted yet (still the symlink to "+plan.Backing+")")
	}
	if done[stepUncordon] {
		e.State = append(e.State, "kubernetes: uncordoned")
	} else {
		e.State = append(e.State, "kubernetes: CORDONED (left that way on purpose: it is not known to be healthy)")
	}
	if !startedHere && plan.startPlanned {
		e.Recovery = append(e.Recovery,
			"fix the cause shown above, then re-run: "+o.Command+" --apply (it resumes from where the node is now; what already happened is not repeated, and it finishes with start, Ready, the NFS check and uncordon)")
		e.Recovery = append(e.Recovery,
			"or put the node back as it was, on "+plan.Host+": restore the backups ("+k3sConfigPath+backupSuffix+" and /etc/systemd/system/"+plan.Unit+backupSuffix+", where they exist); "+
				"if the bind mount was made, undo it with systemctl disable --now "+kubeletMountUnitName+" && rm "+kubeletMountUnitPath+" && rmdir "+kubeletStdPath+" && ln -s "+plan.Backing+" "+kubeletStdPath+"; "+
				"then systemctl daemon-reload && systemctl start "+plan.Unit+", and on "+plan.ControlHost+": k3s kubectl uncordon "+host)
		return
	}
	e.Recovery = append(e.Recovery,
		"on "+plan.Host+": journalctl -u "+plan.Unit+" -n 100 and findmnt "+kubeletStdPath+" to see why the node is not healthy")
	e.Recovery = append(e.Recovery,
		"re-run "+o.Command+" --apply: with the bind mount in place and k3s running it only waits for Ready, repeats the NFS check and uncordons")
	if !done[stepUncordon] {
		e.Recovery = append(e.Recovery,
			"or, once "+host+" is Ready and you accept the risk, on "+plan.ControlHost+": k3s kubectl uncordon "+host)
	}
}

// pollUntil runs cmd every interval until accept approves its output or the
// timeout passes. A failing command counts as "not yet" (the API server can be
// briefly unreachable while a control-plane node restarts).
func pollUntil(ctx context.Context, run CommandRunner, cmd string, accept func(string) bool, timeout, interval time.Duration) (string, error) {
	deadline := time.Now().Add(timeout)
	var last string
	var lastErr error
	for {
		out, err := run(ctx, cmd)
		if err == nil && accept(out) {
			return out, nil
		}
		last, lastErr = strings.TrimSpace(out), err
		if !time.Now().Before(deadline) {
			if lastErr != nil {
				return last, fmt.Errorf("timed out after %s; last error: %w", timeout, lastErr)
			}
			return last, fmt.Errorf("timed out after %s; last reading: %q", timeout, last)
		}
		select {
		case <-ctx.Done():
			return last, ctx.Err()
		case <-time.After(interval):
		}
	}
}

// finalCheck prints the closing evidence: the bind mount, and that the node's
// reported ephemeral-storage is still the big volume's size. Problems are printed
// as warnings; by now the node is already back in service.
func (p *NativeProvider) finalCheck(ctx context.Context, plan *RelocationPlan, o RelocateOptions) {
	w := o.Out
	fmt.Fprintf(w, "\nFinal check on %s:\n", plan.Host)
	out, err := p.run(ctx, plan.verifyMount)
	fmt.Fprintf(w, "  %s\n", indent(strings.TrimSpace(out)))
	if err != nil {
		fmt.Fprintf(w, "  WARNING: mount check failed: %v\n", err)
	}
	capOut, cerr := o.Control(ctx, plan.verifyCapacity)
	diskOut, derr := p.run(ctx, plan.verifyDisk)
	if cerr != nil || derr != nil {
		fmt.Fprintf(w, "  WARNING: could not compare ephemeral-storage (kubectl: %v, df: %v)\n", cerr, derr)
		return
	}
	capBytes, e1 := parseQuantityBytes(capOut)
	diskBytes, e2 := strconv.ParseInt(strings.TrimSpace(diskOut), 10, 64)
	if e1 != nil || e2 != nil {
		fmt.Fprintf(w, "  WARNING: could not compare ephemeral-storage (reported %q, volume %q)\n", strings.TrimSpace(capOut), strings.TrimSpace(diskOut))
		return
	}
	if withinPercent(capBytes, diskBytes, 1) {
		fmt.Fprintf(w, "  ephemeral-storage OK: the node reports %s, the volume under %s is %s bytes\n", strings.TrimSpace(capOut), plan.Backing, strings.TrimSpace(diskOut))
		return
	}
	fmt.Fprintf(w, "  WARNING: the node reports ephemeral-storage %s (%d bytes) but the volume under %s is %d bytes; the kubelet may not be reporting the big volume\n",
		strings.TrimSpace(capOut), capBytes, plan.Backing, diskBytes)
}

func indent(s string) string { return strings.ReplaceAll(s, "\n", "\n  ") }

func withinPercent(a, b int64, pct float64) bool {
	if b == 0 {
		return a == 0
	}
	d := float64(a - b)
	if d < 0 {
		d = -d
	}
	return d/float64(b)*100 <= pct
}

// parseQuantityBytes parses a Kubernetes storage quantity ("479670088Ki",
// "512Gi", "123456") into bytes.
func parseQuantityBytes(q string) (int64, error) {
	q = strings.TrimSpace(q)
	mult := int64(1)
	for _, u := range []struct {
		s string
		m int64
	}{{"Ki", 1 << 10}, {"Mi", 1 << 20}, {"Gi", 1 << 30}, {"Ti", 1 << 40}, {"K", 1000}, {"M", 1000 * 1000}, {"G", 1000 * 1000 * 1000}, {"T", 1000 * 1000 * 1000 * 1000}} {
		if strings.HasSuffix(q, u.s) {
			q, mult = strings.TrimSuffix(q, u.s), u.m
			break
		}
	}
	n, err := strconv.ParseInt(q, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parsing quantity %q: %w", q, err)
	}
	return n * mult, nil
}
