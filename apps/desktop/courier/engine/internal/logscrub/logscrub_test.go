// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package logscrub

import (
	"bytes"
	"encoding/json"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
)

// The keys bridgev2 and the connectors name people and chats with are dropped, nested ones (remote_sender.user_id)
// with their parent; the allowed ones stay, in their order.
func TestOnlyAllowedKeysSurvive(t *testing.T) {
	in := `{"level":"warn","bridge":"whatsapp","portal_id":"15557654321@s.whatsapp.net","portal_receiver":"15550009999",` +
		`"action":"handle remote event","remote_sender":{"user_id":"15557654321","sender_login":""},` +
		`"ghost_id":"zqghost","original_id":"zqorig","sender":"15557654321@s.whatsapp.net","pn":"+15557654321",` +
		`"lid":"210987654321098@lid","jid":"15557654321@s.whatsapp.net","login_id":"15550009999","user_id":"zquser",` +
		`"room_id":"!abc:courier.local","event_id":"$abcdef0123456789","part_id":"","remote_message_id":"zqmsg",` +
		`"bridge_evt_type":"RemoteEventReadReceipt","event_type":"m.receipt","component":"typing updater",` +
		`"time":"2026-10-23T10:00:00Z","message":"No target message found for read receipt"}`
	got := string(Line([]byte(in)))
	require.Equal(t, `{"level":"warn","bridge":"whatsapp","action":"handle remote event",`+
		`"bridge_evt_type":"RemoteEventReadReceipt","event_type":"m.receipt","component":"typing updater",`+
		`"time":"2026-10-23T10:00:00Z","message":"No target message found for read receipt"}`, got)
}

// Identifiers inside a message or an error become a fixed token, whatever network they come from; the words around
// them stay. A quoted value goes whatever it looks like (a name, an ID that has no shape, a message's text).
func TestRedactTakesOutEveryShapeOfID(t *testing.T) {
	for in, want := range map[string]string{
		// Matrix: a ghost, a room, an alias, my own ID, an event (opaque, and with a server).
		"Failed to get ghost @whatsapp_15557654321:courier.local":                  "Failed to get ghost [id]",
		"no portal for !0a1b2c3d4e5f60718293a4b5c6d7e8f9:courier.local, giving up": "no portal for [id], giving up",
		"alias #friends:example.org taken":                                         "alias [id] taken",
		"read by @me:courier.local":                                                "read by [id]",
		"target $0a1b2c3d4e5f60718293a4b5c6d7e8f9 gone":                            "target [id] gone",
		"target $abc123DEF:example.org gone":                                       "target [id] gone",
		// WhatsApp: a JID, a device JID, a group, an LID, a bare LID number.
		"Failed to send to 15557654321@s.whatsapp.net":   "Failed to send to [id]",
		"session for 15557654321:12@s.whatsapp.net lost": "session for [id] lost",
		"group 120363012345678901@g.us left":             "group [id] left",
		"Got receipt from 210987654321098@lid":           "Got receipt from [id]",
		"lid 210987654321098 has no phone number":        "lid [id] has no phone number",
		// Phone numbers however they are written, and an e-mail.
		"Phone +15557654321 is not on WhatsApp":    "Phone [id] is not on WhatsApp",
		"call +1 555-765-4321 failed":              "call [id] failed",
		"number +44 (20) 7946 0958 refused":        "number [id] refused",
		"number (555) 765-4321 unknown":            "number [id] unknown",
		"number 555.765.4321 unknown":              "number [id] unknown",
		"bare 15557654321 here":                    "bare [id] here",
		"invite sent to ana.lima+work@example.com": "invite sent to [id]",
		// Signal, Telegram, Slack, a WhatsApp message ID.
		"no profile for PNI:0f8e7d6c-5b4a-4321-9876-0123456789ab": "no profile for PNI:[id]",
		"user 7123456789 blocked me":                              "user [id] blocked me",
		"username @ana_lima not found":                            "username [id] not found",
		"conversation D04ABCDE12 for U0123ABCD in T01ABC2DEF":     "conversation [id] for [id] in [id]",
		"edit target 3EB0C431D5A8B7E2F1 not found":                "edit target [id] not found",
		// Quotes and URLs.
		`no chat named "Ana Lima"`: "no chat named [quoted]",
		`Post "https://web.whatsapp.com/v1/send?to=15557654321": dial tcp: i/o timeout`: `Post "https://*.whatsapp.com/[path]": dial tcp: i/o timeout`,
		"GET https://acme-co.slack.com/api/users.info?user=U0123ABCD failed":            "GET https://*.slack.com/[path] failed",
		"connect wss://chat.signal.org:443/v1/websocket/ refused":                       "connect wss://*.signal.org/[path] refused",
		"mxc://courier.local/0a1b2c missing":                                            "mxc://courier.local/[path] missing",
		"dial tcp 127.0.0.1:29317: connection refused":                                  "dial tcp 127.0.0.1:29317: connection refused",
	} {
		require.Equal(t, want, Redact(in), "Redact(%q)", in)
	}
}

// Redact leaves alone what names no one: the engine's own messages, the bridges' fixed words, numbers that are counts,
// codes or times, and words with a digit in them.
func TestRedactKeepsWhatNamesNoOne(t *testing.T) {
	for _, s := range []string{
		"typing still on its way at shutdown; stopping anyway",
		"not connected, so the network wasn't told of a change yet; it is told once it connects",
		"couldn't claim waiting messages; trying again later",
		"search backfill done",
		"Search index: a millisecond already holds the most messages it can; one message is not indexed",
		"No target message found for read receipt",
		"Failed to handle Matrix message",
		"bridge database still has open connections after Stop",
		"request failed inside the engine",
		"unexpected status 500 after 3 attempts in 1500ms",
		"bridgev2 v0.31.0 on darwin/arm64",
		"sql: no rows in result set",
		"context deadline exceeded",
		"at 2026-10-23T10:00:00Z",
	} {
		require.Equal(t, s, Redact(s))
	}
}

// The engine's own lines, made as the engine makes them, keep every field they had: the network, the kind of change,
// counts and durations, the method, a redacted error.
func TestTheEnginesOwnLinesKeepTheirFields(t *testing.T) {
	var buf bytes.Buffer
	log := zerolog.New(New(&buf)).With().Timestamp().Logger()
	read := func() map[string]any {
		t.Helper()
		var m map[string]any
		require.NoError(t, json.Unmarshal(buf.Bytes(), &m), buf.String())
		buf.Reset()
		require.NotEmpty(t, m["time"])
		delete(m, "time")
		return m
	}

	log.Warn().Dur("waited", 5*time.Second).Msg("typing still on its way at shutdown; stopping anyway")
	require.Equal(t, map[string]any{
		"level": "warn", "waited": 5000.0,
		"message": "typing still on its way at shutdown; stopping anyway",
	}, read())

	log.Warn().Str("network", "whatsapp").Str("change", "typing").Msg("the network wasn't told of typing")
	require.Equal(t, map[string]any{
		"level": "warn", "network": "whatsapp", "change": "typing",
		"message": "the network wasn't told of typing",
	}, read())

	log.Info().Int("batches", 3).Int64("took_ms", 120).Int("messages", 10).Int("chats", 2).Int("people", 4).
		Msg("search backfill done")
	require.Equal(t, map[string]any{
		"level": "info", "batches": 3.0, "took_ms": 120.0, "messages": 10.0,
		"chats": 2.0, "people": 4.0, "message": "search backfill done",
	}, read())

	log.Warn().Err(errors.New("database is locked")).Dur("retry_in", time.Second).
		Msg("search backfill: a batch failed; trying again later")
	require.Equal(t, map[string]any{
		"level": "warn", "error": "database is locked", "retry_in": 1000.0,
		"message": "search backfill: a batch failed; trying again later",
	}, read())

	log.Error().Str("method", "room.events").Err(errors.New(`room !0a1b2c3d:courier.local: "Ana" not found`)).
		Msg("request failed inside the engine")
	require.Equal(t, map[string]any{
		"level": "error", "method": "room.events", "error": "room [id]: [quoted] not found",
		"message": "request failed inside the engine",
	}, read())

	log.Warn().Str("component", "localmatrix").Str("status", "weird").Str("event_id", "$0a1b2c3d4e5f6071").
		Msg("ignoring unknown message status")
	require.Equal(t, map[string]any{
		"level": "warn", "component": "localmatrix", "status": "weird",
		"message": "ignoring unknown message status",
	}, read(), "the message an event ID names is left out")

	log.Warn().Int("open_connections", 2).Int("per_millisecond", 1000).Str("bridge", "signal").Msg("busy")
	require.Equal(t, map[string]any{
		"level": "warn", "open_connections": 2.0, "per_millisecond": 1000.0,
		"bridge": "signal", "message": "busy",
	}, read())

	log.Error().Str("network", "telegram").Any("panic", "index out of range for 7123456789").
		Bytes("stack", []byte("goroutine 1 [running]:\nmain.main()\n\t/src/main.go:12 +0x1d")).
		Msg("network panicked while starting")
	require.Equal(t, map[string]any{
		"level": "error", "network": "telegram", "panic": "index out of range for [id]",
		"stack": "goroutine 1 [running]:\nmain.main()\n\t/src/main.go:12 +0x1d", "message": "network panicked while starting",
	},
		read())
}

// A line that isn't JSON (a plain print, a panic's first line) is redacted as text; one that starts as JSON but can't
// be read is left out, since its keys can't be checked.
func TestALineThatIsNotJSONIsRedacted(t *testing.T) {
	require.Equal(t, "panic: no session for [id] ([id])",
		string(Line([]byte("panic: no session for 15557654321@s.whatsapp.net (+1 555-765-4321)"))))
	require.Equal(t, string(unreadable), string(Line([]byte(`{"level":"warn","portal_id":"zqchat"`))))
	require.Equal(t, string(unreadable), string(Line([]byte(`{"level":"warn"} {"portal_id":"zqchat"}`))))
	require.Equal(t, string(unreadable), string(Line([]byte(`{"level":"warn","message":"x" "portal_id":"zqchat"}`))))

	var buf bytes.Buffer
	p := []byte("call +15557654321 now\n\n{\"level\":\"info\",\"pn\":\"+15557654321\",\"message\":\"m\"}\ntail 15557654321")
	n, err := New(&buf).Write(p)
	require.NoError(t, err)
	require.Equal(t, len(p), n)
	require.Equal(t, "call [id] now\n{\"level\":\"info\",\"message\":\"m\"}\ntail [id]\n", buf.String())
}

// Only a level that is a level and a time that is a time are kept as they are; an allowed key holding an object, an
// array or null is dropped, and numbers and booleans stay.
func TestValuesOfTheWrongShapeAreDropped(t *testing.T) {
	got := string(Line([]byte(`{"level":"zq 15557654321","time":"zqchat","message":{"user_id":"zq"},` +
		`"error":["zq"],"status":null,"waited":12.5,"batches":-1,"chats":true}`)))
	require.Equal(t, `{"waited":12.5,"batches":-1,"chats":true}`, got)
}

// A huge value is cut, so a line can't grow without end; a write error loses that line and nothing else.
func TestLongLinesAreCutAndWriteErrorsDontBreakLogging(t *testing.T) {
	long := strings.Repeat("é", 1<<20) // 2 MiB, multi-byte, so the cut must find a boundary
	out := Line([]byte(`{"level":"warn","message":"` + long + `","stack":"` + long + `"}`))
	require.Less(t, len(out), maxValue+maxStack+100)
	var m map[string]string
	require.NoError(t, json.Unmarshal(out, &m))
	require.True(t, strings.HasSuffix(m["message"], "…[cut]"))
	require.LessOrEqual(t, len(m["message"]), maxValue)
	require.LessOrEqual(t, len(m["stack"]), maxStack)
	require.LessOrEqual(t, len(Line([]byte(long))), maxText)

	w := &failingWriter{fail: true}
	n, err := New(w).Write([]byte(`{"level":"warn","message":"lost"}` + "\n"))
	require.NoError(t, err, "zerolog would print the event, unscrubbed, to os.Stderr")
	require.Equal(t, 34, n)
	log := zerolog.New(New(w))
	log.Warn().Msg("lost")
	w.fail = false
	log.Warn().Msg("kept")
	require.Equal(t, `{"level":"warn","message":"kept"}`+"\n", w.buf.String())
}

type failingWriter struct {
	fail bool
	buf  bytes.Buffer
}

func (w *failingWriter) Write(p []byte) (int, error) {
	if w.fail {
		return 0, errors.New("disk full")
	}
	return w.buf.Write(p)
}

// Many goroutines log at once (the bridges do): every line reaches the output whole, one per write, and the output
// needn't be safe for concurrent use itself (zerolog's ConsoleWriter, the CLI's, isn't). Run with the race detector.
func TestConcurrentLinesStayWhole(t *testing.T) {
	var out bytes.Buffer
	log := zerolog.New(New(&out))
	var wg sync.WaitGroup
	for g := range 8 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := range 200 {
				log.Warn().Int("batches", g*1000+i).Str("portal_id", "15557654321@s.whatsapp.net").Msg("busy")
			}
		}()
	}
	wg.Wait()
	lines := strings.Split(strings.TrimSpace(out.String()), "\n")
	require.Len(t, lines, 1600)
	for _, l := range lines {
		var m map[string]any
		require.NoError(t, json.Unmarshal([]byte(l), &m), l)
		require.Len(t, m, 3, l)
	}
}
