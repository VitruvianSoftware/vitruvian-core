// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

//go:build courierseed

package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/seed"
)

// These run the test copy's engine (vitruvian-vitruvian-courier-engine-seeded, BUILD's vitruvian-courier-engine_seed_test), started as the app
// starts it, with VITRUVIAN_COURIER_SEED naming a scenario file.

// scenarioPath finds name.json among the scenarios BUILD hands over (VITRUVIAN_VITRUVIAN_COURIER_SEED_SCENARIOS, rlocation paths).
func scenarioPath(t *testing.T, name string) string {
	t.Helper()
	for _, rel := range strings.Fields(os.Getenv("VITRUVIAN_VITRUVIAN_COURIER_SEED_SCENARIOS")) {
		if filepath.Base(rel) != name+".json" {
			continue
		}
		for _, root := range []string{os.Getenv("RUNFILES_DIR"), os.Getenv("TEST_SRCDIR")} {
			if root == "" {
				continue
			}
			if p := filepath.Join(root, rel); fileExists(p) {
				return p
			}
		}
	}
	t.Fatalf("scenario %s is not among VITRUVIAN_VITRUVIAN_COURIER_SEED_SCENARIOS %q", name, os.Getenv("VITRUVIAN_VITRUVIAN_COURIER_SEED_SCENARIOS"))
	return ""
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

type seededRow struct {
	RoomID   string `json:"room_id"`
	Network  string `json:"network"`
	Name     string `json:"name"`
	IsDirect bool   `json:"is_direct"`
	Pinned   bool   `json:"pinned"`
	Unread   int    `json:"unread"`
}

type seededEvent struct {
	EventID    string `json:"event_id"`
	SenderName string `json:"sender_name"`
	Mine       bool   `json:"mine"`
	Type       string `json:"type"`
	TS         int64  `json:"ts"`
	Content    struct {
		Body string `json:"body"`
	} `json:"content"`
	Thread *struct {
		Replies int `json:"replies"`
	} `json:"thread"`
}

func (c *rpcClient) inbox() map[string]seededRow {
	c.t.Helper()
	var res struct {
		Rooms []seededRow `json:"rooms"`
	}
	require.NoError(c.t, json.Unmarshal(c.call("inbox.list", nil), &res))
	out := map[string]seededRow{}
	for _, r := range res.Rooms {
		out[r.Name] = r
	}
	return out
}

// messages is the chat's newest page of messages (no reactions), newest first; a reply that stays in its thread
// isn't on it. With thread, that thread's page.
func (c *rpcClient) messages(roomID, thread string) []seededEvent {
	c.t.Helper()
	params := map[string]any{"room_id": roomID, "limit": 100}
	if thread != "" {
		params["thread"] = thread
	}
	var page struct {
		Events []seededEvent `json:"events"`
	}
	require.NoError(c.t, json.Unmarshal(c.call("room.events", params), &page))
	var out []seededEvent
	for _, e := range page.Events {
		if e.Type == "m.room.message" {
			out = append(out, e)
		}
	}
	return out
}

// TestSeedPlaysGroupThreadsOnce: the seeded engine on an empty data folder plays group-threads (its chats, their
// names and people, every message at its own past time, a thread with its replies), marks the folder played, and a
// second start on the same folder loads the account again and adds nothing.
func TestSeedPlaysGroupThreadsOnce(t *testing.T) {
	t.Setenv("VITRUVIAN_COURIER_SEED", scenarioPath(t, "group-threads"))
	data := filepath.Join(shortDir(t), "data")

	p, ready := start(t, data, nil)
	c := dial(t, ready.Socket)
	require.Equal(t, []string{"whatsapp"}, c.hello().Networks, "only the scenario's networks, under their real names")

	// Wait for every chat by name, not just four rows: a direct chat's row can appear before the bridge has named it
	// (seen in the merge queue, run 42326600819: Cy Example's row still had no name).
	names := []string{"Launch crew", "Ann Example", "Bo Example", "Cy Example"}
	var rows map[string]seededRow
	var group []seededEvent
	c.until(func() bool {
		rows = c.inbox()
		for _, name := range names {
			if _, ok := rows[name]; !ok {
				return false
			}
		}
		if !rows["Cy Example"].Pinned {
			return false // the pin is chat state, which can land after the name
		}
		g := rows["Launch crew"]
		group = c.messages(g.RoomID, "")
		return len(group) >= 9
	})
	require.Len(t, rows, 4)
	for _, name := range names {
		require.Contains(t, rows, name)
		require.Equal(t, "whatsapp", rows[name].Network)
	}
	require.False(t, rows["Launch crew"].IsDirect)
	require.True(t, rows["Ann Example"].IsDirect)
	require.True(t, rows["Cy Example"].Pinned)
	require.Len(t, group, 9, "the group's messages outside its threads")

	var root seededEvent
	senders := map[string]bool{}
	for _, e := range group {
		senders[e.SenderName] = true
		if e.Content.Body == "Who can take the release notes?" {
			root = e
		}
	}
	require.True(t, senders["Ann Example"] && senders["Bo Example"], "people show by name: %v", senders)
	require.NotEmpty(t, root.EventID, "the first thread's root")
	require.True(t, root.Mine)
	require.Less(t, root.TS, time.Now().Add(-3*time.Hour).UnixMilli(), "sent 230 minutes ago, not now")
	c.until(func() bool {
		for _, e := range c.messages(rows["Launch crew"].RoomID, "") {
			if e.EventID == root.EventID {
				root = e
			}
		}
		return root.Thread != nil && root.Thread.Replies == 3
	})
	replies := c.messages(rows["Launch crew"].RoomID, root.EventID)
	require.Len(t, replies, 4, "the thread's three replies and its root")

	// Playback queues the scenario, then marks the folder; the chats above can be in before the mark is. Wait for the
	// mark and for every chat's messages, so the restart below finds the whole scenario stored.
	count := func() int {
		n := 0
		for _, r := range c.inbox() {
			n += len(c.messages(r.RoomID, ""))
		}
		return n
	}
	const allMessages = 9 + 3 + 2 + 3 // every chat's messages outside threads
	// Polled, not c.until: writing the mark sends no notification, and the account's name can land after its chats.
	require.Eventually(t, func() bool {
		played, err := seed.Played(data)
		return err == nil && played && count() == allMessages && c.startedAccounts()["whatsapp"].RemoteName == "Sam Seed"
	}, 30*time.Second, 100*time.Millisecond, "the folder marked played, every message stored, the account named")

	require.NoError(t, p.cmd.Process.Signal(syscall.SIGTERM))
	require.Equal(t, 0, p.exited(t, 60*time.Second), "stderr:\n%s", p.stderr.String())

	// Again, on the same folder: the account loads, and nothing is played twice.
	p, ready = start(t, data, nil)
	c = dial(t, ready.Socket)
	c.hello()
	acct := c.startedAccounts()["whatsapp"]
	require.Equal(t, "CONNECTED", acct.State, "the account the first start made loads again")
	require.Equal(t, "Sam Seed", acct.RemoteName)
	first := count() // count reads through c, which is the new connection now
	require.Equal(t, allMessages, first, "every chat's messages outside threads, once")
	// Give a stray playback time to show: nothing more may arrive.
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		require.Equal(t, first, count())
		require.Len(t, c.inbox(), 4)
		time.Sleep(200 * time.Millisecond)
	}
	require.NoError(t, p.cmd.Process.Signal(syscall.SIGTERM))
	require.Equal(t, 0, p.exited(t, 60*time.Second), "stderr:\n%s", p.stderr.String())
}

// A scenario file that doesn't check stops the seeded engine at start-up, saying what is wrong, rather than opening
// an empty copy.
func TestSeedRefusesABadScenario(t *testing.T) {
	bad := filepath.Join(t.TempDir(), "bad.json")
	require.NoError(t, os.WriteFile(bad, []byte(`{"accounts":[{"network":"whatsapp","login":"a","name":"A"}],
		"chats":[{"account":"nobody","id":"c","name":"C"}]}`), 0o600))
	t.Setenv("VITRUVIAN_COURIER_SEED", bad)
	p := launch(t, nil, "--data", filepath.Join(shortDir(t), "data"))
	require.Equal(t, exitFailed, p.exited(t, 60*time.Second))
	// The engine's startup error is scrubbed of identifiers, as every one is (logscrub), but still says what is wrong.
	require.Contains(t, p.stderr.String(), "is not in accounts")
}
