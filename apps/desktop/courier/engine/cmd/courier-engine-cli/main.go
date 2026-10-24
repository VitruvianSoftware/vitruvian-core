// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// courier-engine-cli drives the engine by hand: link any network, list chats, watch and send.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"time"

	"github.com/rs/zerolog"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/datadir"
	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/login"
	"github.com/VitruvianSoftware/courier/engine/internal/logscrub"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/networks"
	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// loginWait is how long send waits for a linked network to finish logging in before giving up.
const loginWait = 30 * time.Second

// errNotConnected means a linked network never became logged in, so nothing was queued.
var errNotConnected = actions.ErrNotConnected

const usage = "usage: courier-engine-cli [--data DIR] [--network NAME --flow ID] link|chats|tail|send <room-id> <text>"

// args is the parsed command line. network and flow only apply to link.
type args struct{ data, network, flow, cmd, room, text string }

// linkWarnings are questions asked, and which must be answered yes, before linking a network.
var linkWarnings = map[string]string{
	"gmessages": "Google Messages allows one web session. Linking here disconnects it in Beeper. Continue?",
}

func defaultDataDir(home string, homeErr error) (string, error) {
	if homeErr != nil || home == "" {
		return "", fmt.Errorf("cannot find your home directory (%v): pass --data DIR", homeErr)
	}
	return filepath.Join(home, "Library", "Application Support", "Courier-m1"), nil
}

func networkNames() string {
	var names []string
	for _, n := range networks.All() {
		names = append(names, n.Name)
	}
	return strings.Join(names, ", ")
}

func parseArgs(argv []string) (args, error) {
	fs := flag.NewFlagSet("courier-engine-cli", flag.ContinueOnError)
	data := fs.String("data", "", "data directory (default ~/Library/Application Support/Courier-m1)")
	network := fs.String("network", "", "network to link (link only): "+networkNames())
	flow := fs.String("flow", "", "login flow to use (link only; default: the network's first flow)")
	if err := fs.Parse(argv); err != nil {
		return args{}, err
	}
	dataSet := false
	fs.Visit(func(f *flag.Flag) { dataSet = dataSet || f.Name == "data" })
	if dataSet && *data == "" {
		return args{}, errors.New("--data must not be empty")
	}
	if !dataSet {
		home, herr := os.UserHomeDir()
		dir, err := defaultDataDir(home, herr)
		if err != nil {
			return args{}, err
		}
		*data = dir
	}
	rest := fs.Args()
	if len(rest) == 0 {
		return args{}, errors.New(usage)
	}
	a := args{data: *data, cmd: rest[0]}
	if a.cmd != "link" && (*network != "" || *flow != "") {
		return args{}, errors.New("--network and --flow only apply to link: chats, tail and send run every network")
	}
	switch a.cmd {
	case "link":
		// No default network: a QR code must never be shown for the wrong app.
		if *network == "" {
			return args{}, fmt.Errorf("link needs --network NAME (one of: %s)", networkNames())
		}
		n, ok := networks.Get(*network)
		if !ok {
			return args{}, fmt.Errorf("unknown network %q (one of: %s)", *network, networkNames())
		}
		if *flow != "" && !slices.Contains(n.Flows, *flow) {
			return args{}, fmt.Errorf("%s has no login flow %q (one of: %s)", n.Name, *flow, strings.Join(n.Flows, ", "))
		}
		a.network, a.flow = n.Name, *flow
	case "chats", "tail":
	case "send":
		if len(rest) < 3 {
			return args{}, errors.New("send needs <room-id> <text>")
		}
		a.room, a.text = rest[1], strings.Join(rest[2:], " ")
		if strings.TrimSpace(a.text) == "" {
			return args{}, errors.New("send needs non-empty text")
		}
	default:
		return args{}, fmt.Errorf("unknown command %q", a.cmd)
	}
	return a, nil
}

func main() {
	a, err := parseArgs(os.Args[1:])
	if err != nil {
		if !errors.Is(err, flag.ErrHelp) {
			fmt.Fprintln(os.Stderr, err)
		}
		os.Exit(2)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	releaseSignalWhenDone(ctx, stop)
	if err = run(ctx, a); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		stop()
		os.Exit(1)
	}
}

// releaseSignalWhenDone hands Ctrl-C back to Go's default handler once the first one has been caught, so a
// second Ctrl-C ends the process at once if shutting down (engine, then store, then the data-dir lock) hangs.
func releaseSignalWhenDone(ctx context.Context, stop context.CancelFunc) {
	go func() {
		<-ctx.Done()
		stop()
	}()
}

func run(ctx context.Context, a args) error {
	if err := sqlite.PrivateDir(a.data); err != nil {
		return err
	}
	unlock, err := datadir.Lock(a.data)
	if err != nil {
		return err
	}
	defer unlock()
	log := newLog(os.Stderr)
	s, err := store.Open(filepath.Join(a.data, "courier.db"))
	if err != nil {
		return err
	}
	defer s.Close()
	// link needs only the network being linked; everything else runs every network.
	nets := networks.All()
	var target networks.Network
	if a.cmd == "link" {
		target, _ = networks.Get(a.network)
		nets = []networks.Network{target}
	}
	eng, errs := networks.Start(ctx, a.data, s, &media.Store{Dir: filepath.Join(a.data, "media")}, nets, log)
	defer eng.Stop()
	reportNotStarted(os.Stderr, errs)
	switch a.cmd {
	case "link":
		linked, err := link(ctx, eng, target, a.flow, newTerminalPrompter(ctx, os.Stdin, os.Stdout), os.Stdout)
		if err != nil || !linked {
			return err
		}
		fmt.Printf("Linked to %s. Leave this running a minute so history backfills, then Ctrl-C.\n", target.DisplayName)
		<-ctx.Done()
		return nil
	case "chats":
		rooms, err := s.ListRooms(ctx)
		for _, r := range rooms {
			fmt.Printf("%s\t%s\n", r.ID, r.Name)
		}
		return err
	case "tail":
		return tail(ctx, s)
	case "send":
		return send(ctx, eng, s, a, loginWait)
	}
	return nil
}

// newLog is the CLI's logger, which every bridge logs through: warnings and errors, for a person, on w. Like the
// engine's, it keeps only what can't name anyone (logscrub), before the console writer formats it.
func newLog(w io.Writer) zerolog.Logger {
	return zerolog.New(logscrub.New(zerolog.ConsoleWriter{Out: w})).Level(zerolog.WarnLevel).With().Timestamp().Logger()
}

// reportNotStarted prints one line per network that did not start.
func reportNotStarted(w io.Writer, errs map[string]error) {
	names := make([]string, 0, len(errs))
	for name := range errs {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		fmt.Fprintf(w, "%s: not started — %v\n", name, errs[name])
	}
}

// waitForLogin waits for a linked network to finish logging in; see actions.WaitForLogin.
func waitForLogin(ctx context.Context, h *host.Host, timeout time.Duration) error {
	return actions.WaitForLogin(ctx, h, timeout)
}

// ensureNotLinked refuses to link when the network already has a login: a second run would link a second
// device and orphan the first, which would stay listed in the network's linked devices.
func ensureNotLinked(ctx context.Context, h *host.Host, displayName string) error {
	me, err := h.Me(ctx)
	if err != nil {
		return err
	}
	if len(me.GetUserLogins()) > 0 {
		return fmt.Errorf("already linked to %s — unlink this device in that app first, or use a fresh --data dir", displayName)
	}
	return nil
}

// send queues a text message in a room, through the bridge of the network the room belongs to, and waits to
// hear what became of it. The CLI has no timer loop to send a message that waits for its network, so it waits for
// the chat's own login first, up to loginTimeout, and refuses with nothing stored when it doesn't come.
func send(ctx context.Context, eng *engine.Engine, s *store.Store, a args, loginTimeout time.Duration) error {
	act := actions.New(eng, s, nil) // text only: no media store needed
	act.LoginWait = loginTimeout
	if err := act.WaitForChat(ctx, a.room); err != nil {
		return err
	}
	eventID, err := act.SendText(ctx, a.room, a.text, "")
	if err != nil {
		return err
	}
	return waitStatus(ctx, s, eventID, 30*time.Second)
}

// link signs in to one network and reports whether it did. Declining a warning is not an error; it just
// links nothing. flow "" means the network's first flow.
func link(ctx context.Context, eng *engine.Engine, n networks.Network, flow string, p prompter, out io.Writer) (bool, error) {
	h, ok := eng.Host(n.Name)
	if !ok {
		return false, fmt.Errorf("%s is not running", n.DisplayName)
	}
	if err := ensureNotLinked(ctx, h, n.DisplayName); err != nil {
		return false, err
	}
	if flow == "" {
		if len(n.Flows) == 0 {
			return false, fmt.Errorf("%s has no login flow", n.DisplayName)
		}
		flow = n.Flows[0]
	}
	if question, ok := linkWarnings[n.Name]; ok {
		yes, err := p.Confirm(question)
		if err != nil {
			return false, err
		}
		if !yes {
			fmt.Fprintln(out, "Not linking.")
			return false, nil
		}
	}
	// The driver is the same one the app uses. It has no store here, so a network with an account counts as
	// linked whatever state it is in: relinking a signed-out account is the app's Reconnect, not this CLI's.
	d := login.NewDriver(eng, nil, func(name string) ([]string, bool) { return n.Flows, name == n.Name })
	d.IdleTimeout = -1
	step, err := d.Start(ctx, n.Name, flow)
	if err = walkSteps(ctx, d, step, err, p, out); err != nil {
		return false, err
	}
	return true, nil
}

func tail(ctx context.Context, s *store.Store) error {
	feed, cancel := s.Subscribe()
	defer cancel()
	fmt.Println("Waiting for messages. Ctrl-C to stop.")
	for {
		select {
		case <-ctx.Done():
			return nil
		case c := <-feed:
			if c.Kind != "event" {
				continue
			}
			e, ok, err := s.GetEvent(ctx, c.EventID)
			if err != nil || !ok || e.Type != event.EventMessage.Type {
				continue
			}
			var body struct {
				Body string `json:"body"`
			}
			_ = json.Unmarshal(e.Content, &body)
			fmt.Printf("%s  %s  %s: %s\n", e.TS.Format(time.Kitchen), e.RoomID, e.Sender, body.Body)
		}
	}
}

// waitStatus waits for the bridge to report what happened to a queued message.
// The message was already handed to the bridge, so if we stop waiting (timeout
// or Ctrl-C) it may still reach the contact: say so, and leave it pending.
func waitStatus(ctx context.Context, s *store.Store, eventID string, timeout time.Duration) error {
	unknown := fmt.Errorf("delivery unknown — check your phone before resending (event %s left pending)", eventID)
	deadline := time.After(timeout)
	for {
		// Read with an uncancelled context so a status that already landed is not lost to Ctrl-C.
		e, _, err := s.GetEvent(context.WithoutCancel(ctx), eventID)
		if err != nil {
			return err
		}
		switch e.Status {
		case "sent":
			fmt.Println("status: sent")
			return nil
		case "failed":
			return fmt.Errorf("message failed: %s", e.StatusReason)
		}
		select {
		case <-ctx.Done():
			return unknown
		case <-deadline:
			return unknown
		case <-time.After(200 * time.Millisecond):
		}
	}
}
