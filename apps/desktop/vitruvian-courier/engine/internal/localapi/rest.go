// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localapi

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/ids"
)

// The REST part of the local API: two read-only endpoints of the reference app's /v1 API, the two HomeSpeaker
// reads (apps/desktop/home-speaker, BeeperClient.swift), in the reference app's shape. They sit behind the same
// guards as the MCP endpoint (guard: no browser, a loopback Host unless Remote Access is on; requireToken: a token
// the person approved, looked up on every request), and answer from the same code the MCP tools run: get_accounts's
// accounts.list, and search_messages's search (findMessages), so a message reads as it does now (its latest edit)
// and a deleted one is never listed. Nothing here sends, changes or deletes anything.

const (
	// AccountsPath lists the accounts, as the reference app's GET /v1/accounts.
	AccountsPath = "/v1/accounts"
	// MessagesSearchPath searches or lists messages, as the reference app's GET /v1/messages/search.
	MessagesSearchPath = "/v1/messages/search"
	// restSearchMax is the most messages one page of GET /v1/messages/search holds: the reference app's limit.
	restSearchMax = 20
)

// restAccount is one account as GET /v1/accounts gives it.
type restAccount struct {
	AccountID string `json:"accountID"`
	Bridge    struct {
		ID       string `json:"id"`
		Type     string `json:"type"`
		Provider string `json:"provider"`
	} `json:"bridge"`
	Network string `json:"network"`
	User    struct {
		ID       string `json:"id"`
		IsSelf   bool   `json:"isSelf"`
		FullName string `json:"fullName,omitempty"`
	} `json:"user"`
	Status string `json:"status"`
}

// restMessage is one message as GET /v1/messages/search gives it: the MCP tools' message, and what the reference
// app's REST API adds to it.
type restMessage struct {
	messageJSON
	SortKey   string   `json:"sortKey"`
	Type      string   `json:"type"` // TEXT NOTICE IMAGE VIDEO VOICE AUDIO FILE STICKER LOCATION
	IsHidden  bool     `json:"isHidden"`
	IsDeleted bool     `json:"isDeleted"`
	Mentions  []string `json:"mentions"` // user IDs, and @room for everyone
}

// restSearch is GET /v1/messages/search's answer.
type restSearch struct {
	Items        []restMessage       `json:"items"`
	Chats        map[string]chatJSON `json:"chats"`
	HasMore      bool                `json:"hasMore"`
	OldestCursor *string             `json:"oldestCursor"`
	NewestCursor *string             `json:"newestCursor"`
}

// rest is one REST endpoint: GET (or HEAD) only, its answer as JSON, its failure as {"error", "message"}. The log
// line says which endpoint, how long it took and how it ended, and nothing else.
func (s *Server) rest(name string, f func(ctx context.Context, q url.Values) (any, error)) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		outcome := "ok"
		defer func() {
			if rec := recover(); rec != nil {
				outcome = "panic"
				restError(w, http.StatusInternalServerError, "Vitruvian Courier couldn't do that (an internal error).")
			}
			ev := s.log.Info()
			if outcome == "panic" {
				ev = s.log.Warn()
			}
			ev.Str("endpoint", name).Dur("took", time.Since(started)).Str("outcome", outcome).Msg("rest call")
		}()
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			outcome = "method"
			w.Header().Set("Allow", "GET, HEAD")
			restError(w, http.StatusMethodNotAllowed, "Only GET is served here.")
			return
		}
		out, err := f(r.Context(), r.URL.Query())
		if err != nil {
			code := restStatus(err)
			outcome = "error"
			restError(w, code, plain(err))
			return
		}
		b, err := json.Marshal(out)
		if err != nil {
			outcome = "error"
			restError(w, http.StatusInternalServerError, "Vitruvian Courier couldn't do that (an internal error).")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		_, _ = w.Write(b)
	})
}

// restStatus is the HTTP status of a failure: a bad parameter is 400, a chat or message that isn't there 404, and
// anything else 500.
func restStatus(err error) int {
	var te *toolError
	if errors.As(err, &te) {
		return http.StatusBadRequest
	}
	var c coded
	if errors.As(err, &c) {
		switch c.ProtocolCode() {
		case codeInvalidParams:
			return http.StatusBadRequest
		case codeNotFound:
			return http.StatusNotFound
		}
	}
	return http.StatusInternalServerError
}

// restError answers with status and {"error": a short code, "message": msg in plain words}. HomeSpeaker shows
// message; error is the same short code the guards answer with.
func restError(w http.ResponseWriter, status int, msg string) {
	code := "internal_error"
	switch status {
	case http.StatusBadRequest:
		code = "bad_request"
	case http.StatusNotFound:
		code = "not_found"
	case http.StatusMethodNotAllowed:
		code = "method_not_allowed"
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": code, "message": msg})
}

// restAccounts is GET /v1/accounts: every account signed in, as a list. The bridge's type is Vitruvian Courier's name for the
// network (whatsapp, slack, gchat, …); the user is me, as messages' mentions and senderID name me.
func (s *Server) restAccounts(ctx context.Context, _ url.Values) (any, error) {
	l := s.lookups(ctx)
	if err := l.load(); err != nil {
		return nil, err
	}
	out := []restAccount{}
	for _, a := range l.accounts {
		for _, login := range a.Logins {
			var r restAccount
			r.AccountID = login.AccountID
			r.Bridge.ID, r.Bridge.Type, r.Bridge.Provider = a.Network, a.Network, "local"
			r.Network = cmp.Or(a.DisplayName, a.Network)
			r.User.ID, r.User.IsSelf, r.User.FullName = string(ids.Me), true, login.RemoteName
			r.Status = login.State
			out = append(out, r)
		}
	}
	return out, nil
}

// restSearchMessages is GET /v1/messages/search. Its parameters are search_messages's arguments, as query
// parameters: a list is the parameter repeated (accountIDs=a&accountIDs=b, or accountIDs[]=…). Unlike the tool,
// query may be left out: then the filters pick the messages (dateAfter, say), newest first. dateAfter is strictly
// after, as the reference app's is; limit is at most 20.
func (s *Server) restSearchMessages(ctx context.Context, q url.Values) (any, error) {
	a, err := searchArgsFromQuery(q)
	if err != nil {
		return nil, err
	}
	noQuery := a.Query == nil || strings.TrimSpace(*a.Query) == ""
	picks := a.DateAfter != nil || a.DateBefore != nil || len(a.ChatIDs) > 0 || a.Sender != nil || a.ChatType != nil ||
		len(a.MediaTypes) > 0
	if noQuery && !picks {
		return nil, fail("Give a query, or a filter that picks messages: dateAfter, dateBefore, chatIDs, sender, chatType or mediaTypes.")
	}
	f, err := s.findMessages(ctx, a)
	if err != nil {
		return nil, err
	}
	out := restSearch{Items: []restMessage{}, Chats: map[string]chatJSON{}, HasMore: f.hasMore, OldestCursor: f.oldest, NewestCursor: f.newest}
	for _, h := range f.hits {
		out.Items = append(out.Items, s.restMessage(f.l, h))
	}
	for id, r := range f.rows {
		out.Chats[id] = f.l.chat(r)
	}
	return out, nil
}

// searchArgsFromQuery reads GET /v1/messages/search's query parameters. A value of the wrong form is a 400 naming
// the parameter, never its value.
func searchArgsFromQuery(q url.Values) (searchMessagesArgs, error) {
	var a searchMessagesArgs
	str := func(name string) *string {
		if v, ok := q[name]; ok && len(v) > 0 && v[0] != "" {
			return &v[0]
		}
		return nil
	}
	list := func(name string) []string {
		var out []string
		for _, key := range []string{name, name + "[]"} {
			for _, v := range q[key] {
				for part := range strings.SplitSeq(v, ",") {
					if part = strings.TrimSpace(part); part != "" {
						out = append(out, part)
					}
				}
			}
		}
		return out
	}
	boolean := func(name string) (*bool, error) {
		v := str(name)
		if v == nil {
			return nil, nil
		}
		b, err := strconv.ParseBool(*v)
		if err != nil {
			return nil, fail("%s must be true or false.", name)
		}
		return &b, nil
	}
	a.Query, a.ChatType, a.Cursor, a.Direction, a.Sender = str("query"), str("chatType"), str("cursor"), str("direction"), str("sender")
	a.AccountIDs, a.ChatIDs, a.MediaTypes = list("accountIDs"), list("chatIDs"), list("mediaTypes")
	var err error
	if a.ExcludeLowPriority, err = boolean("excludeLowPriority"); err != nil {
		return a, err
	}
	if a.IncludeMuted, err = boolean("includeMuted"); err != nil {
		return a, err
	}
	limit := restSearchMax
	if v := str("limit"); v != nil {
		n, err := strconv.Atoi(*v)
		if err != nil {
			return a, fail("limit must be a whole number.")
		}
		limit = min(max(n, 1), restSearchMax)
	}
	a.Limit = &limit
	a.DateBefore = str("dateBefore")
	if v := str("dateAfter"); v != nil {
		// Strictly after: the store's lower bound is inclusive, to the millisecond.
		t, err := time.Parse(time.RFC3339, *v)
		if err != nil {
			return a, fail("dateAfter must be a date and time in RFC 3339 form, such as 2026-11-01T09:30:00Z.")
		}
		next := t.Truncate(time.Millisecond).Add(time.Millisecond).UTC().Format(time.RFC3339Nano)
		a.DateAfter = &next
	}
	return a, nil
}

// restMessage is a search hit as GET /v1/messages/search gives it: its whole text as it reads now, its type in the
// reference app's words, and who it mentions.
func (s *Server) restMessage(l *lookups, h wireHit) restMessage {
	typ, content := msgType, json.RawMessage(`{"msgtype":"m.text"}`)
	if e, ok, err := s.store.GetEvent(l.ctx, h.EventID); err == nil && ok {
		typ, content = e.Type, e.Content
	}
	now, edited := s.current(l.ctx, h.EventID, h.RoomID, h.Sender, content)
	m := l.message(h.EventID, h.RoomID, h.Sender, h.SenderName, h.Mine, typ, now, h.TS)
	m.IsEdited = edited
	return restMessage{
		messageJSON: m, SortKey: strconv.FormatInt(h.Seq, 10), Type: restType(typ, now),
		Mentions: mentionsOf(content, now),
	}
}

// restType is a message's type in the reference app's words, upper case.
func restType(typ string, content json.RawMessage) string {
	if typ == stickerType {
		return "STICKER"
	}
	var c struct {
		MsgType string          `json:"msgtype"`
		Voice   json.RawMessage `json:"org.matrix.msc3245.voice"`
	}
	_ = json.Unmarshal(content, &c)
	switch c.MsgType {
	case "m.notice":
		return "NOTICE"
	case "m.image":
		return "IMAGE"
	case "m.video":
		return "VIDEO"
	case "m.audio":
		if len(c.Voice) > 0 && string(c.Voice) != "null" {
			return "VOICE"
		}
		return "AUDIO"
	case "m.file":
		return "FILE"
	case "m.location":
		return "LOCATION"
	}
	return "TEXT"
}

// mentionsOf is who the message mentions, as it was sent and as it reads now: each user ID in m.mentions, and
// @room when it mentions everyone. Never null.
func mentionsOf(contents ...json.RawMessage) []string {
	out := []string{}
	add := func(id string) {
		for _, have := range out {
			if have == id {
				return
			}
		}
		out = append(out, id)
	}
	for _, raw := range contents {
		var c struct {
			Mentions *struct {
				UserIDs []string `json:"user_ids"`
				Room    bool     `json:"room"`
			} `json:"m.mentions"`
		}
		if json.Unmarshal(raw, &c) != nil || c.Mentions == nil {
			continue
		}
		for _, id := range c.Mentions.UserIDs {
			if id != "" {
				add(id)
			}
		}
		if c.Mentions.Room {
			add("@room")
		}
	}
	return out
}
