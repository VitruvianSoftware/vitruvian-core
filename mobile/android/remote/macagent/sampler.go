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

package main

import (
	"context"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/VitruvianSoftware/vitruvian-core/mobile/android/remote/macagent/metrics"
)

// Every command this file runs has a fixed name and fixed arguments, and
// nothing from the network reaches an argv. The act endpoints, which do run
// what a caller asks for, live in exec.go behind the pairing token -- and
// exec.go is the only file in this package that imports os/exec.

// topProcesses is how many rows GET /v1/processes returns. Eight is what
// fits on a phone screen without scrolling; more would be a list nobody
// reads on a device this size.
const topProcesses = 8

// sessionWindow is how recently a Claude Code transcript must have been
// written for its project to count as active. Long enough to survive a
// coffee break, short enough that yesterday's work is not "running".
const sessionWindow = 30 * time.Minute

// notConfiguredKube is the reason a phone sees when the agent was started
// without --kube-context. Naming the flag is the point: "unavailable" with
// no next step is a dead end, and this one is fixed by restarting the agent
// with an argument.
const notConfiguredKube = "not configured (--kube-context)"

// Sampler keeps the latest reading and refreshes it in the background.
//
// Serving from a cache rather than sampling per request matters for one
// reason: a real CPU figure needs two top samples a second apart, which is
// far too slow to do inside an HTTP handler, and doing it per request would
// also let a client with a tight poll loop turn the agent into a CPU load of
// its own.
type Sampler struct {
	mu   sync.RWMutex
	snap metrics.Snapshot
	host metrics.Host

	// The v1.1 readings. Sampled on the same tick and served from here for
	// the same reason as the metrics: limactl and kubectl take hundreds of
	// milliseconds each on a good day and seconds on a bad one, and a phone
	// that polls four screens would otherwise pay for all of it, per screen,
	// per tick.
	processes   metrics.Processes
	vms         metrics.VMs
	container   metrics.Containers
	k8s         metrics.K8s
	audio       metrics.Audio
	sessions    metrics.Sessions
	ollama      metrics.Ollama
	tools       metrics.Tools
	antigravity metrics.Antigravity

	interval time.Duration
	// kubeContext is empty unless --kube-context was given, and an empty one
	// is "not configured", not "the current context". Falling back to
	// whatever kubectl happens to point at would let the agent report a
	// production cluster to a phone because someone ran a kubectl command
	// three days ago.
	// kubeconfig is the FILE; empty lets kubectl pick its default. The lab
	// cluster's config on this machine is ~/.kube/cluster.yaml, not
	// ~/.kube/config, which is why the file is a separate flag.
	kubeconfig  string
	kubeContext string
	// The previous network counters, for the rate calculation.
	prevNet metrics.Network
	prevAt  time.Time
}

func NewSampler(interval time.Duration, kubeconfig, kubeContext string) *Sampler {
	// Seeded rather than left zero-valued. A zero VMs marshals to
	// {"available":false,"reason":"","vms":null}, and a phone that asks in
	// the first two seconds would render an empty list with no explanation --
	// the exact failure the available/reason pair exists to prevent.
	const notYet = "sampling"
	kubeReason := notYet
	if kubeContext == "" {
		// Known without asking anything, so it is the answer from the first
		// request rather than from the first tick.
		kubeReason = notConfiguredKube
	}
	return &Sampler{
		interval:    interval,
		kubeconfig:  kubeconfig,
		kubeContext: kubeContext,
		processes:   metrics.Processes{Processes: []metrics.Process{}},
		vms:         metrics.VMs{Reason: notYet, VMs: []metrics.VM{}},
		container:   metrics.Containers{Reason: notYet, Containers: []metrics.Container{}},
		k8s:         metrics.K8s{Reason: kubeReason, Context: kubeContext, Nodes: []metrics.Node{}},
		sessions:    metrics.Sessions{Sessions: []metrics.Session{}},
	}
}

func (s *Sampler) Snapshot() metrics.Snapshot {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.snap
}

func (s *Sampler) Host() metrics.Host {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.host
}

func (s *Sampler) Processes() metrics.Processes {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.processes
}

func (s *Sampler) Tools() metrics.Tools {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.tools
}

func (s *Sampler) Antigravity() metrics.Antigravity {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.antigravity
}

func (s *Sampler) Ollama() metrics.Ollama {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.ollama
}

func (s *Sampler) VMs() metrics.VMs {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.vms
}

func (s *Sampler) Containers() metrics.Containers {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.container
}

func (s *Sampler) K8s() metrics.K8s {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.k8s
}

func (s *Sampler) Audio() metrics.Audio {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.audio
}

// SetAudio records what POST /v1/audio just did, so the next GET does not
// show the old volume for up to a full sampling interval.
func (s *Sampler) SetAudio(a metrics.Audio) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.audio = a
}

func (s *Sampler) Sessions() metrics.Sessions {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.sessions
}

// Run blocks until ctx is cancelled. Two loops: the fast commands on the
// configured interval, and top on its own, because top paces itself and a
// single loop would either stall the fast readings behind it or fire top
// more often than it can answer.
func (s *Sampler) Run(ctx context.Context) {
	s.readHost(ctx)
	go s.cpuLoop(ctx)
	go s.toolsLoop(ctx)
	go s.agyLoop(ctx)
	s.fastLoop(ctx)
}

// toolsLoop refreshes the optional sources. Its own goroutine for the same
// reason top has one: limactl, docker and kubectl can each take seconds,
// and behind the fast loop they would make every CPU and memory reading
// that stale. It paces itself -- the commands' own duration plus interval --
// which on a machine where a daemon is wedged means it asks less often, not
// that it piles up.
func (s *Sampler) toolsLoop(ctx context.Context) {
	for ctx.Err() == nil {
		s.readTools(ctx)
		sleep(ctx, s.interval)
	}
}

func (s *Sampler) cpuLoop(ctx context.Context) {
	for ctx.Err() == nil {
		// -l 2: the first sample is the since-boot average; only the second
		// reflects the last second. -n 0: no process list. -s 1: one second
		// between samples.
		out, err := runWithin(ctx, topTimeout, "top", "-l", "2", "-n", "0", "-s", "1")
		if err != nil {
			log.Printf("top: %v", err)
			sleep(ctx, s.interval)
			continue
		}
		cpu, err := metrics.ParseTop(out)
		if err != nil {
			log.Printf("top: %v", err)
			sleep(ctx, s.interval)
			continue
		}
		s.mu.Lock()
		cpu.Load1, cpu.Load5, cpu.Load15 = s.snap.CPU.Load1, s.snap.CPU.Load5, s.snap.CPU.Load15
		cpu.Cores = s.host.Cores
		s.snap.CPU = cpu
		s.mu.Unlock()
	}
}

func (s *Sampler) fastLoop(ctx context.Context) {
	for ctx.Err() == nil {
		s.readFast(ctx)
		sleep(ctx, s.interval)
	}
}

func (s *Sampler) readFast(ctx context.Context) {
	now := time.Now()
	var next metrics.Snapshot

	freePct := 0
	if out, err := run(ctx, "sysctl", "-n", "kern.memorystatus_level"); err == nil {
		freePct, _ = strconv.Atoi(strings.TrimSpace(out))
	}
	if out, err := run(ctx, "vm_stat"); err == nil {
		if m, err := metrics.ParseVmStat(out, s.host.MemoryBytes, freePct); err == nil {
			next.Memory = m
		} else {
			log.Printf("vm_stat: %v", err)
		}
	}
	if out, err := run(ctx, "ioreg", "-r", "-c", "AppleSmartBattery", "-d", "1"); err == nil {
		next.Battery, _ = metrics.ParseBattery(out)
	}
	if out, err := run(ctx, "df", "-k", "/"); err == nil {
		if d, err := metrics.ParseDf(out, "/"); err == nil {
			next.Disk = d
		}
	}
	if out, err := run(ctx, "pmset", "-g", "therm"); err == nil {
		next.Thermal = metrics.ParseTherm(out)
	}
	if out, err := run(ctx, "sysctl", "-n", "kern.boottime"); err == nil {
		if bt, err := metrics.ParseBoottime(out); err == nil {
			next.UptimeSeconds = int64(now.Sub(bt).Seconds())
		}
	}
	iface := ""
	if out, err := run(ctx, "route", "-n", "get", "default"); err == nil {
		iface, _ = metrics.ParseDefaultInterface(out)
	}
	if iface != "" {
		// -n is load-bearing: without it netstat reverse-resolves every
		// address and takes ~5 s on a normal machine, which turned this
		// 2 s loop into a 7 s one and made every reading look stale. The
		// <Link#N> rows the parser uses carry no names anyway.
		if out, err := run(ctx, "netstat", "-ibn"); err == nil {
			if n, err := metrics.ParseNetstat(out, iface); err == nil {
				// Rate from the previous reading of the SAME interface. A
				// route flap to a different interface resets the baseline
				// rather than reporting a wild negative delta.
				if s.prevNet.Interface == iface && !s.prevAt.IsZero() {
					dt := now.Sub(s.prevAt).Seconds()
					if dt > 0 && n.RxBytes >= s.prevNet.RxBytes && n.TxBytes >= s.prevNet.TxBytes {
						n.RxBytesPerSec = float64(n.RxBytes-s.prevNet.RxBytes) / dt
						n.TxBytesPerSec = float64(n.TxBytes-s.prevNet.TxBytes) / dt
					}
				}
				s.prevNet, s.prevAt = n, now
				next.Network = n
			}
		}
	}

	// Stamped AFTER the commands, not before: the age a client sees must be
	// the age of the numbers, not the age of the moment we started asking.
	next.SampledAt = time.Now()
	next.Unavailable = unavailable

	s.mu.Lock()
	// CPU is owned by cpuLoop; carry the last reading across rather than
	// zeroing it every fast tick. Load averages are refreshed here.
	next.CPU = s.snap.CPU
	next.CPU.Load1, next.CPU.Load5, next.CPU.Load15 = s.parseLoad(ctx)
	s.snap = next
	s.mu.Unlock()
}

func (s *Sampler) parseLoad(ctx context.Context) (float64, float64, float64) {
	out, err := run(ctx, "sysctl", "-n", "vm.loadavg")
	if err != nil {
		return s.snap.CPU.Load1, s.snap.CPU.Load5, s.snap.CPU.Load15
	}
	l1, l5, l15, err := metrics.ParseLoadAvg(out)
	if err != nil {
		return s.snap.CPU.Load1, s.snap.CPU.Load5, s.snap.CPU.Load15
	}
	return l1, l5, l15
}

func (s *Sampler) readHost(ctx context.Context) {
	h := metrics.Host{AgentVersion: version}
	get := func(key string) string {
		out, err := run(ctx, "sysctl", "-n", key)
		if err != nil {
			return ""
		}
		return strings.TrimSpace(out)
	}
	h.Model = get("hw.model")
	h.Chip = get("machdep.cpu.brand_string")
	h.Cores, _ = strconv.Atoi(get("hw.ncpu"))
	h.MemoryBytes, _ = strconv.ParseUint(get("hw.memsize"), 10, 64)
	if out, err := run(ctx, "sw_vers", "-productVersion"); err == nil {
		h.OSVersion = strings.TrimSpace(out)
	}
	if out, err := run(ctx, "hostname", "-s"); err == nil {
		h.Hostname = strings.TrimSpace(out)
	}
	if out, err := run(ctx, "ifconfig", "en0"); err == nil {
		h.MACAddress, _ = metrics.ParseEther(out)
	}
	if out, err := run(ctx, "pmset", "-g"); err == nil {
		h.WakeOnLAN = metrics.ParseWomp(out)
	}
	s.mu.Lock()
	s.host = h
	s.mu.Unlock()
}

// readTools refreshes everything behind /v1/processes, /v1/vms,
// /v1/containers, /v1/k8s, /v1/audio and /v1/sessions.
//
// Each source is independent: a missing limactl must not cost the container
// list, and none of them may turn into an empty list. Every failure path
// below ends in available:false with a reason a person can act on.
func (s *Sampler) readTools(ctx context.Context) {
	procs := s.readProcesses(ctx)
	vms := s.readVMs(ctx)
	containers := s.readContainers(ctx)
	k8s := s.readK8s(ctx)
	sessions := s.readSessions(ctx)
	ollama := s.readOllama(ctx)
	tools := toolPresence(knownTools)

	s.mu.Lock()
	s.tools = tools
	if procs != nil {
		s.processes = metrics.Processes{SampledAt: time.Now(), Processes: procs}
	}
	s.vms, s.container, s.k8s, s.sessions, s.ollama = vms, containers, k8s, sessions, ollama
	s.mu.Unlock()

	// Audio last and separately: unlike the others it can be changed by
	// POST /v1/audio between ticks, and overwriting a just-set value with a
	// stale reading would make the phone's slider spring back.
	if out, err := run(ctx, "osascript", "-e", "get volume settings"); err == nil {
		if a, err := metrics.ParseVolumeSettings(out); err == nil {
			s.SetAudio(a)
		}
	}
}

func (s *Sampler) readProcesses(ctx context.Context) []metrics.Process {
	out, err := run(ctx, "ps", "-Aceo", "pcpu,rss,comm", "-r")
	if err != nil {
		log.Printf("ps: %v", err)
		return nil
	}
	procs, err := metrics.ParseProcesses(out, topProcesses)
	if err != nil {
		log.Printf("ps: %v", err)
		return nil
	}
	return procs
}

// knownTools are the programs the phone's modules depend on. Presence is
// answered with LookPath on the agent's (extended) PATH, so it is the same
// answer the exec endpoint would get.
var knownTools = []string{"agy", "claude", "docker", "kubectl", "limactl", "ollama", "osascript", "podman", "shortcuts", "xcodebuild"}

// agyLoop refreshes /v1/antigravity. `agy models` goes to the network and
// takes seconds, and the answer changes when agy is upgraded, not every two
// seconds -- so once at start and then every ten minutes.
func (s *Sampler) agyLoop(ctx context.Context) {
	for ctx.Err() == nil {
		ag := s.readAntigravity(ctx)
		s.mu.Lock()
		s.antigravity = ag
		s.mu.Unlock()
		sleep(ctx, 10*time.Minute)
	}
}

func (s *Sampler) readAntigravity(ctx context.Context) metrics.Antigravity {
	empty := metrics.Antigravity{Models: []metrics.AgyModel{}, Agents: []string{}}
	ver, stderr, err := runToolWithin(ctx, 30*time.Second, "agy", "--version")
	if err != nil {
		empty.Reason = toolReason("agy", stderr, err)
		return empty
	}
	out := metrics.Antigravity{Available: true, Version: strings.TrimSpace(ver), Models: []metrics.AgyModel{}, Agents: []string{}}
	if mo, _, err := runToolWithin(ctx, 30*time.Second, "agy", "models"); err == nil {
		out.Models = metrics.ParseAgyModels(mo)
	}
	if ao, _, err := runToolWithin(ctx, 30*time.Second, "agy", "agents"); err == nil {
		out.Agents = metrics.ParseAgyAgents(ao)
	}
	return out
}

// readOllama asks for the installed models and the loaded ones. `ollama
// list` fails when the daemon is not running, and that failure IS the
// answer: available:false with ollama's own message.
func (s *Sampler) readOllama(ctx context.Context) metrics.Ollama {
	stdout, stderr, err := runTool(ctx, "ollama", "list")
	if err != nil {
		return metrics.Ollama{Reason: toolReason("ollama", stderr, err), Models: []metrics.OllamaModel{}, Running: []metrics.OllamaLoaded{}}
	}
	models, err := metrics.ParseOllamaList(stdout)
	if err != nil {
		return metrics.Ollama{Reason: err.Error(), Models: []metrics.OllamaModel{}, Running: []metrics.OllamaLoaded{}}
	}
	running := []metrics.OllamaLoaded{}
	if psOut, _, err := runTool(ctx, "ollama", "ps"); err == nil {
		if r, err := metrics.ParseOllamaPs(psOut); err == nil {
			running = r
		}
	}
	return metrics.Ollama{Available: true, Models: models, Running: running}
}

func (s *Sampler) readVMs(ctx context.Context) metrics.VMs {
	stdout, stderr, err := runTool(ctx, "limactl", "list", "--json")
	if err != nil {
		return metrics.VMs{Reason: toolReason("limactl", stderr, err), VMs: []metrics.VM{}}
	}
	vms, err := metrics.ParseLimaList(stdout)
	if err != nil {
		return metrics.VMs{Reason: err.Error(), VMs: []metrics.VM{}}
	}
	return metrics.VMs{Available: true, VMs: vms}
}

// readContainers asks docker, then podman.
//
// Order matters and the fallback is deliberate: on a machine with both, the
// one whose daemon is actually up is the one worth reporting, and "docker is
// down" is not the answer when podman is running the containers. The reason
// returned when both fail is docker's, because that is the one nearly
// everyone means.
func (s *Sampler) readContainers(ctx context.Context) metrics.Containers {
	empty := []metrics.Container{}
	dockerOut, dockerStderr, dockerErr := runTool(ctx, "docker", "ps", "--format", "{{json .}}")
	if dockerErr == nil {
		cs, err := metrics.ParseDockerPS(dockerOut)
		if err != nil {
			return metrics.Containers{Reason: err.Error(), Containers: empty}
		}
		return metrics.Containers{Available: true, Runtime: "docker", Containers: cs}
	}

	if podmanOut, _, err := runTool(ctx, "podman", "ps", "--format", "json"); err == nil {
		if cs, err := metrics.ParsePodmanPS(podmanOut); err == nil {
			return metrics.Containers{Available: true, Runtime: "podman", Containers: cs}
		}
	}
	return metrics.Containers{Reason: toolReason("docker", dockerStderr, dockerErr), Containers: empty}
}

func (s *Sampler) readK8s(ctx context.Context) metrics.K8s {
	if s.kubeContext == "" {
		return metrics.K8s{Reason: notConfiguredKube, Nodes: []metrics.Node{}}
	}
	args := []string{}
	if s.kubeconfig != "" {
		args = append(args, "--kubeconfig", s.kubeconfig)
	}
	args = append(args, "--context", s.kubeContext, "get", "nodes", "-o", "json")
	stdout, stderr, err := runTool(ctx, "kubectl", args...)
	if err != nil {
		return metrics.K8s{Context: s.kubeContext, Reason: toolReason("kubectl", stderr, err), Nodes: []metrics.Node{}}
	}
	nodes, err := metrics.ParseKubectlNodes(stdout)
	if err != nil {
		return metrics.K8s{Context: s.kubeContext, Reason: err.Error(), Nodes: []metrics.Node{}}
	}
	return metrics.K8s{Available: true, Context: s.kubeContext, Nodes: nodes}
}

// toolReason turns a failed command into a sentence worth showing on a
// phone. The tool's own first stderr line when it produced one -- "Cannot
// connect to the Docker daemon" says exactly what to do -- and otherwise
// the exec error, which is what "not installed" looks like.
func toolReason(name, stderr string, err error) string {
	if line := firstLine(stderr); line != "" {
		return line
	}
	if strings.Contains(err.Error(), "executable file not found") {
		return name + " is not installed"
	}
	return name + ": " + err.Error()
}

// readSessions lists the Claude Code projects with a transcript touched in
// the last sessionWindow, newest first, and counts the live `claude`
// processes.
//
// The two numbers answer different questions and neither substitutes for the
// other: a session waiting at a prompt has an old transcript and a live
// process; a session that just exited has a fresh transcript and none.
func (s *Sampler) readSessions(ctx context.Context) metrics.Sessions {
	out := metrics.Sessions{Sessions: []metrics.Session{}}
	if ps, err := run(ctx, "ps", "-Axo", "comm="); err == nil {
		out.RunningProcesses = metrics.CountProcessesNamed(ps, "claude")
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return out
	}
	root := filepath.Join(home, ".claude", "projects")
	entries, err := os.ReadDir(root)
	if err != nil {
		// No ~/.claude/projects at all: Claude Code has never run here.
		// Zero sessions is the truth, not a failure.
		return out
	}
	cutoff := time.Now().Add(-sessionWindow)
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		dir := filepath.Join(root, e.Name())
		// One level only, matching the contract: the per-session subagent
		// transcripts nested below would each report as their own project.
		files, err := filepath.Glob(filepath.Join(dir, "*.jsonl"))
		if err != nil {
			continue
		}
		var newest time.Time
		var newestFile string
		for _, f := range files {
			fi, err := os.Stat(f)
			if err != nil {
				continue
			}
			if fi.ModTime().After(newest) {
				newest = fi.ModTime()
				newestFile = f
			}
		}
		if newest.Before(cutoff) {
			continue
		}
		// The transcript's own cwd is the truth; the dir name is a lossy
		// fallback for a transcript with no cwd in its first 8 KiB.
		project := ""
		if fh, err := os.Open(newestFile); err == nil {
			buf := make([]byte, 8192)
			n, _ := fh.Read(buf)
			fh.Close()
			project = metrics.CwdFromTranscript(string(buf[:n]))
		}
		if project == "" {
			project = metrics.ProjectFromDirName(e.Name())
		}
		out.Sessions = append(out.Sessions, metrics.Session{
			Project:    project,
			LastActive: newest,
			Path:       dir,
		})
	}
	sort.Slice(out.Sessions, func(i, j int) bool {
		return out.Sessions[i].LastActive.After(out.Sessions[j].LastActive)
	})
	return out
}

// unavailable is the honest list. Each of these needs root (powermetrics) or
// an SMC reader that ships with neither macOS nor this agent. They are named
// so a client can render "not available" rather than a blank or a guess.
var unavailable = map[string]string{
	"soc_temperature_c": "needs root (powermetrics) or an SMC reader; the battery sensor is in battery.temperature_c",
	"fan_rpm":           "needs an SMC reader",
	"gpu_percent":       "needs root (powermetrics)",
	"ane_percent":       "needs root (powermetrics)",
	"soc_power_watts":   "needs root (powermetrics); ops/macos-power-agent pushes this to Prometheus",
}

func sleep(ctx context.Context, d time.Duration) {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
	case <-t.C:
	}
}
