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
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/VitruvianSoftware/vitruvian-core/apps/mobile/android-remote/macagent/metrics"
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

	// The v1.2 readings. Each on its own clock, because their costs differ
	// by two orders of magnitude: a transcript tail is a 64 KiB read every
	// five seconds, and a PR refresh is twenty-one gh calls to github.com.
	claude metrics.ClaudeSessions
	prs    metrics.PRs
	argo   metrics.ArgoApps

	// The transition memory behind the notifications. A notification is
	// worth sending when a session ENTERS a state, not for every tick it
	// spends there, so the previous value has to be kept somewhere.
	prevSessionState map[string]string
	prevPRVerdict    map[string]string

	// notifier is never nil; an unconfigured one is a working no-op, so the
	// sampler can call it unconditionally.
	notifier *Notifier
	// ghExtraRepos are the repos from --gh-extra-repos, whose open PRs are
	// listed whoever wrote them.
	ghExtraRepos []string

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

func NewSampler(interval time.Duration, kubeconfig, kubeContext string, ghExtraRepos []string, notifier *Notifier) *Sampler {
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
	if notifier == nil {
		notifier = NewNotifier("", "", "")
	}
	return &Sampler{
		interval:         interval,
		kubeconfig:       kubeconfig,
		kubeContext:      kubeContext,
		ghExtraRepos:     ghExtraRepos,
		notifier:         notifier,
		processes:        metrics.Processes{Processes: []metrics.Process{}},
		vms:              metrics.VMs{Reason: notYet, VMs: []metrics.VM{}},
		container:        metrics.Containers{Reason: notYet, Containers: []metrics.Container{}},
		k8s:              metrics.K8s{Reason: kubeReason, Context: kubeContext, Nodes: []metrics.Node{}},
		sessions:         metrics.Sessions{Sessions: []metrics.Session{}},
		claude:           metrics.ClaudeSessions{Sessions: []metrics.ClaudeSession{}},
		prs:              metrics.PRs{Reason: notYet, PRs: []metrics.PR{}},
		argo:             metrics.ArgoApps{Reason: kubeReason, Apps: []metrics.ArgoApp{}},
		prevSessionState: map[string]string{},
		prevPRVerdict:    map[string]string{},
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

func (s *Sampler) ClaudeSessions() metrics.ClaudeSessions {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.claude
}

func (s *Sampler) PRs() metrics.PRs {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.prs
}

func (s *Sampler) ArgoCD() metrics.ArgoApps {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.argo
}

// Notifier is how the act handlers reach the push channel: a streamed exec
// that finishes while the phone is asleep is the third of the five events in
// the contract, and it happens in an HTTP handler, not in a sampler tick.
func (s *Sampler) Notifier() *Notifier { return s.notifier }

// Run blocks until ctx is cancelled. Several loops, each on its own clock,
// because the readings cost wildly different amounts: the fast commands on
// the configured interval, top on its own because it paces itself, the
// optional tools on theirs, agy every ten minutes because it goes to the
// network, Claude transcripts every five seconds because that is the one a
// person is actually waiting on, and gh every sixty because twenty-one calls
// to github.com per refresh is not something to do more often.
func (s *Sampler) Run(ctx context.Context) {
	s.readHost(ctx)
	go s.cpuLoop(ctx)
	go s.toolsLoop(ctx)
	go s.agyLoop(ctx)
	go s.claudeLoop(ctx)
	go s.prsLoop(ctx)
	// The hostname is read by readHost above, so this is the first moment
	// there is anything to say. "Agent online" is worth one notification
	// because the common cause of silence is an agent that never started.
	go s.notifier.notify(ctx, "agent:start", "Agent online", s.Host().Hostname, "low", "computer", "vitruvian-remote://mac")
	s.fastLoop(ctx)
}

// claudeSessionWindow is how stale a transcript may be and still be listed.
//
// Wider than sessionWindow (30 min) on purpose: a session parked on a
// permission prompt stopped writing at the moment it asked, so the thirty
// minute window would drop exactly the session the phone exists to show.
// Four hours covers a working afternoon.
const claudeSessionWindow = 4 * time.Hour

// transcriptTail is how much of a transcript is read. The contract's number.
// A day of work is tens of megabytes; the state is decided by the last few
// records, and 64 KiB reaches back past a long tool result to find them.
const transcriptTail = 64 << 10

func (s *Sampler) claudeLoop(ctx context.Context) {
	for ctx.Err() == nil {
		sessions := s.readClaudeSessions()
		s.mu.Lock()
		s.claude = sessions
		s.mu.Unlock()
		s.notifySessionTransitions(ctx, sessions)
		sleep(ctx, 5*time.Second)
	}
}

// readClaudeSessions finds the newest transcript per project, reads its tail
// and asks the parser what that session is doing.
//
// Only the tail is read, with a seek: these files reach hundreds of megabytes
// on a long project, and reading one in full every five seconds would be a
// bigger load than everything else this agent does put together.
func (s *Sampler) readClaudeSessions() metrics.ClaudeSessions {
	out := metrics.ClaudeSessions{Sessions: []metrics.ClaudeSession{}}
	home, err := os.UserHomeDir()
	if err != nil {
		return out
	}
	root := filepath.Join(home, ".claude", "projects")
	entries, err := os.ReadDir(root)
	if err != nil {
		// Claude Code has never run here. Zero sessions is the truth.
		return out
	}
	now := time.Now()
	cutoff := now.Add(-claudeSessionWindow)
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		dir := filepath.Join(root, e.Name())
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
				newest, newestFile = fi.ModTime(), f
			}
		}
		if newestFile == "" || newest.Before(cutoff) {
			continue
		}
		state := metrics.ParseTranscriptTail(readTail(newestFile, transcriptTail), now)
		project := state.Cwd
		if project == "" {
			project = metrics.ProjectFromDirName(e.Name())
		}
		lastActive := state.LastActive
		if lastActive.IsZero() {
			// No parseable timestamp in the tail: the file's own mtime is
			// the fallback, and it is close enough to be useful.
			lastActive = newest
		}
		out.Sessions = append(out.Sessions, metrics.ClaudeSession{
			// The filename stem IS the session id -- it is what
			// `claude --resume` takes -- so nothing has to be parsed out of
			// the records to get it.
			SessionID:  strings.TrimSuffix(filepath.Base(newestFile), ".jsonl"),
			Project:    project,
			Cwd:        state.Cwd,
			Path:       newestFile,
			LastActive: lastActive,
			State:      state.State,
			LastRole:   state.LastRole,
			LastText:   state.LastText,
			LastTool:   state.LastTool,
		})
	}
	sort.Slice(out.Sessions, func(i, j int) bool {
		return out.Sessions[i].LastActive.After(out.Sessions[j].LastActive)
	})
	return out
}

// readTail returns the last n bytes of a file, or "" if it cannot be read.
// The first line of the result is almost always a fragment; the parser is
// built to drop it.
func readTail(path string, n int64) string {
	fh, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer fh.Close()
	fi, err := fh.Stat()
	if err != nil {
		return ""
	}
	if fi.Size() > n {
		if _, err := fh.Seek(-n, io.SeekEnd); err != nil {
			return ""
		}
	}
	b, err := io.ReadAll(io.LimitReader(fh, n))
	if err != nil {
		return ""
	}
	return string(b)
}

// notifySessionTransitions sends the two Claude Code notifications, on the
// TRANSITION into a state rather than for each tick spent in it. A session
// waiting for permission is one notification; the same session still waiting
// four seconds later is not news.
func (s *Sampler) notifySessionTransitions(ctx context.Context, sessions metrics.ClaudeSessions) {
	if !s.notifier.Configured() {
		return
	}
	s.mu.Lock()
	prev := s.prevSessionState
	next := make(map[string]string, len(sessions.Sessions))
	for _, sess := range sessions.Sessions {
		next[sess.SessionID] = sess.State
	}
	s.prevSessionState = next
	s.mu.Unlock()

	for _, sess := range sessions.Sessions {
		was := prev[sess.SessionID]
		if was == sess.State {
			continue
		}
		project := filepath.Base(sess.Project)
		switch sess.State {
		case metrics.StateWaitingForPermission:
			// High priority: this one is a person blocked on a tap.
			// "may be": the transcript cannot tell a permission prompt from a
			// long command, and a push that claims certainty it does not have
			// gets muted within a day.
			s.notifier.notify(ctx, "claude:"+sess.SessionID+":permission",
				"Claude Code may be waiting", project+" · "+sess.LastTool+" · no result for 90 s",
				"high", "raised_hand", "vitruvian-remote://sessions")
		case metrics.StateIdle:
			// Only from working. Idle straight from unknown is a session
			// that was already finished when the agent started, and
			// announcing it would mean a burst of stale news at every boot.
			if was != metrics.StateWorking {
				continue
			}
			s.notifier.notify(ctx, "claude:"+sess.SessionID+":idle",
				"Claude Code finished a turn", project+" · "+metrics.TrimRunes(sess.LastText, 120),
				"default", "white_check_mark", "vitruvian-remote://sessions")
		}
	}
}

// prsLoop refreshes /v1/prs every sixty seconds. Its own goroutine and its
// own clock: one refresh is a search plus one `gh pr view` per PR, each a
// round trip to github.com, and on a slow connection the whole pass can take
// most of a minute.
func (s *Sampler) prsLoop(ctx context.Context) {
	for ctx.Err() == nil {
		prs := s.readPRs(ctx)
		s.mu.Lock()
		s.prs = prs
		s.mu.Unlock()
		s.notifyPRTransitions(ctx, prs)
		sleep(ctx, 60*time.Second)
	}
}

func (s *Sampler) readPRs(ctx context.Context) metrics.PRs {
	empty := []metrics.PR{}
	// @me rather than a username: gh resolves it against whoever is logged
	// in, so the agent never has to be told who its owner is.
	refs, reason := s.searchPRs(ctx, ghSearchArgv("@me"))
	if reason != "" {
		return metrics.PRs{Reason: reason, PRs: empty}
	}
	for _, repo := range s.ghExtraRepos {
		extra, _ := s.searchPRs(ctx, ghSearchRepoArgv(repo))
		refs = append(refs, extra...)
	}

	seen := map[string]bool{}
	out := make([]metrics.PR, 0, len(refs))
	for _, ref := range refs {
		// A PR can arrive twice: once as the caller's own and once through
		// an extra repo that is also theirs.
		id := fmt.Sprintf("%s#%d", ref.Repo, ref.Number)
		if seen[id] {
			continue
		}
		seen[id] = true

		pr := metrics.PR{Repo: ref.Repo, Number: ref.Number, Title: ref.Title, URL: ref.URL, UpdatedAt: ref.UpdatedAt}
		stdout, _, err := runToolWithin(ctx, 20*time.Second, "gh", ghViewArgv(ref.Repo, ref.Number)...)
		if err == nil {
			if detail, perr := metrics.ParseGhPrView(stdout); perr == nil {
				// The search row owns identity, the view owns state. Merged
				// this way round so a view that half-failed cannot blank out
				// the title and URL.
				detail.Repo, detail.Number, detail.Title, detail.URL, detail.UpdatedAt = pr.Repo, pr.Number, pr.Title, pr.URL, pr.UpdatedAt
				pr = detail
			}
		}
		out = append(out, pr)
	}
	return metrics.PRs{Available: true, SampledAt: time.Now(), PRs: out}
}

// searchPRs runs one gh search and returns its rows, or the reason it could
// not. gh's own message is the reason -- "gh auth login" is the next step and
// nothing this agent writes says it better.
func (s *Sampler) searchPRs(ctx context.Context, args []string) ([]metrics.PRRef, string) {
	stdout, stderr, err := runToolWithin(ctx, 30*time.Second, "gh", args...)
	if err != nil {
		return nil, toolReason("gh", stderr, err)
	}
	refs, err := metrics.ParseGhSearchPrs(stdout)
	if err != nil {
		return nil, err.Error()
	}
	return refs, ""
}

// notifyPRTransitions fires when a PR's checks settle, in either direction.
// Only on the change: a PR that has been green for a day is not news, and a
// notification per poll is how a person learns to swipe them away unread.
func (s *Sampler) notifyPRTransitions(ctx context.Context, prs metrics.PRs) {
	if !s.notifier.Configured() || !prs.Available {
		return
	}
	s.mu.Lock()
	prev := s.prevPRVerdict
	next := make(map[string]string, len(prs.PRs))
	for _, pr := range prs.PRs {
		next[fmt.Sprintf("%s#%d", pr.Repo, pr.Number)] = metrics.PRChecksVerdict(pr.Checks)
	}
	s.prevPRVerdict = next
	s.mu.Unlock()

	for _, pr := range prs.PRs {
		id := fmt.Sprintf("%s#%d", pr.Repo, pr.Number)
		verdict := metrics.PRChecksVerdict(pr.Checks)
		if verdict == "" || prev[id] == verdict {
			continue
		}
		// A PR seen for the first time in a settled state is not announced:
		// on the first pass after a restart that would be one notification
		// per open PR.
		if _, known := prev[id]; !known {
			continue
		}
		title, tag, prio := "PR #"+strconv.Itoa(pr.Number)+" checks green", "white_check_mark", "default"
		if verdict == "red" {
			title, tag, prio = "PR #"+strconv.Itoa(pr.Number)+" checks failed", "x", "high"
		}
		s.notifier.notify(ctx, "pr:"+id+":"+verdict, title, pr.Title, prio, tag, "vitruvian-remote://prs")
	}
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
		// Pause between samples. Back-to-back `top -l 2` kept a top process
		// alive almost continuously, and it showed up in the agent's own
		// process list at ~28% CPU -- a cost the phone was paying to watch
		// the Mac. One sample per interval is plenty for a gauge.
		sleep(ctx, s.interval)
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
	argo := s.readArgoCD(ctx)
	tools := toolPresence(knownTools)

	s.mu.Lock()
	s.tools = tools
	if procs != nil {
		s.processes = metrics.Processes{SampledAt: time.Now(), Processes: procs}
	}
	s.vms, s.container, s.k8s, s.sessions, s.ollama, s.argo = vms, containers, k8s, sessions, ollama, argo
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

// readArgoCD lists the cluster's ArgoCD Applications. Same flags and same
// "not configured" answer as /v1/k8s: without --kube-context the agent has
// no cluster to ask, and guessing at kubectl's current context would let a
// phone sync a production app because someone ran a kubectl command on
// Tuesday.
//
// A longer bound than the other tools: the lab cluster's answer is two
// megabytes, nearly all of it the per-app resource inventory this drops, and
// on a slow link the five second bound was the thing that failed.
func (s *Sampler) readArgoCD(ctx context.Context) metrics.ArgoApps {
	if s.kubeContext == "" {
		return metrics.ArgoApps{Reason: notConfiguredKube, Apps: []metrics.ArgoApp{}}
	}
	args := kubectlArgs(s.kubeconfig, s.kubeContext, "get", "applications", "-A", "-o", "json")
	stdout, stderr, err := runToolWithin(ctx, 20*time.Second, "kubectl", args...)
	if err != nil {
		return metrics.ArgoApps{Reason: toolReason("kubectl", stderr, err), Apps: []metrics.ArgoApp{}}
	}
	apps, err := metrics.ParseArgoApps(stdout)
	if err != nil {
		return metrics.ArgoApps{Reason: err.Error(), Apps: []metrics.ArgoApp{}}
	}
	return metrics.ArgoApps{Available: true, Apps: apps}
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
