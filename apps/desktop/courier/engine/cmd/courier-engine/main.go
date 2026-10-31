// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// courier-engine is the helper the Courier app runs: it serves the app protocol on a Unix socket in the data
// directory as soon as its store is open, and starts every network's bridge over that store behind it.
//
// Standard output carries exactly one line, once the engine is serving:
//
//	{"ready":true,"socket":"/path/to/engine.sock","protocol":3}
//
// Standard error carries warnings and errors as JSON lines, and one info line when the history already on disk has
// been added to search ("search backfill done", counts and a duration); nothing is written to a log file, because
// a bridge's error can quote what was submitted. Every log line keeps only keys that can't name anyone, with
// identifiers in its message and error taken out (internal/logscrub). A fatal error is one plain line,
// "courier-engine: <message>", before the exit. Exit codes: 0 stopped cleanly, 2 usage, 3 another engine holds
// the data directory, 1 anything else.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime/debug"
	"syscall"
	"time"

	"github.com/rs/zerolog"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/datadir"
	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/entitlement"
	"github.com/VitruvianSoftware/courier/engine/internal/login"
	"github.com/VitruvianSoftware/courier/engine/internal/logscrub"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/networks"
	"github.com/VitruvianSoftware/courier/engine/internal/rpc"
	"github.com/VitruvianSoftware/courier/engine/internal/search"
	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
	"github.com/VitruvianSoftware/courier/engine/internal/timers"
)

// version is the engine's version, sent in hello. A build stamps it with Bazel's x_defs ("main.version").
var version = "dev"

const usage = "usage: courier-engine --data DIR [--parent-fd N]"

const (
	exitUsage  = 2
	exitLocked = 3
	exitFailed = 1
)

// socketName is the socket's name inside the data directory.
const socketName = "engine.sock"

// maxSocketPath is the longest socket path that fits: macOS's sun_path is 104 bytes, one of them the NUL.
const maxSocketPath = 103

// serveStopWait bounds how long shutdown waits for requests in flight (a send waiting on a phone, say).
const serveStopWait = 5 * time.Second

type config struct {
	data   string   // absolute
	parent *os.File // the inherited descriptor to watch; nil: no watchdog
	// nets is the networks run starts; nil is networks.All(). It is the seam a test uses to put in a network whose
	// start it controls (Ruling C31).
	nets []networks.Network
}

func main() {
	os.Exit(realMain(os.Args[1:], os.Stdout, os.Stderr))
}

func realMain(argv []string, stdout, stderr io.Writer) int {
	cfg, err := parseArgs(argv)
	if err != nil {
		if !errors.Is(err, flag.ErrHelp) {
			fmt.Fprintln(stderr, err)
		}
		fmt.Fprintln(stderr, usage)
		return exitUsage
	}
	if err = run(cfg, stdout, stderr); err != nil {
		fmt.Fprintln(stderr, logscrub.ScrubStartupError("courier-engine:", err))
		if errors.Is(err, datadir.ErrLocked) {
			return exitLocked
		}
		return exitFailed
	}
	return 0
}

func parseArgs(argv []string) (config, error) {
	fs := flag.NewFlagSet("courier-engine", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	data := fs.String("data", "", "data directory")
	parentFD := fs.Int("parent-fd", -1, "inherited file descriptor; the engine exits when it reaches end of file")
	if err := fs.Parse(argv); err != nil {
		return config{}, err
	}
	if fs.NArg() > 0 {
		return config{}, fmt.Errorf("unexpected argument %q", fs.Arg(0))
	}
	if *data == "" {
		return config{}, errors.New("--data DIR is required")
	}
	abs, err := filepath.Abs(*data)
	if err != nil {
		return config{}, err
	}
	cfg := config{data: abs}
	set := false
	fs.Visit(func(f *flag.Flag) { set = set || f.Name == "parent-fd" })
	if set {
		if cfg.parent, err = openParentFD(*parentFD); err != nil {
			return config{}, err
		}
	}
	return cfg, nil
}

// openParentFD returns the inherited descriptor n, or an error if n is not one the engine may watch.
func openParentFD(n int) (*os.File, error) {
	if n < 0 {
		return nil, fmt.Errorf("--parent-fd %d: not a file descriptor", n)
	}
	if n == 1 || n == 2 {
		return nil, fmt.Errorf("--parent-fd %d: that is the engine's own output", n)
	}
	f := os.NewFile(uintptr(n), "parent")
	if _, err := f.Stat(); err != nil {
		return nil, fmt.Errorf("--parent-fd %d: not an open file descriptor", n)
	}
	syscall.CloseOnExec(n) // nothing the engine starts may keep the pipe open
	return f, nil
}

type readyLine struct {
	Ready    bool   `json:"ready"`
	Socket   string `json:"socket"`
	Protocol int    `json:"protocol"`
}

func run(cfg config, stdout, stderr io.Writer) error {
	sock := filepath.Join(cfg.data, socketName)
	if len(sock) > maxSocketPath {
		return fmt.Errorf("the socket path %s is %d bytes, and a Unix socket path can be at most %d "+
			"(macOS's sun_path is 104 bytes, the last for a terminating NUL): use a shorter --data directory",
			sock, len(sock), maxSocketPath)
	}

	// From here a SIGTERM or SIGINT, or the app going away, ends the run cleanly, even mid-start-up.
	sigCtx, stopSignals := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stopSignals()
	ctx, cancel := context.WithCancel(sigCtx)
	defer cancel()
	if cfg.parent != nil {
		go func() {
			_, _ = io.Copy(io.Discard, cfg.parent) // returns at end of file or on error: the app is gone
			cancel()
		}()
	}
	go func() {
		// After the first signal the default handler takes the next, so a second Ctrl-C ends a stuck shutdown.
		<-ctx.Done()
		stopSignals()
	}()

	if err := sqlite.PrivateDir(cfg.data); err != nil {
		return err
	}
	unlock, err := datadir.Lock(cfg.data)
	if err != nil {
		return err
	}
	defer unlock()

	// Only now, holding the lock, is the socket ours to remove: no other engine can be using it.
	if err = removeStaleSocket(sock); err != nil {
		return err
	}
	ln, err := net.Listen("unix", sock)
	if err != nil {
		return fmt.Errorf("listen on %s: %w", sock, err)
	}
	defer os.Remove(sock)
	defer ln.Close()
	if err = os.Chmod(sock, 0o600); err != nil {
		return fmt.Errorf("secure %s: %w", sock, err)
	}

	// Every bridge logs through this logger (host.Start), and bridgev2 puts the chats and people it handles in its log
	// context: the log writer keeps only what can't name anyone (never log who). The fatal "courier-engine: ..." line
	// realMain prints is not a log line and doesn't go through it: the app reads it as it is written.
	rollingStderr, err := logscrub.OpenRollingFile(filepath.Join(cfg.data, "engine-stderr.log"), 0)
	if err != nil {
		return err
	}
	defer rollingStderr.Close()
	if f := rollingStderr.File(); f != nil {
		_ = debug.SetCrashOutput(f, debug.CrashOptions{})
		defer func() { _ = debug.SetCrashOutput(nil, debug.CrashOptions{}) }()
	}
	log := zerolog.New(logscrub.New(io.MultiWriter(stderr, rollingStderr))).Level(zerolog.WarnLevel).With().Timestamp().Logger()
	s, err := store.Open(filepath.Join(cfg.data, "courier.db"))
	if err != nil {
		return err
	}
	defer s.Close()
	// Sends the last engine was still waiting on when it stopped: it never heard back, and the bridges forgot them.
	// They become failed ("may have been sent") for the person to Retry or Delete; nothing is sent again unasked.
	// This is safe only here, holding the data directory's lock, before any bridge or client is running.
	if _, err = s.FailInterruptedSends(context.Background()); err != nil {
		return fmt.Errorf("mark interrupted sends: %w", err)
	}

	// Account spaces and a row's muted_by_name say "WhatsApp", not "whatsapp" (Ruling 5).
	all := cfg.nets
	if all == nil {
		all = networks.All()
	}
	s.SetNetworkNames(displayNames(all))

	// The loop and the protocol ask one provider which plan features are allowed.
	var ent entitlement.Provider = entitlement.Always{}
	tm := timers.New(s, ent, timers.RealClock{}, log)
	m := &media.Store{Dir: filepath.Join(cfg.data, "media")}
	s.SetMediaStore(m)
	actions.ConfigureFFmpeg(os.Stat, exec.LookPath)

	// The networks start behind the engine, after it is serving (below), so the app connects at once and each
	// network's chats show as its bridge becomes ready (spec §7). Every one of them is STARTING until then: their
	// names are known now, before any starts (Ruling C7). eng.Stop, deferred here, runs after everything else that
	// uses the bridges has stopped (defers run in reverse); it waits for a start still under way, then stops the bridges.
	eng := engine.New(s)
	defer eng.Stop()
	specs := networks.Specs(all)
	eng.Expect(specs)
	acts := newActions(eng, s, m, ent)
	// Typing still on its way to a bridge goes before the bridges stop (eng.Stop, deferred above, runs after this),
	// and nothing more is queued once it has. The wait is bounded: typing stuck behind a send in flight is freed only
	// by the bridges stopping.
	defer func() {
		if !acts.StopTyping(serveStopWait) {
			log.Warn().Dur("waited", serveStopWait).Msg("typing still on its way at shutdown; stopping anyway")
		}
	}()
	tm.SetDispatcher(acts)
	acts.Wake = tm.Poke // a message put back behind its chat's waiting ones goes on the loop's next run

	infos := make([]rpc.NetworkInfo, 0, len(all))
	for _, n := range all {
		infos = append(infos, rpc.NetworkInfo{Name: n.Name, DisplayName: n.DisplayName, Flows: n.Flows})
	}
	deps := rpc.Deps{
		Store:   s,
		Engine:  eng,
		Actions: acts,
		Login: login.NewDriver(eng, s, func(name string) ([]string, bool) {
			n, ok := networks.Get(name)
			return n.Flows, ok
		}),
		Media:       m,
		Search:      search.New(s),
		Timers:      tm,
		Entitlement: ent,
		Networks:    infos,
		Version:     version,
		DataDir:     cfg.data,
		Log:         log,
	}

	served := make(chan struct{})
	var serveErr error
	go func() {
		defer close(served)
		serveErr = rpc.Serve(ctx, ln, deps)
	}()
	if err = json.NewEncoder(stdout).Encode(readyLine{Ready: true, Socket: sock, Protocol: rpc.Protocol}); err != nil {
		cancel()
		<-served
		return fmt.Errorf("write the ready line: %w", err)
	}

	// Now the timer loop (reminders, auto-archive, the outbox, waiting messages and disappearing timers) and, beside
	// it, the networks, one after the other, each reporting STARTING, then its own states. The loop starts after
	// FailInterruptedSends, so a message it claims and makes pending is never mistaken for an interrupted send of the
	// last run. It needn't wait for the bridges (Ruling C5): a held or scheduled message due while its network is
	// still starting waits for it (HandOff), and each network's "bridge" changes wake the loop to send the messages
	// waiting for it once a login is in. The start stops at ctx's end, between networks (a start under way finishes:
	// the bridges outlive the signal, and eng.Stop stops them). Both are waited for, hand-offs and all, before the
	// bridges stop and the store closes (defers run in reverse): neither may touch them once they have gone.
	loopCtx, stopLoop := context.WithCancel(ctx)
	loopDone := make(chan struct{})
	go func() {
		defer close(loopDone)
		tm.Run(loopCtx)
	}()
	defer func() {
		stopLoop()
		<-loopDone
	}()
	startCtx, stopStart := context.WithCancel(ctx)
	startDone := make(chan struct{})
	go func() {
		defer close(startDone)
		eng.StartNetworks(startCtx, cfg.data, m, specs, log)
	}()
	defer func() {
		stopStart()
		<-startDone
	}()

	// History already on disk goes into the search index behind the engine, in short batches (at most 2,000 rows and
	// 50 ms each), each followed by a rest at least as long (search.RunBackfill): a big courier.db starts as fast
	// as an empty one, and new messages, indexed as they arrive, never wait long for a batch. It starts only now,
	// once the engine is serving, and like the timers it stops with the engine's context and is waited for before
	// the store closes (defers run in reverse). Its one line when done gives counts and a duration, at info: the
	// only line below warn that the engine writes.
	backfillCtx, stopBackfill := context.WithCancel(ctx)
	backfillDone := make(chan struct{})
	go func() {
		defer close(backfillDone)
		search.RunBackfill(backfillCtx, s, log.Level(zerolog.InfoLevel))
	}()
	defer func() {
		stopBackfill()
		<-backfillDone
	}()

	select {
	case <-ctx.Done():
		if !waitBounded(served, serveStopWait) {
			log.Warn().Dur("waited", serveStopWait).Msg("requests still in flight at shutdown; stopping anyway")
		}
	case <-served:
		if serveErr != nil {
			return fmt.Errorf("serve: %w", serveErr)
		}
	}
	return nil
}

// newActions is the engine's actions, asking ent, the provider the timer loop and the protocol ask, before a message is
// held for undo send or scheduled for later (Ruling 19). Without it Actions allows everything, and those two features
// would be free.
func newActions(eng *engine.Engine, s *store.Store, m *media.Store, ent entitlement.Provider) *actions.Actions {
	a := actions.New(eng, s, m)
	a.Entitlement = ent
	return a
}

// displayNames maps each network's name to its display name: whatsapp to WhatsApp.
func displayNames(all []networks.Network) map[string]string {
	out := make(map[string]string, len(all))
	for _, n := range all {
		out[n.Name] = n.DisplayName
	}
	return out
}

// removeStaleSocket removes what a crashed engine left at sock. Anything else at that path is not ours to delete.
func removeStaleSocket(sock string) error {
	fi, err := os.Lstat(sock)
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if fi.Mode()&os.ModeSocket == 0 {
		return fmt.Errorf("%s exists and is not a socket: remove it, or choose another --data directory", sock)
	}
	return os.Remove(sock)
}

// waitBounded reports whether done closed within d.
func waitBounded(done <-chan struct{}, d time.Duration) bool {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-done:
		return true
	case <-t.C:
		return false
	}
}
