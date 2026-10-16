// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// courier-engine-cli drives the milestone-1 engine by hand: link WhatsApp, list chats, watch and send.
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
	"strings"
	"time"

	"github.com/mdp/qrterminal/v3"
	"github.com/rs/zerolog"
	"go.mau.fi/mautrix-whatsapp/pkg/connector"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// loginWait is how long send waits for WhatsApp to finish logging in before giving up.
const loginWait = 30 * time.Second

// errNotConnected means the engine never became logged in to the network, so nothing was queued.
var errNotConnected = errors.New("not connected to WhatsApp yet — nothing was sent")

const usage = "usage: courier-engine-cli [--data DIR] link|chats|tail|send <room-id> <text>"

type args struct{ data, cmd, room, text string }

// bridgeCommandPrefix is the host's bridge command prefix ("!" + network name).
// A message body starting with it would be run as a bridge admin command.
const bridgeCommandPrefix = "!whatsapp"

func defaultDataDir(home string, homeErr error) (string, error) {
	if homeErr != nil || home == "" {
		return "", fmt.Errorf("cannot find your home directory (%v): pass --data DIR", homeErr)
	}
	return filepath.Join(home, "Library", "Application Support", "Courier-m1"), nil
}

func parseArgs(argv []string) (args, error) {
	fs := flag.NewFlagSet("courier-engine-cli", flag.ContinueOnError)
	data := fs.String("data", "", "data directory (default ~/Library/Application Support/Courier-m1)")
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
	switch a.cmd {
	case "link", "chats", "tail":
	case "send":
		if len(rest) < 3 {
			return args{}, errors.New("send needs <room-id> <text>")
		}
		a.room, a.text = rest[1], strings.Join(rest[2:], " ")
		if strings.TrimSpace(a.text) == "" {
			return args{}, errors.New("send needs non-empty text")
		}
		if strings.HasPrefix(strings.ToLower(strings.TrimSpace(a.text)), bridgeCommandPrefix) {
			return args{}, fmt.Errorf("refusing to send text starting with %s: the bridge would run it as an admin command", bridgeCommandPrefix)
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
	if err = run(ctx, a); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		stop()
		os.Exit(1)
	}
}

func run(ctx context.Context, a args) error {
	if err := sqlite.PrivateDir(a.data); err != nil {
		return err
	}
	unlock, err := lockDataDir(a.data)
	if err != nil {
		return err
	}
	defer unlock()
	log := zerolog.New(zerolog.ConsoleWriter{Out: os.Stderr}).Level(zerolog.WarnLevel).With().Timestamp().Logger()
	s, err := store.Open(filepath.Join(a.data, "courier.db"))
	if err != nil {
		return err
	}
	defer s.Close()
	h, err := host.Start(ctx, a.data, "whatsapp", s, &media.Store{Dir: filepath.Join(a.data, "media")}, &connector.WhatsAppConnector{}, log)
	if err != nil {
		return err
	}
	defer h.Stop()
	switch a.cmd {
	case "link":
		return link(ctx, h)
	case "chats":
		rooms, err := s.ListRooms(ctx)
		for _, r := range rooms {
			fmt.Printf("%s\t%s\n", r.ID, r.Name)
		}
		return err
	case "tail":
		return tail(ctx, s)
	case "send":
		return send(ctx, h, s, a, loginWait)
	}
	return nil
}

// waitForLogin waits until at least one of the local user's logins reports it is logged in. The bridge's Start
// only connects the logins: the connection counts as logged in a moment later, when the server's success
// message arrives. A message queued before then is refused as "not logged in" and marked failed.
func waitForLogin(ctx context.Context, h *host.Host, timeout time.Duration) error {
	me, err := h.Me(ctx)
	if err != nil {
		return err
	}
	deadline := time.After(timeout)
	for {
		for _, login := range me.GetUserLogins() {
			if login.Client != nil && login.Client.IsLoggedIn() {
				return nil
			}
		}
		select {
		case <-ctx.Done():
			return errNotConnected
		case <-deadline:
			return errNotConnected
		case <-time.After(200 * time.Millisecond):
		}
	}
}

// ensureNotLinked refuses to link when the data dir already has a login: a second run would link a second
// device and orphan the first, which would stay listed in WhatsApp's Linked devices.
func ensureNotLinked(ctx context.Context, h *host.Host) error {
	me, err := h.Me(ctx)
	if err != nil {
		return err
	}
	if len(me.GetUserLogins()) > 0 {
		return errors.New("already linked — unlink this device in WhatsApp → Linked devices first, or use a fresh --data dir")
	}
	return nil
}

func send(ctx context.Context, h *host.Host, s *store.Store, a args, loginTimeout time.Duration) error {
	// Wait before storing or queueing anything, so a refused send leaves no trace.
	if err := waitForLogin(ctx, h, loginTimeout); err != nil {
		return err
	}
	now := time.Now()
	evt := &event.Event{
		Type: event.EventMessage, RoomID: id.RoomID(a.room), Sender: ids.Me, ID: ids.RandomEventID(),
		Timestamp: now.UnixMilli(), Content: event.Content{Parsed: &event.MessageEventContent{MsgType: event.MsgText, Body: a.text}},
	}
	raw, err := json.Marshal(&evt.Content)
	if err != nil {
		return err
	}
	if _, err = s.InsertEvent(ctx, store.Event{
		RoomID: a.room, EventID: string(evt.ID), Sender: string(ids.Me),
		Type: evt.Type.Type, Content: raw, TS: now, Status: "pending",
	}); err != nil {
		return err
	}
	h.Bridge.QueueMatrixEvent(ctx, evt)
	return waitStatus(ctx, s, string(evt.ID), 30*time.Second)
}

func link(ctx context.Context, h *host.Host) error {
	if err := ensureNotLinked(ctx, h); err != nil {
		return err
	}
	me, err := h.Me(ctx)
	if err != nil {
		return err
	}
	proc, err := h.Bridge.Network.CreateLogin(ctx, me, connector.LoginFlowIDQR)
	if err != nil {
		return fmt.Errorf("start QR login: %w", err)
	}
	if err = runLogin(ctx, proc, os.Stdout); err != nil {
		return err
	}
	fmt.Println("Linked. Leave this running a minute so history backfills, then Ctrl-C.")
	<-ctx.Done()
	return nil
}

// runLogin walks a QR login to completion, drawing each QR code to out. On every
// path except a completed login it cancels the process so no half-open pairing
// is left behind.
func runLogin(ctx context.Context, proc bridgev2.LoginProcess, out io.Writer) (err error) {
	completed := false
	defer func() {
		if !completed {
			proc.Cancel()
		}
	}()
	step, err := proc.Start(ctx)
	for err == nil {
		switch step.Type {
		case bridgev2.LoginStepTypeComplete:
			completed = true
			return nil
		case bridgev2.LoginStepTypeWebAuthn:
			return errors.New("WhatsApp asked for a passkey, which this test CLI can't do — link from a device without a passkey prompt, or try again")
		case bridgev2.LoginStepTypeDisplayAndWait:
			if p := step.DisplayAndWaitParams; p != nil && p.Type == bridgev2.LoginDisplayTypeQR {
				fmt.Fprintln(out, "Scan with WhatsApp → Settings → Linked devices → Link a device:")
				qrterminal.GenerateHalfBlock(p.Data, qrterminal.L, out)
			}
			waiter, ok := proc.(bridgev2.LoginProcessDisplayAndWait)
			if !ok {
				return errors.New("login process cannot wait for the QR scan")
			}
			step, err = waiter.Wait(ctx)
		default:
			return fmt.Errorf("unexpected login step %q (id %q)", step.Type, step.StepID)
		}
	}
	return err
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
