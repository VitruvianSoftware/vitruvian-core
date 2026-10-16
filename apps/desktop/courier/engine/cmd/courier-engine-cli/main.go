// courier-engine-cli drives the milestone-1 engine by hand: link WhatsApp, list chats, watch and send.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
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
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

const usage = "usage: courier-engine-cli [--data DIR] link|chats|tail|send <room-id> <text>"

type args struct{ data, cmd, room, text string }

func parseArgs(argv []string) (args, error) {
	home, _ := os.UserHomeDir()
	fs := flag.NewFlagSet("courier-engine-cli", flag.ContinueOnError)
	data := fs.String("data", filepath.Join(home, "Library", "Application Support", "Courier-m1"), "data directory")
	if err := fs.Parse(argv); err != nil {
		return args{}, err
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
	if err := os.MkdirAll(a.data, 0o700); err != nil {
		return err
	}
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
		return send(ctx, h, s, a)
	}
	return nil
}

func send(ctx context.Context, h *host.Host, s *store.Store, a args) error {
	now := time.Now()
	evt := &event.Event{Type: event.EventMessage, RoomID: id.RoomID(a.room), Sender: ids.Me, ID: ids.RandomEventID(),
		Timestamp: now.UnixMilli(), Content: event.Content{Parsed: &event.MessageEventContent{MsgType: event.MsgText, Body: a.text}}}
	raw, err := json.Marshal(&evt.Content)
	if err != nil {
		return err
	}
	if _, err = s.InsertEvent(ctx, store.Event{RoomID: a.room, EventID: string(evt.ID), Sender: string(ids.Me),
		Type: evt.Type.Type, Content: raw, TS: now, Status: "pending"}); err != nil {
		return err
	}
	h.Bridge.QueueMatrixEvent(ctx, evt)
	return waitStatus(ctx, s, string(evt.ID))
}

func link(ctx context.Context, h *host.Host) error {
	me, err := h.Me(ctx)
	if err != nil {
		return err
	}
	proc, err := h.Bridge.Network.CreateLogin(ctx, me, connector.LoginFlowIDQR)
	if err != nil {
		return fmt.Errorf("start QR login: %w", err)
	}
	step, err := proc.Start(ctx)
	for err == nil && step.Type == bridgev2.LoginStepTypeDisplayAndWait {
		if p := step.DisplayAndWaitParams; p != nil && p.Type == bridgev2.LoginDisplayTypeQR {
			fmt.Println("Scan with WhatsApp → Settings → Linked devices → Link a device:")
			qrterminal.GenerateHalfBlock(p.Data, qrterminal.L, os.Stdout)
		}
		waiter, ok := proc.(bridgev2.LoginProcessDisplayAndWait)
		if !ok {
			return errors.New("login process cannot wait for the QR scan")
		}
		step, err = waiter.Wait(ctx)
	}
	if err != nil {
		return err
	}
	if step.Type != bridgev2.LoginStepTypeComplete {
		return fmt.Errorf("unexpected login step %s", step.Type)
	}
	fmt.Println("Linked. Leave this running a minute so history backfills, then Ctrl-C.")
	<-ctx.Done()
	return nil
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

func waitStatus(ctx context.Context, s *store.Store, eventID string) error {
	deadline := time.After(30 * time.Second)
	for {
		e, _, err := s.GetEvent(ctx, eventID)
		if err != nil {
			return err
		}
		if e.Status == "sent" || e.Status == "failed" {
			fmt.Println("status:", e.Status, e.StatusReason)
			if e.Status == "failed" {
				return errors.New("message was not delivered")
			}
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-deadline:
			return errors.New("no delivery status within 30 s")
		case <-time.After(200 * time.Millisecond):
		}
	}
}
