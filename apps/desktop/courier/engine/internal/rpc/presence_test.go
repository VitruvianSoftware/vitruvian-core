// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/login"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// Protocol 5's presence: receipts and deliveries on my messages, typing, waiting sends, a private chat from a group,
// Mark as Unread from a message, and accounts with more than one login.

// wireReader is a Reader as it comes off the wire.
type wireReader struct {
	UserID string `json:"user_id"`
	Name   string `json:"name"`
	TS     int64  `json:"ts"`
}

// wireEvent5 is an Event as it comes off the wire, with protocol 5's fields.
type wireEvent5 struct {
	EventID      string       `json:"event_id"`
	Mine         bool         `json:"mine"`
	Status       string       `json:"status"`
	StatusReason string       `json:"status_reason"`
	Delivered    bool         `json:"delivered"`
	ReadBy       []wireReader `json:"read_by"`
}

type wirePage5 struct {
	Events []wireEvent5 `json:"events"`
	Before *cursor      `json:"before"`
}

func (p wirePage5) event(t *testing.T, eventID string) wireEvent5 {
	t.Helper()
	for _, e := range p.Events {
		if e.EventID == eventID {
			return e
		}
	}
	t.Fatalf("%s is not on the page", eventID)
	return wireEvent5{}
}

// page5 reads the newest page of a chat.
func (c *client) page5(roomID string) wirePage5 {
	c.t.Helper()
	var p wirePage5
	c.ok("room.events", map[string]any{"room_id": roomID, "limit": 100}, &p)
	return p
}

type wireLogin struct {
	AccountID  string `json:"account_id"`
	RemoteName string `json:"remote_name"`
	State      string `json:"state"`
	Error      string `json:"error"`
}

type wireAccount5 struct {
	Network    string      `json:"network"`
	State      string      `json:"state"`
	Error      string      `json:"error"`
	RemoteName string      `json:"remote_name"`
	Logins     []wireLogin `json:"logins"`
}

func (c *client) account(network string) wireAccount5 {
	c.t.Helper()
	var res struct {
		Accounts []wireAccount5 `json:"accounts"`
	}
	c.ok("accounts.list", nil, &res)
	for _, a := range res.Accounts {
		if a.Network == network {
			return a
		}
	}
	c.t.Fatalf("no account %s", network)
	return wireAccount5{}
}

// loginState is a login's bridge state as the bridge sends it, sent now.
func loginState(event, accountID, name, message string) json.RawMessage {
	b, _ := json.Marshal(map[string]any{
		"state_event": event, "remote_id": accountID, "remote_name": name, "message": message, "timestamp": time.Now().Unix(),
	})
	return b
}

// secondAccount signs a second WhatsApp account in beside the world's, with a state for each.
func (w *world) secondAccount(t *testing.T) *bridgev2.UserLogin {
	t.Helper()
	ctx := context.Background()
	h, ok := w.eng.Host("whatsapp")
	require.True(t, ok)
	second, err := w.wa.LoginAs(ctx, h.Bridge, "whatsapp-second", "Second Account")
	require.NoError(t, err)
	require.NoError(t, w.s.SetLoginState(ctx, "whatsapp", string(w.waLogin.ID), loginState("CONNECTED", string(w.waLogin.ID), "Test Account", "")))
	require.NoError(t, w.s.SetLoginState(ctx, "whatsapp", string(second.ID), loginState("CONNECTED", string(second.ID), "Second Account", "")))
	return second
}

// direct makes the world's chat the one-to-one chat with contact, as a bridge stores it.
func (w *world) direct(t *testing.T) {
	t.Helper()
	ctx := context.Background()
	r, ok, err := w.s.GetRoom(ctx, w.room)
	require.NoError(t, err)
	require.True(t, ok)
	r.IsDirect = true
	require.NoError(t, w.s.UpsertRoom(ctx, r))
	require.NoError(t, w.s.SetMember(ctx, w.room, contact, json.RawMessage(`{"membership":"join"}`)))
}

func TestPresenceParamsValidation(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	start := func(extra map[string]any) map[string]any {
		p := map[string]any{"network": "whatsapp", "flow": fakenet.ScriptFlow}
		for k, v := range extra {
			p[k] = v
		}
		return p
	}
	for _, tc := range []struct {
		name, method string
		params       map[string]any
		reason       string
	}{
		{
			"another with account_id", "login.start", start(map[string]any{"another": true, "account_id": string(w.waLogin.ID)}),
			"another and account_id can't be given together",
		},
		{"account_id too long", "login.start", start(map[string]any{"account_id": strings.Repeat("a", 257)}), "account_id must be 1 to 256 bytes"},
		{"account_id empty", "login.start", start(map[string]any{"account_id": ""}), "account_id must be 1 to 256 bytes"},
		{"no such account", "login.start", start(map[string]any{"account_id": "no-such-account"}), "account_id is no account of this network"},
		{"typing missing", "room.setTyping", map[string]any{"room_id": w.room}, "typing is required"},
		{"typing chat missing", "room.setTyping", map[string]any{"typing": true}, "room_id is required"},
		{"unread from missing", "room.setUnreadFrom", map[string]any{}, "event_id is required"},
		{"private chat person missing", "room.directChat", map[string]any{"room_id": w.room}, "user_id is required"},
		{"private chat group missing", "room.directChat", map[string]any{"user_id": contact}, "room_id is required"},
		{"unread from takes no chat", "room.setUnreadFrom", map[string]any{"event_id": w.events[0], "room_id": w.room}, "unknown parameter room_id"},
	} {
		e := c.fails(CodeInvalidParams, tc.method, tc.params)
		require.Equal(t, tc.reason, reason(t, e), tc.name)
	}
	// 256 bytes is still an account ID: refused as no account of the network's, not as too long.
	e := c.fails(CodeInvalidParams, "login.start", start(map[string]any{"account_id": strings.Repeat("é", 128)}))
	require.Equal(t, "account_id is no account of this network", reason(t, e))
}

func TestPresenceErrorsMapExactly(t *testing.T) {
	for _, tc := range []struct {
		err    error
		code   int
		reason string
	}{
		{fmt.Errorf("%w: whatsapp has %w", login.ErrBadValue, login.ErrUnknownAccount), CodeInvalidParams, "account_id is no account of this network"},
		{login.ErrBadValue, CodeBadValue, ""},
		{fmt.Errorf("%w: whatsapp", login.ErrAlreadyLinked), CodeAlreadyLinked, ""},
		{fmt.Errorf("%w: %w", actions.ErrNotSupported, store.ErrNote), CodeNotSupported, ""}, // Ruling P2
		{fmt.Errorf("chat !r is on x, which %w", engine.ErrStarting), CodeNotConnected, ""},
		{fmt.Errorf("chat !r is on x, which %w", engine.ErrNotRunning), CodeNotRunning, ""},
		{fmt.Errorf("not a person of this chat's network: %w", store.ErrNotFound), CodeNotFound, ""},
		{fmt.Errorf("%w: the bridge couldn't make the one-to-one chat", actions.ErrNetworkRefused), CodeNetworkRefused, ""},
	} {
		e, unknown := classify(tc.err)
		require.False(t, unknown, "%v", tc.err)
		require.Equal(t, tc.code, e.Code, "%v", tc.err)
		require.Equal(t, errorMessages[tc.code], e.Message, "%v", tc.err)
		if tc.reason == "" {
			require.Nil(t, e.Data, "%v", tc.err)
		} else {
			require.Equal(t, map[string]string{"reason": tc.reason}, e.Data, "%v", tc.err)
		}
	}

	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	ctx := context.Background()
	note := w.put(t, "$timernote", contact, "m.room.message",
		`{"msgtype":"m.notice","body":"","com.beeper.action_message":{"type":"disappearing_timer","timer":86400000}}`, time.Now())
	c.fails(CodeNotSupported, "room.setUnreadFrom", map[string]any{"event_id": note})
	c.fails(CodeNotFound, "room.setUnreadFrom", map[string]any{"event_id": "$nope"})
	c.fails(CodeNotFound, "room.setTyping", map[string]any{"room_id": "!nope:courier.local", "typing": true})
	c.fails(CodeNotFound, "room.directChat", map[string]any{"room_id": "!nope:courier.local", "user_id": contact})
	w.direct(t)
	c.fails(CodeNotSupported, "room.directChat", map[string]any{"room_id": w.room, "user_id": contact}) // a one-to-one chat
	// The account works: signing it in again is refused, and so is the network's first with neither option.
	require.NoError(t, w.s.SetLoginState(ctx, "whatsapp", string(w.waLogin.ID), loginState("CONNECTED", string(w.waLogin.ID), "Test Account", "")))
	c.fails(CodeAlreadyLinked, "login.start", map[string]any{"network": "whatsapp", "flow": fakenet.ScriptFlow, "account_id": string(w.waLogin.ID)})
	c.fails(CodeAlreadyLinked, "login.start", map[string]any{"network": "whatsapp", "flow": fakenet.ScriptFlow})
	c.fails(CodeNotRunning, "login.start", map[string]any{"network": "telegram", "another": true})
}

// A message of mine carries who has read it (or anything after it), newest receipt first, and whether someone's
// device has it. A receipt for an older message doesn't mark a newer one; others' messages and mine not sent yet
// carry neither.
func TestEventsCarryDeliveredAndReadBy(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	ctx := context.Background()
	base := time.Now().Add(-time.Hour).Truncate(time.Millisecond)
	older := w.put(t, "$mineolder", string(ids.Me), "m.room.message", `{"msgtype":"m.text","body":"first"}`, base)
	newer := w.put(t, "$minenewer", string(ids.Me), "m.room.message", `{"msgtype":"m.text","body":"second"}`, base.Add(time.Minute))
	const ana, bea = "@whatsapp_ana:courier.local", "@whatsapp_bea:courier.local"
	readAt := base.Add(2 * time.Minute)
	require.NoError(t, w.s.SetReceipt(ctx, w.room, ana, older, readAt))                     // Ana read only the first
	require.NoError(t, w.s.SetReceipt(ctx, w.room, bea, newer, time.Time{}))                // Bea read both, at no time
	require.NoError(t, w.s.SetDelivered(ctx, w.room, contact, newer, time.Time{}))          // the second reached a device
	require.NoError(t, w.s.SetReceipt(ctx, w.room, ana, "$not-a-message-here", time.Now())) // dropped
	require.NoError(t, w.s.SetDelivered(ctx, w.room, contact, w.events[0], time.Time{}))    // not mine: dropped

	p := c.page5(w.room)
	o, n := p.event(t, older), p.event(t, newer)
	require.True(t, o.Mine)
	require.False(t, o.Delivered)
	require.True(t, n.Delivered)
	require.Equal(t, []string{"whatsapp_bea"}, readerIDs(n.ReadBy), "a receipt for an older message doesn't mark a newer one")
	require.Equal(t, int64(0), n.ReadBy[0].TS, "a receipt with no time")
	require.ElementsMatch(t, []string{"whatsapp_ana", "whatsapp_bea"}, readerIDs(o.ReadBy), "a receipt counts for what comes before it")
	for _, r := range o.ReadBy {
		if r.UserID == ana {
			require.Equal(t, readAt.UnixMilli(), r.TS)
		}
	}
	for _, id := range w.events {
		e := p.event(t, id)
		require.False(t, e.Delivered)
		require.NotNil(t, e.ReadBy, "[] on the wire, never null")
		require.Empty(t, e.ReadBy, "someone else's message")
	}

	// Newest receipt first: Ana reads the second later than Bea did.
	require.NoError(t, w.s.SetReceipt(ctx, w.room, ana, newer, time.Now()))
	n = c.page5(w.room).event(t, newer)
	require.Equal(t, []string{"whatsapp_ana", "whatsapp_bea"}, readerIDs(n.ReadBy))

	// A message of mine not sent yet has no receipts, even with a reader past it.
	w.wa.SetLoggedIn(w.waLogin, false)
	var sent struct {
		EventID string `json:"event_id"`
	}
	c.ok("message.send", map[string]any{"room_id": w.room, "text": "later"}, &sent)
	require.NoError(t, w.s.SetReceipt(ctx, w.room, bea, sent.EventID, time.Now()))
	e := c.page5(w.room).event(t, sent.EventID)
	require.Equal(t, store.StatusWaiting, e.Status)
	require.Empty(t, e.ReadBy)
	require.False(t, e.Delivered)
}

func readerIDs(rs []wireReader) []string {
	out := []string{}
	for _, r := range rs {
		out = append(out, localpart(r.UserID))
	}
	return out
}

// A reader is named as typing names people (their name in the chat, else their profile's, else their ID's
// localpart), and someone the chat doesn't list by their localpart.
func TestReadByNamesPeopleAsTypingDoes(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	ctx := context.Background()
	const ana, bea, cy, dee = "@whatsapp_ana:courier.local", "@whatsapp_bea:courier.local", "@whatsapp_cy:courier.local",
		"@whatsapp_dee:courier.local"
	require.NoError(t, w.s.SetMember(ctx, w.room, ana, json.RawMessage(`{"membership":"join","displayname":"Ana in the chat"}`)))
	require.NoError(t, w.s.SetMember(ctx, w.room, bea, json.RawMessage(`{"membership":"join"}`)))
	require.NoError(t, w.s.SetMember(ctx, w.room, cy, json.RawMessage(`{"membership":"join"}`)))
	for user, name := range map[string]string{ana: "Ana Profile", bea: "Bea Profile", dee: "Dee Profile"} {
		require.NoError(t, w.s.SetProfile(ctx, user, &name, nil))
	}
	mine := w.put(t, "$mine", string(ids.Me), "m.room.message", `{"msgtype":"m.text","body":"hi"}`, time.Now())
	for _, u := range []string{ana, bea, cy, dee} {
		require.NoError(t, w.s.SetReceipt(ctx, w.room, u, mine, time.Now()))
		w.s.SetTyping(w.room, u, time.Now().Add(time.Minute))
	}
	names := map[string]string{}
	for _, r := range c.page5(w.room).event(t, mine).ReadBy {
		names[r.UserID] = r.Name
	}
	typing := c.row(w.room).Typing // in the order of their IDs: ana, bea, cy, dee
	require.Len(t, typing, 4)
	for i, u := range []string{ana, bea, cy} {
		require.Equal(t, typing[i], names[u], "a member is named as typing names them: %s", localpart(u))
	}
	require.Equal(t, map[string]string{ana: "Ana in the chat", bea: "Bea Profile", cy: "whatsapp_cy", dee: "whatsapp_dee"}, names)
	require.Equal(t, "Dee Profile", typing[3], "typing reads the profile of someone the chat doesn't list; a receipt doesn't")
}

// A page of messages that each carry 50 readers (the most read_by holds) with long names stays under 1 MiB, and
// paging through reads every message once.
func TestPagesWithFiftyReadersEndBeforeOneMiB(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	ctx := context.Background()
	var readers []string
	for i := range store.MaxReaders + 10 {
		u := fmt.Sprintf("@whatsapp_reader%02d:courier.local", i)
		readers = append(readers, u)
		content, err := json.Marshal(map[string]any{"membership": "join", "displayname": strings.Repeat("N", 1500) + fmt.Sprint(i)})
		require.NoError(t, err)
		require.NoError(t, w.s.SetMember(ctx, w.room, u, content))
	}
	base := time.Now().Add(-time.Hour)
	var mine []string
	for i := range 100 {
		mine = append(mine, w.put(t, fmt.Sprintf("$mine%03d", i), string(ids.Me), "m.room.message",
			`{"msgtype":"m.text","body":"hello"}`, base.Add(time.Duration(i)*time.Second)))
	}
	for _, u := range readers { // everyone has read everything
		require.NoError(t, w.s.SetReceipt(ctx, w.room, u, mine[len(mine)-1], time.Now()))
	}
	seen := map[string]int{}
	params := map[string]any{"room_id": w.room, "limit": 100}
	pages := 0
	for {
		m := c.call("room.events", params)
		require.Nil(t, m.Error, "%s", m.raw)
		require.Less(t, len(m.raw), maxPageBytes, "a page stays under 1 MiB")
		var p wirePage5
		require.NoError(t, json.Unmarshal(m.Result, &p))
		pages++
		for _, e := range p.Events {
			seen[e.EventID]++
			if e.Mine {
				require.Len(t, e.ReadBy, store.MaxReaders, "at most 50 readers, the newest")
			}
		}
		if p.Before == nil {
			break
		}
		params = map[string]any{"room_id": w.room, "limit": 100, "before": p.Before}
	}
	require.Greater(t, pages, 1, "the readers' names didn't fit one page")
	for _, id := range mine {
		require.Equal(t, 1, seen[id], "%s read once", id)
	}
}

// Each account's logins come with their own state, name and error, and the account's state sums them up: the login
// that needs the person, else the first reconnecting, else the first. A login the bridge no longer has, and the
// bridge's own state, are not logins.
func TestAccountsListLogins(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	ctx := context.Background()
	first := string(w.waLogin.ID) // fake-login, before whatsapp-second
	second := w.secondAccount(t)
	set := func(account, event, message string) {
		name := "Test Account"
		if account == string(second.ID) {
			name = "Second Account"
		}
		require.NoError(t, w.s.SetLoginState(ctx, "whatsapp", account, loginState(event, account, name, message)))
	}
	require.NoError(t, w.s.SetLoginState(ctx, "whatsapp", "", json.RawMessage(`{"state_event":"UNCONFIGURED","timestamp":1}`)))
	require.NoError(t, w.s.SetLoginState(ctx, "whatsapp", "gone-login", loginState("LOGGED_OUT", "gone-login", "Gone", "signed out")))

	a := c.account("whatsapp")
	require.Equal(t, []wireLogin{
		{AccountID: first, RemoteName: "Test Account", State: "CONNECTED"},
		{AccountID: string(second.ID), RemoteName: "Second Account", State: "CONNECTED"},
	}, a.Logins)
	require.Equal(t, "CONNECTED", a.State)
	require.Equal(t, "Test Account", a.RemoteName, "the first login's")

	for _, tc := range []struct {
		first, second, want, wantErr string
	}{
		{"CONNECTED", "LOGGED_OUT", "LOGGED_OUT", "You were signed out on your phone."},
		{"BAD_CREDENTIALS", "LOGGED_OUT", "BAD_CREDENTIALS", "You were signed out on your phone."},
		{"TRANSIENT_DISCONNECT", "UNKNOWN_ERROR", "UNKNOWN_ERROR", "You were signed out on your phone."},
		{"CONNECTED", "TRANSIENT_DISCONNECT", "TRANSIENT_DISCONNECT", "You were signed out on your phone."},
		{"BACKFILLING", "CONNECTED", "BACKFILLING", "You were signed out on your phone."},
	} {
		set(first, tc.first, "")
		set(string(second.ID), tc.second, tc.wantErr)
		a = c.account("whatsapp")
		require.Equal(t, tc.want, a.State, "%s + %s", tc.first, tc.second)
		require.Equal(t, "Test Account", a.RemoteName)
		require.Equal(t, tc.second, a.Logins[1].State)
		if tc.want == tc.second {
			require.Equal(t, tc.wantErr, a.Error, "the error of the login the state is")
		} else {
			require.Empty(t, a.Error)
		}
	}

	require.Empty(t, c.account("signal").Logins, "running, nothing linked")
	tg := c.account("telegram")
	require.Equal(t, "NOT_STARTED", tg.State)
	require.NotNil(t, tg.Logins)
	require.Empty(t, tg.Logins)
}

// While a network starts, its account is STARTING and so is each login the engine knew from its last run, named,
// with no error: the app shows no banner for any of them.
func TestAccountsListLoginsWhileStarting(t *testing.T) {
	w := startingWorld(t)
	c := dial(t, w.path)
	c.hello()
	a := c.account("whatsapp")
	require.Equal(t, "STARTING", a.State)
	require.Equal(t, "Test Account", a.RemoteName)
	require.Equal(t, []wireLogin{{AccountID: "whatsapp-login", RemoteName: "Test Account", State: "STARTING"}}, a.Logins)
}

// login.start signs in beside the accounts (another), or one of them again (account_id) when Reconnect would fix it.
// The complete step says which account it became, and when it isn't the one asked for (Ruling 11).
func TestLoginStartTakesAnotherAndAnAccount(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	ctx := context.Background()
	account := string(w.waLogin.ID)
	require.NoError(t, w.s.SetLoginState(ctx, "whatsapp", account, loginState("CONNECTED", account, "Test Account", "")))

	type step struct {
		LoginID      string `json:"login_id"`
		Type         string `json:"type"`
		AccountID    string `json:"account_id"`
		OtherAccount bool   `json:"other_account"`
	}
	complete := func(accountID string) *bridgev2.LoginStep {
		return &bridgev2.LoginStep{
			Type: bridgev2.LoginStepTypeComplete, StepID: "fi.mau.whatsapp.complete",
			CompleteParams: &bridgev2.LoginCompleteParams{
				UserLoginID: networkid.UserLoginID(accountID),
				UserLogin:   &bridgev2.UserLogin{UserLogin: &database.UserLogin{ID: networkid.UserLoginID(accountID), RemoteName: "Someone"}},
			},
		}
	}

	w.wa.Script = &fakenet.ScriptedLogin{Steps: []*bridgev2.LoginStep{qrStep(), complete("whatsapp-second")}}
	var s step
	c.ok("login.start", map[string]any{"network": "whatsapp", "flow": fakenet.ScriptFlow, "another": true}, &s)
	require.Equal(t, "display_and_wait", s.Type)
	c.ok("login.wait", map[string]any{"login_id": s.LoginID}, &s)
	require.Equal(t, step{LoginID: s.LoginID, Type: "complete", AccountID: "whatsapp-second"}, s, "a new account, beside the first")

	// Signed out: it can be signed in again by its ID, and scanning with another phone says so.
	require.NoError(t, w.s.SetLoginState(ctx, "whatsapp", account, loginState("LOGGED_OUT", account, "Test Account", "signed out")))
	w.wa.Script = &fakenet.ScriptedLogin{Steps: []*bridgev2.LoginStep{qrStep(), complete("whatsapp-third")}}
	c.ok("login.start", map[string]any{"network": "whatsapp", "flow": fakenet.ScriptFlow, "account_id": account}, &s)
	c.ok("login.wait", map[string]any{"login_id": s.LoginID}, &s)
	require.Equal(t, step{LoginID: s.LoginID, Type: "complete", AccountID: "whatsapp-third", OtherAccount: true}, s)

	w.wa.Script = &fakenet.ScriptedLogin{Steps: []*bridgev2.LoginStep{qrStep(), complete(account)}}
	c.ok("login.start", map[string]any{"network": "whatsapp", "flow": fakenet.ScriptFlow, "account_id": account}, &s)
	m := c.call("login.wait", map[string]any{"login_id": s.LoginID})
	require.Nil(t, m.Error)
	var raw map[string]any
	require.NoError(t, json.Unmarshal(m.Result, &raw))
	require.Equal(t, account, raw["account_id"])
	require.NotContains(t, raw, "other_account", "the account asked for: left out")
}

// The row's account tag shows only while the network has more than one account, and only on a chat that is one
// account's own: a chat every account shares has none.
func TestRowsCarryTheAccountNameOnlyWithTwoAccounts(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	ctx := context.Background()
	require.NoError(t, w.s.SetRoomLogin(ctx, w.room, string(w.waLogin.ID)))
	const shared = "!shared:courier.local"
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: shared, Network: "whatsapp", Name: "A group"}))
	require.NoError(t, w.s.SetLoginState(ctx, "whatsapp", string(w.waLogin.ID), loginState("CONNECTED", string(w.waLogin.ID), "Test Account", "")))

	type tagged struct {
		LoginName     string `json:"login_name"`
		PreviewStatus string `json:"preview_status"`
	}
	tag := func(roomID string) tagged {
		var p struct {
			Rooms []tagged `json:"rooms"`
		}
		c.ok("inbox.list", map[string]any{"room_ids": []string{roomID}}, &p)
		require.Len(t, p.Rooms, 1)
		return p.Rooms[0]
	}
	require.NoError(t, w.s.SetLoginState(ctx, "whatsapp", "gone-login", loginState("LOGGED_OUT", "gone-login", "Gone", "")))
	require.Empty(t, tag(w.room).LoginName, "one account: a stale row of an account the bridge has deleted doesn't make two")
	w.secondAccount(t)
	require.Equal(t, "Test Account", tag(w.room).LoginName)
	require.Empty(t, tag(shared).LoginName, "a chat every account shares")

	// The row says how far my newest message has got.
	mine := w.put(t, "$mynewest", string(ids.Me), "m.room.message", `{"msgtype":"m.text","body":"hi"}`, time.Now())
	require.Equal(t, "sent", tag(w.room).PreviewStatus)
	require.NoError(t, w.s.SetDelivered(ctx, w.room, contact, mine, time.Time{}))
	require.Equal(t, "delivered", tag(w.room).PreviewStatus)
	require.NoError(t, w.s.SetReceipt(ctx, w.room, contact, mine, time.Now()))
	require.Equal(t, "seen", tag(w.room).PreviewStatus)
}

// A new message while the chat's account is down answers at once, waiting (not -32018 after a wait), shows as
// waiting, and message.undo takes it back.
func TestSendWhileDownAnswersWaiting(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	w.wa.SetLoggedIn(w.waLogin, false)

	var sent struct {
		EventID string `json:"event_id"`
	}
	c.ok("message.send", map[string]any{"room_id": w.room, "text": "On my way"}, &sent)
	e := c.page5(w.room).event(t, sent.EventID)
	require.Equal(t, "waiting", e.Status)
	require.Empty(t, e.StatusReason, "just waiting: the chat has its account")

	var file struct {
		EventID string `json:"event_id"`
	}
	c.ok("message.sendFile", map[string]any{"room_id": w.room, "path": aFile(t)}, &file)
	require.Equal(t, "waiting", c.page5(w.room).event(t, file.EventID).Status)

	var draft struct {
		Text string `json:"text"`
	}
	c.ok("message.undo", map[string]any{"event_id": sent.EventID}, &draft)
	require.Equal(t, "On my way", draft.Text)
	for _, ev := range c.page5(w.room).Events {
		require.NotEqual(t, sent.EventID, ev.EventID, "taken back")
	}
}

// A waiting message in a chat none of my accounts is in any more can't go until one is: it says so ("no account")
// rather than waiting with nothing to say. That is a chat of an account that has gone, and a chat every account
// shares whose only account of mine in it has gone.
func TestWaitingInAChatWithNoAccountSaysSo(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	ctx := context.Background()
	const orphan = "!orphan:courier.local"
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: orphan, Network: "whatsapp", Name: "Gone account's chat", IsDirect: true}))
	require.NoError(t, w.s.SetRoomLogin(ctx, orphan, "gone-login"))
	var sent struct {
		EventID string `json:"event_id"`
	}
	c.ok("message.send", map[string]any{"room_id": orphan, "text": "hello?"}, &sent)
	e := c.page5(orphan).event(t, sent.EventID)
	require.Equal(t, "waiting", e.Status)
	require.Equal(t, "no account", e.StatusReason)

	// A group every account shares (no receiver), that only an account now gone was in: no row of mine is in it.
	h, ok := w.eng.Host("whatsapp")
	require.True(t, ok)
	w.wa.IncomingShared(w.waLogin, "group1", "contact", "g0", "hello all")
	wait, cancel := context.WithTimeout(ctx, 5*time.Second) // a deadlock guard, not a measure
	defer cancel()
	stored, err := fakenet.RoomWith(wait, w.s, "hello all") // woken by the store's feed
	require.NoError(t, err, "the bridge never stored the group")
	group := stored.ID
	w.wa.SetLoggedIn(w.waLogin, false) // so the messages wait rather than go
	c.ok("message.send", map[string]any{"room_id": group, "text": "still here"}, &sent)
	e = c.page5(group).event(t, sent.EventID)
	require.Equal(t, "waiting", e.Status)
	require.Empty(t, e.StatusReason, "an account of mine is in it: just waiting")
	ups, err := h.Bridge.DB.UserPortal.GetAllForUserInPortal(ctx, ids.Me, networkid.PortalKey{ID: "group1"})
	require.NoError(t, err)
	require.NotEmpty(t, ups)
	for _, up := range ups {
		require.NoError(t, h.Bridge.DB.UserPortal.Delete(ctx, up))
	}
	e = c.page5(group).event(t, sent.EventID)
	require.Equal(t, "waiting", e.Status)
	require.Equal(t, "no account", e.StatusReason, "said as the page is read, for a message already waiting")
}

// room.setTyping reaches the chat's network while it is connected and is nothing (and no error) while it is down;
// room.setUnreadFrom makes the count run from the message; room.directChat finds Courier's own one-to-one chat.
func TestPresenceMethodsOverTheSocket(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	ctx := context.Background()

	c.ok("room.setTyping", map[string]any{"room_id": w.room, "typing": true}, nil)
	require.True(t, received(t, w.wa.Typings).Typing)
	c.ok("room.setTyping", map[string]any{"room_id": w.room, "typing": false}, nil)
	require.False(t, received(t, w.wa.Typings).Typing)
	w.wa.SetLoggedIn(w.waLogin, false)
	c.ok("room.setTyping", map[string]any{"room_id": w.room, "typing": true}, nil) // down: told nothing
	// The sync point: back up, a stop then a start go out in order through the chat's one drainer. What this shows is
	// that the down call left no typing behind: had it marked me as typing, that stop would be the first thing heard.
	// It can't tell a start handed over while down from the later one; that the down network is told nothing is the
	// actions' TestTypingToADownNetworkIsNothing.
	w.wa.SetLoggedIn(w.waLogin, true)
	c.ok("room.setTyping", map[string]any{"room_id": w.room, "typing": false}, nil)
	c.ok("room.setTyping", map[string]any{"room_id": w.room, "typing": true}, nil)
	require.True(t, received(t, w.wa.Typings).Typing, "the first the network hears after it was down is the new start")

	c.ok("room.markRead", map[string]any{"room_id": w.room}, nil)
	c.ok("room.setUnreadFrom", map[string]any{"event_id": w.events[1]}, nil)
	require.Equal(t, 2, c.row(w.room).Unread, "from the second of three messages on")

	const group = "!group:courier.local"
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: group, Network: "whatsapp", Name: "Lunch group", LoginID: string(w.waLogin.ID)}))
	require.NoError(t, w.s.SetMember(ctx, group, contact, json.RawMessage(`{"membership":"join"}`)))
	w.direct(t)
	var res struct {
		RoomID string `json:"room_id"`
	}
	c.ok("room.directChat", map[string]any{"room_id": group, "user_id": contact}, &res)
	require.Equal(t, w.room, res.RoomID)
	c.fails(CodeNotFound, "room.directChat", map[string]any{"room_id": group, "user_id": "@whatsapp_stranger:courier.local"})
}

// The receipt change reaches the app as its own kind, naming the chat.
func TestReceiptChangesAreNotified(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	mine := w.put(t, "$mine", string(ids.Me), "m.room.message", `{"msgtype":"m.text","body":"hi"}`, time.Now())
	require.NoError(t, w.s.SetDelivered(context.Background(), w.room, contact, mine, time.Time{}))
	got := c.changed(func(ch changed) bool { return ch.Kind == "receipt" })
	require.Equal(t, changed{Kind: "receipt", RoomID: w.room}, got)
}

// A chat deleted between reading its page and asking whether it has an account has no reason to give: the page still
// answers, rather than not_found.
func TestNoAccountReasonOfAChatGoneIsNone(t *testing.T) {
	w := newWorld(t)
	reason, err := w.deps.noAccountReason(context.Background(), "!deleted:courier.local")
	require.NoError(t, err)
	require.Empty(t, reason)
}

// B3: a message of mine I unsent carries no read_by and no delivered, even though receipts and a delivery for it
// were stored: the protocol's read_by is for my messages that have gone and are still there. The unsend's redaction
// is on a newer page than the message here, so the page alone doesn't know it.
func TestAMessageIUnsentCarriesNoReceipts(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	ctx := context.Background()
	base := time.Now().Add(-time.Hour).Truncate(time.Millisecond)
	unsent := w.put(t, "$unsent", string(ids.Me), "m.room.message", `{"msgtype":"m.text","body":"oops"}`, base)
	kept := w.put(t, "$kept", string(ids.Me), "m.room.message", `{"msgtype":"m.text","body":"fine"}`, base.Add(time.Minute))
	const ana = "@whatsapp_ana:courier.local"
	require.NoError(t, w.s.SetReceipt(ctx, w.room, ana, kept, time.Time{}))
	require.NoError(t, w.s.SetDelivered(ctx, w.room, contact, unsent, time.Time{}))
	w.put(t, "$unsend", string(ids.Me), "m.room.redaction", `{"redacts":"$unsent"}`, base.Add(2*time.Minute))
	redacted, err := w.s.Redacted(ctx, unsent)
	require.NoError(t, err)
	require.True(t, redacted)

	var page wirePage5
	c.ok("room.events", map[string]any{"room_id": w.room, "around": unsent, "limit": 1}, &page)
	e := page.event(t, unsent)
	for _, other := range page.Events {
		require.NotEqual(t, "$unsend", other.EventID, "the page doesn't reach the unsend")
	}
	require.Empty(t, e.ReadBy, "an unsent message has no readers")
	require.False(t, e.Delivered)
	require.Equal(t, []string{"whatsapp_ana"}, readerIDs(c.page5(w.room).event(t, kept).ReadBy), "the one still there has")
}

func TestRPCRoomInfoGroupActionsAndReportSpam(t *testing.T) {
	w := newWorld(t)
	w.can(t, everything())
	c := dial(t, w.path)
	c.hello()
	ctx := context.Background()

	// Seed a group chat bound to the live whatsapp portal ("chat1") so bridgev2 group actions work over RPC.
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{
		ID: w.room, Network: "whatsapp", Name: "Original Group", Topic: "Initial topic",
		IsDirect: false, LoginID: string(w.waLogin.ID),
	}))
	plRaw := json.RawMessage(`{"users":{"@me:courier.local":100,"@whatsapp_contact:courier.local":50},"users_default":0}`)
	_, err := w.s.SetState(ctx, w.room, "m.room.power_levels", "", plRaw)
	require.NoError(t, err)
	require.NoError(t, w.s.SetMember(ctx, w.room, string(ids.Me), json.RawMessage(`{"membership":"join","displayname":"Me"}`)))
	require.NoError(t, w.s.SetMember(ctx, w.room, contact, json.RawMessage(`{"membership":"join","displayname":"Alice Example"}`)))
	require.NoError(t, w.s.SetProfileExtraMeta(ctx, contact, []string{"tel:+15550100101"}, "America/Los_Angeles", false))
	w.put(t, "$link1", contact, "m.room.message", `{"msgtype":"m.text","body":"See https://example.com/spec"}`, time.UnixMilli(1700000000000))

	// 1. room.info
	var info struct {
		RoomID     string `json:"room_id"`
		Name       string `json:"name"`
		RemoteName string `json:"remote_name"`
		LocalName  string `json:"local_name"`
		Topic      string `json:"topic"`
		Network    string `json:"network"`
		Members    []struct {
			UserID      string   `json:"user_id"`
			Name        string   `json:"name"`
			PowerLevel  int      `json:"power_level"`
			IsAdmin     bool     `json:"is_admin"`
			Identifiers []string `json:"identifiers"`
			Timezone    string   `json:"tz"`
		} `json:"members"`
		SharedLinks []struct {
			URL  string `json:"url"`
			Host string `json:"host"`
		} `json:"shared_links"`
		Features struct {
			CanSetName  bool `json:"can_set_name"`
			CanSetTopic bool `json:"can_set_topic"`
			CanInvite   bool `json:"can_invite"`
			CanKick     bool `json:"can_kick"`
			CanLeave    bool `json:"can_leave"`
			CanDelete   bool `json:"can_delete"`
		} `json:"features"`
	}
	c.ok("room.info", map[string]any{"room_id": w.room}, &info)
	require.Equal(t, w.room, info.RoomID)
	require.Equal(t, "Original Group", info.Name)
	require.Equal(t, "Original Group", info.RemoteName)
	require.GreaterOrEqual(t, len(info.Members), 2)
	require.NotEmpty(t, info.SharedLinks)
	require.Equal(t, "https://example.com/spec", info.SharedLinks[0].URL)
	require.True(t, info.Features.CanSetName)
	require.True(t, info.Features.CanInvite)
	require.True(t, info.Features.CanKick)

	// 2. room.setLocalOverride
	c.ok("room.setLocalOverride", map[string]any{
		"room_id": w.room, "local_name": "My Custom Name", "local_avatar_path": "",
	}, nil)
	c.ok("room.info", map[string]any{"room_id": w.room}, &info)
	require.Equal(t, "My Custom Name", info.Name)
	require.Equal(t, "Original Group", info.RemoteName)
	require.Equal(t, "My Custom Name", info.LocalName)

	// 3. room.setName, room.setTopic, room.setAvatar, room.invite, room.kick, room.setAdmin
	c.ok("room.setLocalOverride", map[string]any{
		"room_id": w.room, "local_name": "", "local_avatar_path": "",
	}, nil)
	c.ok("room.setName", map[string]any{"room_id": w.room, "text": "Weekend Hike"}, nil)
	c.ok("room.setTopic", map[string]any{"room_id": w.room, "text": "Bring water"}, nil)
	avatarFile := filepath.Join(t.TempDir(), "avatar.png")
	require.NoError(t, os.WriteFile(avatarFile, []byte("\x89PNG\r\n\x1a\n"), 0o600))
	c.ok("room.setAvatar", map[string]any{"room_id": w.room, "path": avatarFile}, nil)
	c.ok("room.invite", map[string]any{"room_id": w.room, "user_ids": []string{"@whatsapp_carol:courier.local"}}, nil)
	c.ok("room.kick", map[string]any{"room_id": w.room, "user_id": "@whatsapp_carol:courier.local", "reason": "wrong group"}, nil)
	c.ok("room.setAdmin", map[string]any{"room_id": w.room, "user_id": contact, "is_admin": true}, nil)
	// A 1:1 direct chat cannot promote admins -> room.setAdmin maps ErrNotSupported to CodeNotSupported.
	const directRoom = "!direct1:courier.local"
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{
		ID: directRoom, Network: "whatsapp", Name: "Alice DM", IsDirect: true, LoginID: string(w.waLogin.ID),
	}))
	c.fails(CodeNotSupported, "room.setAdmin", map[string]any{"room_id": directRoom, "user_id": contact, "is_admin": true})

	// 4. room.export path validation (rejects relative path, symlink, and directory) and valid export
	tmpDir := t.TempDir()
	exportPath := filepath.Join(tmpDir, "chat-export.txt")
	var exported struct {
		MessagesWritten int `json:"messages_written"`
	}
	c.ok("room.export", map[string]any{"room_id": w.room, "path": exportPath}, &exported)
	require.GreaterOrEqual(t, exported.MessagesWritten, 1)
	c.fails(CodeInvalidParams, "room.export", map[string]any{"room_id": w.room, "path": "relative/export.txt"})
	c.fails(CodeInvalidParams, "room.export", map[string]any{"room_id": w.room, "path": tmpDir})
	otherDir := t.TempDir()
	symDir := filepath.Join(tmpDir, "sym")
	require.NoError(t, os.Symlink(otherDir, symDir))
	c.fails(CodeInvalidParams, "room.export", map[string]any{"room_id": w.room, "path": filepath.Join(symDir, "out.txt")})

	// 5. people.contacts, people.resolve, room.createGroup, blast.send
	w.wa.Contacts = []fakenet.Contact{{
		UserID:      "bob",
		Name:        "Bob Example",
		Identifiers: []string{"tel:+15550100202"},
	}}
	var contactsRes struct {
		Contacts []actions.ContactCandidate `json:"contacts"`
	}
	c.ok("people.contacts", map[string]any{"network": "whatsapp", "query": "bob"}, &contactsRes)
	require.Len(t, contactsRes.Contacts, 1)
	require.Equal(t, "Bob Example", contactsRes.Contacts[0].Name)

	var resolved actions.ContactCandidate
	c.ok("people.resolve", map[string]any{
		"network": "whatsapp", "identifier": "+15550100202", "start_chat": true,
	}, &resolved)
	require.Equal(t, "@whatsapp_+15550100202:courier.local", resolved.UserID)
	require.NotEmpty(t, resolved.RoomID)

	var createdGroup struct {
		RoomID string `json:"room_id"`
	}
	c.ok("room.createGroup", map[string]any{
		"network": "whatsapp", "name": "Trail Crew", "user_ids": []string{contact, resolved.UserID},
	}, &createdGroup)
	require.NotEmpty(t, createdGroup.RoomID)

	var blastRes struct {
		Events []struct {
			EventID string `json:"event_id"`
			RoomID  string `json:"room_id"`
		} `json:"events"`
	}
	c.ok("blast.send", map[string]any{
		"messages": []map[string]any{
			{"room_id": w.room, "text": "Heads up, Alice!"},
			{"room_id": resolved.RoomID, "text": "Heads up, Bob!"},
		},
	}, &blastRes)
	require.Len(t, blastRes.Events, 2)

	// 6. room.reportSpam
	c.ok("room.reportSpam", map[string]any{"room_id": createdGroup.RoomID, "leave_or_delete": false}, nil)
	rm, ok, err := w.s.GetRoom(ctx, createdGroup.RoomID)
	require.NoError(t, err)
	require.True(t, ok)
	require.True(t, rm.Hidden)

	// 7. Failing fakenet leave returns -32027 (network_refused) with no network error text in message or data.
	w.wa.Refuse = true
	t.Cleanup(func() { w.wa.Refuse = false })
	we := c.fails(CodeNetworkRefused, "room.leave", map[string]any{"room_id": w.room})
	require.Equal(t, "network refused", we.Message)
	require.Empty(t, we.Data)
}
