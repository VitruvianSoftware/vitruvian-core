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
	"sort"
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
	// ErrKubeletAlreadyRelocated: /var/lib/kubelet is already the bind mount and
	// no root-dir argument remains. Nothing to do.
	ErrKubeletAlreadyRelocated = errors.New("kubelet is already at /var/lib/kubelet")
	// ErrKubeletNotAtDataDir: the kubelet is not currently at <dataDir>/kubelet.
	ErrKubeletNotAtDataDir = errors.New("kubelet is not currently at <dataDir>/kubelet")
	// ErrRootDirUnsupported: a root-dir setting lives somewhere this command does
	// not edit (a drop-in), so it would survive the change.
	ErrRootDirUnsupported = errors.New("root-dir is set somewhere devx does not edit")
	// ErrQuorumRisk: stopping this control-plane node would endanger etcd quorum.
	ErrQuorumRisk = errors.New("stopping this control-plane node is unsafe right now")
	// ErrNotNative: only native Linux nodes can be switched.
	ErrNotNative = errors.New("only native nodes can be switched")
)

const (
	k3sConfigPath = "/etc/rancher/k3s/config.yaml"
	// backupSuffix marks the copies made before a file is edited. It is also
	// excluded from the root-dir scan so a re-run is not confused by its own backup.
	backupSuffix = ".pre-relocate-kubelet"
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
	// Control runs kubectl as root on a control-plane node, ControlHost names it,
	// and OtherServers lists the other control-plane hosts that must stay Ready.
	Control      CommandRunner
	ControlHost  string
	OtherServers []string
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
	stepCordon    = "cordon"
	stepDrain     = "drain"
	stepStop      = "stop"
	stepKillall   = "killall"
	stepUnmount   = "unmount"
	stepConfig    = "config"
	stepUnit      = "unit"
	stepBindMount = "bindmount"
	stepStamp     = "stamp"
	stepStart     = "start"
	stepReady     = "ready"
	stepUncordon  = "uncordon"
)

// RelocationStep is one action of the plan. Cmd is the exact command run as root
// on the host named by OnControl.
type RelocationStep struct {
	ID        string
	Desc      string
	Cmd       string
	OnControl bool // run on the control-plane node; otherwise on the node itself
	// PollTimeout > 0 makes the step poll Cmd every interval until Done accepts the
	// output.
	PollTimeout time.Duration
	Done        func(out string) bool
	// Capture, when set, receives the step's output (used to timestamp the start).
	Capture func(out string)
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
	Steps       []RelocationStep
	// Verify commands for the final check.
	verifyMount, verifyCapacity, verifyDisk string

	startedAt string
}

// kubeletNodeState is what the read-only inspections found on the node; it decides
// whether the node can be switched and feeds the edits.
type kubeletNodeState struct {
	unitPresent bool
	configYAML  string
	unitText    string
	rootDirHits []string
	mounted     bool
	symlinkTo   string
}

func (p *NativeProvider) inspectKubelet(ctx context.Context, unit string) (kubeletNodeState, error) {
	var st kubeletNodeState
	out, err := p.run(ctx, "systemctl cat "+unit+" >/dev/null 2>&1 && echo present || echo missing")
	if err != nil {
		return st, fmt.Errorf("[%s] checking %s: %w", p.spec.Host, unit, err)
	}
	st.unitPresent = strings.Contains(out, "present")
	if st.configYAML, err = p.run(ctx, "cat "+k3sConfigPath+" 2>/dev/null || true"); err != nil {
		return st, fmt.Errorf("[%s] reading %s: %w", p.spec.Host, k3sConfigPath, err)
	}
	if st.unitText, err = p.run(ctx, "cat /etc/systemd/system/"+unit+" 2>/dev/null || true"); err != nil {
		return st, fmt.Errorf("[%s] reading %s: %w", p.spec.Host, unit, err)
	}
	hits, err := p.run(ctx, "grep -rls --exclude='*"+backupSuffix+"' root-dir /etc/rancher/k3s /etc/systemd/system/"+unit+" /etc/systemd/system/"+unit+".d 2>/dev/null || true")
	if err != nil {
		return st, fmt.Errorf("[%s] scanning for root-dir: %w", p.spec.Host, err)
	}
	for _, l := range strings.Split(hits, "\n") {
		if l = strings.TrimSpace(l); l != "" {
			st.rootDirHits = append(st.rootDirHits, l)
		}
	}
	m, err := p.run(ctx, "mountpoint -q "+kubeletStdPath+" && echo mounted || echo not-mounted")
	if err != nil {
		return st, fmt.Errorf("[%s] checking the %s mount: %w", p.spec.Host, kubeletStdPath, err)
	}
	st.mounted = strings.TrimSpace(m) == "mounted"
	if st.symlinkTo, err = p.run(ctx, "readlink "+kubeletStdPath+" || true"); err != nil {
		return st, fmt.Errorf("[%s] reading %s: %w", p.spec.Host, kubeletStdPath, err)
	}
	st.symlinkTo = strings.TrimSpace(st.symlinkTo)
	return st, nil
}

// checkControlPlane makes sure the control node answers and, for a server target,
// that every other control-plane node is Ready (so etcd keeps quorum while this
// one is down). Also confirms the target is a known node.
func (p *NativeProvider) checkControlPlane(ctx context.Context, o RelocateOptions) error {
	out, err := o.Control(ctx, "k3s kubectl get nodes --no-headers")
	if err != nil {
		return fmt.Errorf("asking %s for the node list: %w", o.ControlHost, err)
	}
	status := map[string]string{}
	for _, l := range strings.Split(out, "\n") {
		f := strings.Fields(l)
		if len(f) >= 2 {
			status[f[0]] = f[1]
		}
	}
	if _, ok := status[p.spec.Host]; !ok {
		return fmt.Errorf("node %q is not in the cluster (kubectl on %s lists: %s)", p.spec.Host, o.ControlHost, nodeNames(status))
	}
	if p.spec.Role == "server" {
		for _, h := range o.OtherServers {
			if !strings.HasPrefix(status[h], "Ready") {
				return fmt.Errorf("%w: control-plane node %q is %q, not Ready; taking %s down as well could break etcd quorum", ErrQuorumRisk, h, status[h], p.spec.Host)
			}
		}
	}
	return nil
}

func nodeNames(m map[string]string) string {
	names := make([]string, 0, len(m))
	for n := range m {
		names = append(names, n)
	}
	sort.Strings(names)
	return strings.Join(names, ", ")
}

// PlanKubeletRelocation inspects the node (read-only) and returns the plan to
// move its kubelet from <dataDir>/kubelet to the standard /var/lib/kubelet bind
// mount. It refuses, with a wrapped sentinel error, when the node should not be
// touched.
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
	unit := k3sUnitFor(p.spec.Role)
	want := kubeletBackingDir(p.spec.DataDir)
	st, err := p.inspectKubelet(ctx, unit)
	if err != nil {
		return nil, err
	}
	if !st.unitPresent {
		return nil, fmt.Errorf("[%s] %s is not installed on the host", p.spec.Host, unit)
	}

	// Where is root-dir set, and to what?
	cfgVals, err := rootDirValuesInConfig(st.configYAML)
	if err != nil {
		return nil, fmt.Errorf("[%s] %w", p.spec.Host, err)
	}
	unitVals := rootDirValuesInUnit(st.unitText)
	found := append(append([]string{}, cfgVals...), unitVals...)
	handled := map[string]bool{k3sConfigPath: true, "/etc/systemd/system/" + unit: true}
	for _, f := range st.rootDirHits {
		if !handled[f] {
			return nil, fmt.Errorf("[%s] %w: %s mentions root-dir; remove it by hand, then re-run", p.spec.Host, ErrRootDirUnsupported, f)
		}
	}
	for _, v := range found {
		if !samePath(v, want) {
			return nil, fmt.Errorf("[%s] %w: root-dir is %q but dataDir implies %q; the node does not match the devx config", p.spec.Host, ErrKubeletNotAtDataDir, v, want)
		}
	}
	if len(found) == 0 {
		switch {
		case st.mounted:
			return nil, fmt.Errorf("[%s] %w: %s is already a mount and no root-dir argument remains", p.spec.Host, ErrKubeletAlreadyRelocated, kubeletStdPath)
		case samePath(st.symlinkTo, want) && st.symlinkTo != "":
			// Interrupted earlier: the argument is gone, the bind mount is not there yet. Resume.
		default:
			return nil, fmt.Errorf("[%s] %w: no root-dir argument in %s or %s, and %s is neither a mount nor a symlink to %s", p.spec.Host, ErrKubeletNotAtDataDir, k3sConfigPath, unit, kubeletStdPath, want)
		}
	}

	if err := p.checkControlPlane(ctx, o); err != nil {
		return nil, fmt.Errorf("[%s] %w", p.spec.Host, err)
	}

	plan := &RelocationPlan{
		Host: p.spec.Host, Role: p.spec.Role, Unit: unit, DataDir: p.spec.DataDir, Backing: want,
		Found: found, ControlHost: o.ControlHost,
	}
	host := p.spec.Host
	ctl := func(id, desc, cmd string) RelocationStep {
		return RelocationStep{ID: id, Desc: desc, Cmd: cmd, OnControl: true}
	}
	node := func(id, desc, cmd string) RelocationStep {
		return RelocationStep{ID: id, Desc: desc, Cmd: cmd}
	}
	plan.Steps = append(
		plan.Steps,
		ctl(stepCordon, "cordon "+host+" so nothing new is scheduled on it", "k3s kubectl cordon "+host),
		ctl(stepDrain, fmt.Sprintf("drain %s (ignore DaemonSets, delete emptyDir data, respect PodDisruptionBudgets, %s timeout)", host, o.DrainTimeout),
			fmt.Sprintf("k3s kubectl drain %s --ignore-daemonsets --delete-emptydir-data --timeout=%ds", host, int(o.DrainTimeout.Seconds()))),
		node(stepStop, "stop "+unit, "systemctl stop "+unit),
		node(stepKillall, "stop the containers that outlive the unit (DaemonSet pods still hold the old mounts)",
			"if [ -x /usr/local/bin/k3s-killall.sh ]; then /usr/local/bin/k3s-killall.sh; fi"),
		node(stepUnmount, "unmount leftover mounts under "+want+" so the new bind mount starts clean",
			"findmnt -rn -o TARGET | grep '^"+want+"/' | sort -r | xargs -r -n1 umount -l || true"),
	)
	if newCfg, changed, err := removeRootDirFromConfig(st.configYAML); err != nil {
		return nil, fmt.Errorf("[%s] %w", host, err)
	} else if changed {
		bak := k3sConfigPath + backupSuffix
		plan.Steps = append(plan.Steps, node(stepConfig,
			"remove the root-dir entry from kubelet-arg in "+k3sConfigPath+" (every other key is kept; backup at "+bak+")",
			"cp -p "+k3sConfigPath+" "+bak+" && echo "+util.Base64Encode(newCfg)+" | base64 -d > "+k3sConfigPath+".devx-new && mv "+k3sConfigPath+".devx-new "+k3sConfigPath))
	}
	if newUnit, changed := removeRootDirFromUnit(st.unitText); changed {
		upath := "/etc/systemd/system/" + unit
		plan.Steps = append(plan.Steps, node(stepUnit,
			"remove the root-dir argument from ExecStart in "+upath+" (backup at "+upath+backupSuffix+")",
			"cp -p "+upath+" "+upath+backupSuffix+" && echo "+util.Base64Encode(newUnit)+" | base64 -d > "+upath+".devx-new && mv "+upath+".devx-new "+upath))
	}
	plan.Steps = append(
		plan.Steps,
		node(stepBindMount, "bind-mount "+want+" at "+kubeletStdPath+" (replaces the symlink; persistent systemd mount unit ordered before "+unit+")",
			kubeletBindMountCmd(p.spec.DataDir, unit)),
		RelocationStep{
			ID: stepStamp, Desc: "note the time on the node, to tell the restarted kubelet's heartbeat from the old one",
			Cmd: "date -u +%Y-%m-%dT%H:%M:%SZ", Capture: func(out string) { plan.startedAt = strings.TrimSpace(out) },
		},
		node(stepStart, "start "+unit, "systemctl start "+unit),
	)
	readyCmd := fmt.Sprintf(`k3s kubectl get node %s -o jsonpath='{.status.conditions[?(@.type=="Ready")].status} {.status.conditions[?(@.type=="Ready")].lastHeartbeatTime}'`, host)
	plan.Steps = append(
		plan.Steps,
		RelocationStep{
			ID: stepReady, OnControl: true, Cmd: readyCmd, PollTimeout: o.ReadyTimeout,
			Desc: fmt.Sprintf("wait up to %s for %s to be Ready with a heartbeat newer than the start (polling every %s)", o.ReadyTimeout, host, o.PollInterval),
			Done: func(out string) bool { return readyAfter(out, plan.startedAt) },
		},
		ctl(stepUncordon, "uncordon "+host, "k3s kubectl uncordon "+host),
	)
	plan.verifyMount = "findmnt " + kubeletStdPath + " && { [ " + kubeletStdPath + " -ef " + want + " ] && echo 'bind mount OK: " + kubeletStdPath + " is " + want + "' || echo 'WARNING: " + kubeletStdPath + " is not " + want + "'; }"
	plan.verifyCapacity = "k3s kubectl get node " + host + " -o jsonpath='{.status.capacity.ephemeral-storage}'"
	plan.verifyDisk = "df -B1 --output=size " + want + " | tail -n 1"
	return plan, nil
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
	if len(pl.Found) > 0 {
		fmt.Fprintf(w, "  kubelet now:   at %s (root-dir kubelet-arg)\n", pl.Backing)
	} else {
		fmt.Fprintf(w, "  kubelet now:   %s symlinked to %s (an earlier run was interrupted; resuming)\n", kubeletStdPath, pl.Backing)
	}
	fmt.Fprintf(w, "  kubelet after: %s, a bind mount of %s (the files stay on the same volume)\n", kubeletStdPath, pl.Backing)
	fmt.Fprintf(w, "  kubectl runs:  on %s\n", pl.ControlHost)
	fmt.Fprintf(w, "  Each command runs as root over ssh (sudo sh -c '<command>').\n\n")
	for i, s := range pl.Steps {
		where := pl.Host
		if s.OnControl {
			where = pl.ControlHost
		}
		fmt.Fprintf(w, "%2d. [%s] %s\n", i+1, where, s.Desc)
		fmt.Fprintf(w, "      %s\n", s.Cmd)
	}
	fmt.Fprintf(w, "%2d. [%s] final check: the bind mount is in place\n      %s\n", len(pl.Steps)+1, pl.Host, pl.verifyMount)
	fmt.Fprintf(w, "    [%s] final check: the node still reports the big volume's size as ephemeral-storage\n      %s\n      %s (on %s)\n", pl.ControlHost, pl.verifyCapacity, pl.verifyDisk, pl.Host)
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
	stoppedAt := indexOf(plan.Steps, stepStop)
	for i, s := range plan.Steps {
		fmt.Fprintf(o.Out, "[%d/%d] %s\n", i+1, len(plan.Steps), s.Desc)
		run := p.run
		if s.OnControl {
			run = o.Control
		}
		var out string
		var err error
		if s.PollTimeout > 0 {
			out, err = pollUntil(ctx, run, s.Cmd, s.Done, s.PollTimeout, o.PollInterval)
		} else {
			out, err = run(ctx, s.Cmd)
		}
		if err == nil && s.Capture != nil {
			s.Capture(out)
		}
		if err != nil {
			rerr := &RelocationError{Host: plan.Host, Step: i + 1, Total: len(plan.Steps), StepDesc: s.Desc, Err: err}
			describeFailure(rerr, plan, s.ID, o, done, i < stoppedAt)
			return rerr
		}
		done[s.ID] = true
	}
	p.finalCheck(ctx, plan, o)
	fmt.Fprintf(o.Out, "\n%s now runs its kubelet at %s (bind mount of %s) and is schedulable again.\n", plan.Host, kubeletStdPath, plan.Backing)
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
		e.Recovery = append(e.Recovery, "fix the cause shown above (a PodDisruptionBudget that blocks the drain is the usual one), then re-run: "+o.Command+" --apply")
		return
	}
	switch {
	case done[stepStart]:
		e.State = append(e.State, plan.Unit+" is STARTED")
	case done[stepStop]:
		e.State = append(e.State, plan.Unit+" is STOPPED (its containers were stopped too)")
	default:
		e.State = append(e.State, plan.Unit+": the stop did not complete, so it may be running or half stopped (check systemctl status "+plan.Unit+")")
	}
	cfg := "config.yaml: not changed yet"
	if done[stepConfig] {
		cfg = "config.yaml: root-dir already removed (original kept at " + k3sConfigPath + backupSuffix + ")"
	}
	e.State = append(e.State, cfg)
	if done[stepUnit] {
		e.State = append(e.State, "ExecStart: root-dir already removed (original kept at /etc/systemd/system/"+plan.Unit+backupSuffix+")")
	}
	switch {
	case done[stepBindMount]:
		e.State = append(e.State, kubeletStdPath+" is now the bind mount of "+plan.Backing)
	case failed == stepBindMount:
		e.State = append(e.State, kubeletStdPath+" is unknown: that step replaces the symlink first, so it may be an empty directory or missing (check with ls -ld "+kubeletStdPath+")")
	default:
		e.State = append(e.State, kubeletStdPath+" is still the symlink to "+plan.Backing)
	}
	if done[stepUncordon] {
		e.State = append(e.State, "kubernetes: uncordoned")
	} else {
		e.State = append(e.State, "kubernetes: CORDONED (left that way on purpose: it is not known to be healthy)")
	}
	if !done[stepStart] {
		e.Recovery = append(e.Recovery,
			"fix the cause shown above, then re-run: "+o.Command+" --apply (it resumes from where the node is now; nothing is repeated that already happened)")
		e.Recovery = append(e.Recovery,
			"or put the node back as it was, on "+plan.Host+": restore the backups ("+k3sConfigPath+backupSuffix+" and /etc/systemd/system/"+plan.Unit+backupSuffix+", where they exist); "+
				"if the bind mount was made, undo it with systemctl disable --now "+kubeletMountUnitName+" && rm "+kubeletMountUnitPath+" && rmdir "+kubeletStdPath+" && ln -s "+plan.Backing+" "+kubeletStdPath+"; "+
				"then systemctl daemon-reload && systemctl start "+plan.Unit+", and on "+plan.ControlHost+": k3s kubectl uncordon "+host)
		return
	}
	e.Recovery = append(e.Recovery,
		"on "+plan.Host+": journalctl -u "+plan.Unit+" -n 100 and findmnt "+kubeletStdPath+" to see why the node is not Ready")
	if !done[stepUncordon] {
		e.Recovery = append(e.Recovery,
			"once "+host+" is Ready, on "+plan.ControlHost+": k3s kubectl uncordon "+host)
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
