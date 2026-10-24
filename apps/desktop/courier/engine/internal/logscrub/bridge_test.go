// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package logscrub

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/networkid"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// syncBuffer is a bytes.Buffer the bridge's goroutines can log into while the test reads it.
type syncBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *syncBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *syncBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

// Never log who, end to end: real bridgev2 log lines, made by running the fake network through a real bridge at the
// most verbose level, name no contact, chat, login or message once they have been through the Writer, while the same
// lines unscrubbed do (so the test can fail). The IDs are shaped as WhatsApp's are (a one-to-one chat is the contact's
// JID, which is their phone number; a sender is the bare number or an LID; my login is my own number), plus a chat and
// a contact whose IDs look like nothing, which only dropping keys can keep out. The events are the ones that log a
// contact: messages in, a read receipt and a delivery naming a message bridgev2 never bridged (Task 4's "No target
// message found for read receipt", which TestTypingNeverLogsWho had to leave out), typing both ways, and a send the
// network refuses with an error that quotes the contact.
func TestBridgeLinesNameNoOne(t *testing.T) {
	ctx := context.Background()
	const (
		network  = "fake"
		myNumber = "15550009999"                // my login's ID: WhatsApp's is my phone number
		dmChat   = "15557654321@s.whatsapp.net" // a one-to-one chat: the contact's JID
		dmSender = "15557654321"
		group    = "120363012345678901@g.us"
		lidUser  = "lid-210987654321098"
		plain    = "zqchatplain"
		plainWho = "zqalice"
		body     = "zqbodytext"
	)
	refusal := errors.New("no session with 15557654321@s.whatsapp.net (+1 555-765-4321) for chat \"" + plain + "\"")

	raw, scrubbed := &syncBuffer{}, &syncBuffer{}
	log := zerolog.New(io.MultiWriter(raw, New(scrubbed))).Level(zerolog.TraceLevel).With().Timestamp().Logger()

	dir := t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	m := &media.Store{Dir: filepath.Join(dir, "media")}
	n := fakenet.New()
	direct := true
	n.SetChat(dmChat, fakenet.Chat{Direct: &direct})
	eng, errs := engine.Start(ctx, dir, s, m,
		[]engine.Spec{{Name: network, Connector: func() (bridgev2.NetworkConnector, error) { return n, nil }}}, log)
	require.Empty(t, errs)
	t.Cleanup(eng.Stop)
	h, ok := eng.Host(network)
	require.True(t, ok)
	login, err := n.LoginAs(ctx, h.Bridge, myNumber, "Me")
	require.NoError(t, err)
	a := actions.New(eng, s, m)

	n.Incoming(login, dmChat, dmSender, "3EB0C431D5A8B7E2F1", body)
	n.Incoming(login, group, lidUser, "3EB0AA11BB22CC33DD", body)
	n.Incoming(login, plain, plainWho, "zqmessage1", body)
	rooms := waitRooms(t, s, 3)
	dmRoom := string(ids.RoomID(network, networkid.PortalKey{ID: dmChat, Receiver: login.ID}))
	require.Contains(t, rooms, dmRoom)

	n.Typing(login, dmChat, dmSender, time.Minute)
	n.Receipt(login, dmChat, dmSender, []string{"no-such-message"}, false)
	n.Receipt(login, dmChat, dmSender, []string{"no-such-message"}, true)
	require.NoError(t, a.SetTyping(ctx, dmRoom, true))
	n.FailWith(refusal)
	sent, err := a.SendText(ctx, dmRoom, body, "")
	require.NoError(t, err)
	require.Eventually(t, func() bool {
		e, ok, err := s.GetEvent(ctx, sent)
		return err == nil && ok && e.Status == "failed"
	}, 10*time.Second, 20*time.Millisecond, "the refused send never failed")
	require.Eventually(t, func() bool {
		return strings.Contains(raw.String(), "No target message found for read receipt")
	}, 10*time.Second, 20*time.Millisecond, "fixture: bridgev2 warns of the receipt for a message it never bridged")
	eng.Stop() // every line is written

	// What the bridge's own lines carry (checked, so the test can fail), and what must not survive them.
	named := append([]string{myNumber, dmChat, dmSender, group, lidUser, plain, plainWho, "555-765-4321", sent}, rooms...)
	in, out := raw.String(), scrubbed.String()
	for _, who := range named {
		require.Contains(t, in, who, "fixture: the bridge's own lines carry %q", who)
		require.NotContains(t, out, who, "the scrubbed log names someone")
	}
	for _, u := range []string{dmSender, lidUser, plainWho} {
		require.NotContains(t, out, string(ids.GhostMXID(network, networkid.UserID(u))), "the scrubbed log names a contact")
	}
	require.NotContains(t, in+out, body, "no message text, even before scrubbing")
	for _, shape := range []*regexp.Regexp{
		regexp.MustCompile(`\+\d[\d ().-]{5,}\d|\d{6,}|\d{3}[ .-]\d{3}[ .-]\d{4}`), // phone-number-shaped
		regexp.MustCompile(`[@!#$][^\s"\\]*:courier\.local`),                       // a Matrix user, room or alias
		regexp.MustCompile(`\$[0-9a-f]{32}`),                                       // a Courier event ID
	} {
		require.Empty(t, shape.FindAllString(out, 5), "the scrubbed log keeps a string shaped like an ID")
	}

	// What can't name anyone is kept: every line is still a JSON object, with its level, time and message, and the
	// bridge's name, actions and components stay.
	lines := strings.Split(strings.TrimSpace(out), "\n")
	require.Greater(t, len(lines), 20, "fixture: the bridge logged plenty")
	seen := map[string]bool{}
	for _, line := range lines {
		var obj map[string]any
		require.NoError(t, json.Unmarshal([]byte(line), &obj), "not JSON: %s", line)
		for k := range obj {
			seen[k] = true
			require.Contains(t, allowed, k, "a key not on the allow-list: %s", line)
		}
		require.NotEmpty(t, obj["level"], line)
		require.NotEmpty(t, obj["time"], line)
	}
	for _, k := range []string{"bridge", "message", "action", "event_type", "bridge_evt_type", "error"} {
		require.True(t, seen[k], "the key %q never survived", k)
	}
	require.Contains(t, out, `"message":"No target message found for read receipt"`)
	require.Contains(t, out, `"action":"handle remote event"`)
	require.Contains(t, out, `"error":"no session with [id] ([id]) for chat [quoted]"`, "the refusal, redacted")
}

// waitRooms waits for the store to hold want rooms, each with a message, and returns their IDs.
func waitRooms(t *testing.T, s *store.Store, want int) []string {
	t.Helper()
	var got []string
	require.Eventually(t, func() bool {
		rooms, err := s.ListRooms(context.Background())
		if err != nil {
			return false
		}
		got = got[:0]
		for _, r := range rooms {
			if evs, err := s.Events(context.Background(), r.ID, 1); err == nil && len(evs) > 0 {
				got = append(got, r.ID)
			}
		}
		return len(got) == want
	}, 10*time.Second, 20*time.Millisecond, "the bridge never stored the messages")
	return got
}
