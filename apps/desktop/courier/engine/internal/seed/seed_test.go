// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package seed

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"

	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// scenarioDir is apps/desktop/courier/seed/scenarios in the runfiles (BUILD's data).
func scenarioDir(t *testing.T) string {
	t.Helper()
	for _, root := range []string{os.Getenv("RUNFILES_DIR"), os.Getenv("TEST_SRCDIR")} {
		if root == "" {
			continue
		}
		dir := filepath.Join(root, "_main", "apps/desktop/courier/seed/scenarios")
		if _, err := os.Stat(dir); err == nil {
			return dir
		}
	}
	t.Fatal("the scenarios are not in the runfiles: run with bazel test //apps/desktop/courier/engine/internal/seed:seed_test")
	return ""
}

func TestEveryScenarioIsValid(t *testing.T) {
	names, err := filepath.Glob(filepath.Join(scenarioDir(t), "*.json"))
	require.NoError(t, err)
	var got []string
	for _, p := range names {
		s, err := Load(p)
		require.NoError(t, err, p)
		require.NotEmpty(t, s.Accounts, p)
		got = append(got, strings.TrimSuffix(filepath.Base(p), ".json"))
	}
	require.ElementsMatch(t, []string{"direct", "empty", "group-threads", "long-content", "multi-network"}, got)
}

func TestTheScenariosHaveWhatTheyPromise(t *testing.T) {
	dir := scenarioDir(t)
	load := func(name string) *Scenario {
		s, err := Load(filepath.Join(dir, name+".json"))
		require.NoError(t, err)
		return s
	}
	gt := load("group-threads")
	var group Chat
	directs := 0
	for _, c := range gt.Chats {
		if c.ID == "grp-launch" {
			group = c
		}
		if c.Direct {
			directs++
		}
	}
	roots := map[string]bool{}
	replies, reactions := 0, 0
	for _, m := range group.Messages {
		if m.Thread != "" {
			roots[m.Thread] = true
		}
		if m.ReplyTo != "" {
			replies++
		}
		reactions += len(m.Reactions)
	}
	require.Len(t, roots, 2, "two threads")
	require.Positive(t, replies)
	require.Positive(t, reactions)
	require.GreaterOrEqual(t, directs, 2)

	mn := load("multi-network")
	require.ElementsMatch(t, []string{"whatsapp", "slack", "telegram"}, mn.Networks())
	require.GreaterOrEqual(t, len(mn.Chats), 8)
	var pinned, muted, unread bool
	for _, c := range mn.Chats {
		pinned, muted, unread = pinned || c.Pinned, muted || c.Muted, unread || c.Unread
	}
	require.True(t, pinned && muted && unread)

	require.Empty(t, load("empty").Chats)
	require.Len(t, load("direct").Chats, 1)
}

func TestCheckNamesWhatIsWrong(t *testing.T) {
	_, err := Parse([]byte(`{"accounts":[{"network":"WhatsApp","login":"a","name":"A"}],"people":[{"id":"me","name":"X"}],
		"chats":[{"account":"nobody","id":"c","direct":true,"members":["ghost","zed"],"messages":[
		  {"id":"m1","from":"stranger","minutesAgo":-1,"text":"x","replyTo":"m9",
		   "reactions":[{"from":"bo","emoji":""}]},
		  {"id":"m2","from":"me","minutesAgo":5,"text":"y"},
		  {"id":"m2","from":"me","minutesAgo":5,"text":"z"},
		  {"id":"m3","from":"me","minutesAgo":10,"text":"older","thread":"m2"}]}]}`))
	require.Error(t, err)
	for _, want := range []string{
		`network "WhatsApp" must be lowercase`,
		`a person's id may be neither empty nor "me"`,
		`account "nobody" is not in accounts`,
		`member "ghost" is not in people`,
		`needs exactly one member`,
		`from "stranger" is neither`,
		`minutesAgo -1 is in the future`,
		`replyTo "m9" is not a message of this chat`,
		`thread "m2" was sent after it`,
		`a reaction from "bo"`,
		`has no emoji`,
		`message "m2" is listed twice`,
	} {
		require.Contains(t, err.Error(), want)
	}
	_, err = Parse([]byte(`{"accounts":[],"chats":[],"surprise":1}`))
	require.ErrorContains(t, err, "unknown field")
}

func TestOrderedIsOldestFirstAndStable(t *testing.T) {
	c := Chat{Messages: []Message{{ID: "new", MinutesAgo: 1}, {ID: "old", MinutesAgo: 9}, {ID: "same-a", MinutesAgo: 5}, {ID: "same-b", MinutesAgo: 5}}}
	var got []string
	for _, m := range c.Ordered() {
		got = append(got, m.ID)
	}
	require.Equal(t, []string{"old", "same-a", "same-b", "new"}, got)
}

func TestPlayedMarker(t *testing.T) {
	dir := t.TempDir()
	played, err := Played(dir)
	require.NoError(t, err)
	require.False(t, played)
	require.NoError(t, MarkPlayed(dir, "/x/group-threads.json"))
	played, err = Played(dir)
	require.NoError(t, err)
	require.True(t, played)
	b, err := os.ReadFile(filepath.Join(dir, PlayedFile))
	require.NoError(t, err)
	require.Contains(t, string(b), Marker)
	require.Contains(t, string(b), "group-threads.json")
}

// Playing group-threads through a real bridge over fakes puts its chats, names, messages, reactions and a thread in
// the store, each message at its own past time.
func TestPlayFillsTheStore(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	sc, err := Load(filepath.Join(scenarioDir(t), "group-threads.json"))
	require.NoError(t, err)
	n := fakenet.New()
	nets := map[string]*fakenet.Network{"whatsapp": n}
	require.NoError(t, sc.Prepare(nets))

	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	eng, errs := engine.Start(ctx, dir, s, &media.Store{Dir: filepath.Join(dir, "media")}, []engine.Spec{{
		Name: "whatsapp", Connector: func() (bridgev2.NetworkConnector, error) { return n, nil },
	}}, zerolog.Nop())
	require.Empty(t, errs)
	defer eng.Stop()
	h, ok := eng.Host("whatsapp")
	require.True(t, ok)

	now := time.Now()
	require.NoError(t, sc.Play(ctx, map[string]*bridgev2.Bridge{"whatsapp": h.Bridge}, nets, now))

	want := 0
	for _, c := range sc.Chats {
		for _, m := range c.Messages {
			want += 1 + len(m.Reactions)
		}
	}
	byName := map[string]store.Room{}
	var events []store.Event
	require.Eventually(t, func() bool {
		rooms, err := s.ListRooms(ctx)
		if err != nil {
			return false
		}
		byName = map[string]store.Room{}
		events = nil
		for _, r := range rooms {
			byName[r.Name] = r
			evs, err := s.Events(ctx, r.ID, 200)
			if err != nil {
				return false
			}
			for _, e := range evs {
				if e.Type == "m.room.message" || e.Type == "m.reaction" {
					events = append(events, e)
				}
			}
		}
		return len(events) >= want
	}, 20*time.Second, 50*time.Millisecond, "the scenario's messages and reactions never all reached the store")
	require.Len(t, events, want)
	for _, name := range []string{"Launch crew", "Ann Example", "Bo Example", "Cy Example"} {
		require.Contains(t, byName, name)
	}
	require.False(t, byName["Launch crew"].IsDirect)
	require.True(t, byName["Ann Example"].IsDirect)

	var threaded, mine, old bool
	for _, e := range events {
		var c struct {
			Body      string `json:"body"`
			RelatesTo struct {
				RelType string `json:"rel_type"`
			} `json:"m.relates_to"`
		}
		require.NoError(t, json.Unmarshal(e.Content, &c))
		threaded = threaded || c.RelatesTo.RelType == "m.thread"
		mine = mine || e.Sender == string(ids.Me)
		if c.Body == "Happy Friday!" { // 1500 minutes ago
			old = e.TS.Before(now.Add(-24*time.Hour)) && e.TS.After(now.Add(-26*time.Hour))
		}
	}
	require.True(t, threaded, "a thread reply")
	require.True(t, mine, "a message from me")
	require.True(t, old, "messages keep their past time")

	p, ok, err := s.GetProfile(ctx, string(ids.GhostMXID("whatsapp", "ann")))
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "Ann Example", p.DisplayName)
}
