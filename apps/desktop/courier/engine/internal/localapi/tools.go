// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localapi

import (
	"cmp"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/searchtext"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// The engine's protocol codes the tools put in their own words (protocol.json's errors).
const (
	codeInvalidParams = -32602
	codeInternal      = -32603
	codeNotFound      = -32020
	codePinned        = -32021
)

// Limits and defaults of the tools' arguments.
const (
	maxLimit             = 200
	defaultChatsLimit    = 50
	defaultMessagesLimit = 20
	messagesPage         = 20 // list_messages's page
	defaultParticipants  = 20
	maxParticipants      = 500
	enginePage           = 50 // what each engine call asks for while a tool gathers a page
	maxEngineCalls       = 40 // how many engine calls one tool call may make while gathering
	maxSearchChatIDs     = 100
)

// toolError is a tool's failure in plain words: the client gets it as a result with isError, never as a crash.
type toolError struct{ msg string }

func (e *toolError) Error() string { return e.msg }

func fail(format string, args ...any) error { return &toolError{msg: fmt.Sprintf(format, args...)} }

// coded is an engine error with its protocol code (*rpc.Error).
type coded interface {
	error
	ProtocolCode() int
	Reason() string
}

// plain is err in words for the tool's caller. An engine error's message is the protocol's fixed text, which never
// carries what was sent; anything else is an internal error and says no more.
func plain(err error) string {
	var te *toolError
	if errors.As(err, &te) {
		return te.msg
	}
	var c coded
	if errors.As(err, &c) {
		switch c.ProtocolCode() {
		case codeNotFound:
			return "No chat or message with that ID."
		case codePinned:
			return "A pinned chat can't be archived. Unpin it in Courier first."
		case codeInvalidParams:
			if r := c.Reason(); r != "" {
				return "That isn't accepted: " + r + "."
			}
			return "That isn't accepted."
		case codeInternal:
			return "Courier couldn't do that (an internal error)."
		}
		msg := c.Error()
		if msg == "" {
			return "Courier couldn't do that."
		}
		return strings.ToUpper(msg[:1]) + msg[1:] + "."
	}
	return "Courier couldn't do that (an internal error)."
}

type toolFunc func(ctx context.Context, req *mcp.CallToolRequest, args json.RawMessage) (any, error)

// addTools registers every tool with its schema.
func (s *Server) addTools() {
	impl := map[string]toolFunc{
		"get_accounts":        s.getAccounts,
		"search":              s.search,
		"search_chats":        s.searchChats,
		"search_messages":     s.searchMessages,
		"get_chat":            s.getChat,
		"list_messages":       s.listMessages,
		"send_message":        s.sendMessage,
		"archive_chat":        s.archiveChat,
		"set_chat_reminder":   s.setChatReminder,
		"clear_chat_reminder": s.clearChatReminder,
		"focus_app":           s.focusApp,
		"search_docs":         s.searchDocs,
	}
	for _, def := range toolDefs {
		f, ok := impl[def.name]
		if !ok {
			panic("localapi: no implementation for tool " + def.name)
		}
		s.mcp.AddTool(&mcp.Tool{Name: def.name, Description: def.description, InputSchema: json.RawMessage(def.schema)}, s.wrap(def.name, f))
	}
}

// wrap runs one tool: its result as one JSON text block, or its failure as a tool error. A panic is a tool error
// too. The log line says which tool, how long it took and how it ended, and nothing else.
func (s *Server) wrap(name string, f toolFunc) mcp.ToolHandler {
	return func(ctx context.Context, req *mcp.CallToolRequest) (res *mcp.CallToolResult, _ error) {
		started := time.Now()
		outcome := "ok"
		defer func() {
			if r := recover(); r != nil {
				outcome = "panic"
				res = errorResult("Courier couldn't do that (an internal error).")
			}
			ev := s.log.Info()
			if outcome == "panic" {
				ev = s.log.Warn()
			}
			ev.Str("tool", name).Dur("took", time.Since(started)).Str("outcome", outcome).Msg("mcp tool call")
		}()
		args := req.Params.Arguments
		if len(args) == 0 || string(args) == "null" {
			args = json.RawMessage("{}")
		}
		out, err := f(ctx, req, args)
		if err != nil {
			outcome = "tool_error"
			return errorResult(plain(err)), nil
		}
		if t, ok := out.(textResult); ok {
			return &mcp.CallToolResult{Content: []mcp.Content{&mcp.TextContent{Text: string(t)}}}, nil
		}
		b, err := json.Marshal(out)
		if err != nil {
			outcome = "tool_error"
			return errorResult("Courier couldn't do that (an internal error)."), nil
		}
		return &mcp.CallToolResult{Content: []mcp.Content{&mcp.TextContent{Text: string(b)}}}, nil
	}
}

func errorResult(msg string) *mcp.CallToolResult {
	return &mcp.CallToolResult{IsError: true, Content: []mcp.Content{&mcp.TextContent{Text: msg}}}
}

// args reads a tool's arguments into v. A wrong type is a tool error naming the argument, never its value.
func args(raw json.RawMessage, v any) error {
	if err := json.Unmarshal(raw, v); err != nil {
		var te *json.UnmarshalTypeError
		if errors.As(err, &te) && te.Field != "" {
			return fail("%s has the wrong type.", te.Field)
		}
		return fail("The arguments don't fit this tool.")
	}
	return nil
}

// call is one engine method, its result read into out.
func (s *Server) call(ctx context.Context, method string, params, out any) error {
	raw, err := s.disp.Dispatch(ctx, method, params)
	if err != nil {
		return err
	}
	if out == nil {
		return nil
	}
	return json.Unmarshal(raw, out)
}

// clampLimit is a limit argument within 1 to maxLimit, def when left out.
func clampLimit(v *int, def int) int {
	if v == nil {
		return def
	}
	return min(max(*v, 1), maxLimit)
}

func boolOr(v *bool, def bool) bool {
	if v == nil {
		return def
	}
	return *v
}

// rfc3339 is a Unix-millisecond time as RFC 3339, in UTC, to the millisecond. 0 is "".
func rfc3339(ms int64) string {
	if ms <= 0 {
		return ""
	}
	return time.UnixMilli(ms).UTC().Format("2006-01-02T15:04:05.000Z07:00")
}

// parseTime reads an RFC 3339 argument as Unix milliseconds; name is the argument, for the error.
func parseTime(name string, v *string) (int64, bool, error) {
	if v == nil || *v == "" {
		return 0, false, nil
	}
	t, err := time.Parse(time.RFC3339, *v)
	if err != nil {
		return 0, false, fail("%s must be a date and time in RFC 3339 form, such as 2026-11-01T09:30:00Z.", name)
	}
	return t.UnixMilli(), true, nil
}

// pageCursor is a page's place, opaque to clients: base64url of {t, id} (a time in Unix ms and the chat's or the
// message's ID), and for a message its seq (s), which breaks ties between messages of the same millisecond.
type pageCursor struct {
	T  int64  `json:"t"`
	ID string `json:"id"`
	S  *int64 `json:"s,omitempty"`
}

func (c pageCursor) String() string {
	b, _ := json.Marshal(c)
	return base64.RawURLEncoding.EncodeToString(b)
}

func parseCursor(v *string) (*pageCursor, error) {
	if v == nil || *v == "" {
		return nil, nil
	}
	b, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(*v, "="))
	var c pageCursor
	if err != nil || json.Unmarshal(b, &c) != nil || c.T < 0 || c.ID == "" {
		return nil, fail("That cursor isn't one Courier handed out.")
	}
	return &c, nil
}

func directionOf(v *string) (after bool, err error) {
	if v == nil || *v == "" || *v == "before" {
		return false, nil
	}
	if *v == "after" {
		return true, nil
	}
	return false, fail("direction must be before or after.")
}

// ---- What the engine answers, as far as the tools read it ----

type wireAccount struct {
	Network     string `json:"network"`
	DisplayName string `json:"display_name"`
	State       string `json:"state"`
	Logins      []struct {
		AccountID  string `json:"account_id"`
		RemoteName string `json:"remote_name"`
		State      string `json:"state"`
	} `json:"logins"`
}

type wireRow struct {
	RoomID       string `json:"room_id"`
	Network      string `json:"network"`
	Name         string `json:"name"`
	IsDirect     bool   `json:"is_direct"`
	LastTS       int64  `json:"last_ts"`
	Unread       int    `json:"unread"`
	Muted        bool   `json:"muted"`
	Pinned       bool   `json:"pinned"`
	Archived     bool   `json:"archived"`
	LowPriority  bool   `json:"low_priority"`
	Hidden       bool   `json:"hidden"`
	MarkedUnread bool   `json:"marked_unread"`
}

type wireEvent struct {
	EventID    string          `json:"event_id"`
	RoomID     string          `json:"room_id"`
	Sender     string          `json:"sender"`
	SenderName string          `json:"sender_name"`
	Mine       bool            `json:"mine"`
	Type       string          `json:"type"`
	Content    json.RawMessage `json:"content"`
	TS         int64           `json:"ts"`
	Seq        int64           `json:"seq"`
}

type wireCursor struct {
	TS  int64 `json:"ts"`
	Seq int64 `json:"seq"`
}

type wirePage struct {
	Events []wireEvent `json:"events"`
	Before *wireCursor `json:"before"`
	After  *wireCursor `json:"after"`
}

type wireHit struct {
	EventID    string `json:"event_id"`
	RoomID     string `json:"room_id"`
	Place      string `json:"place"`
	Sender     string `json:"sender"`
	SenderName string `json:"sender_name"`
	Mine       bool   `json:"mine"`
	TS         int64  `json:"ts"`
	Seq        int64  `json:"seq"`
	Snippet    string `json:"snippet"`
}

type wireHits struct {
	Hits       []wireHit `json:"hits"`
	NextCursor *string   `json:"next_cursor"`
}

// ---- What the tools answer ----

type accountJSON struct {
	AccountID   string `json:"accountID"`
	Network     string `json:"network"`
	DisplayName string `json:"displayName"`
	Status      string `json:"status"`
}

type participantJSON struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	IsAdmin bool   `json:"isAdmin"`
	IsSelf  bool   `json:"isSelf"`
}

type chatJSON struct {
	ID            string            `json:"id"`
	AccountID     string            `json:"accountID"`
	Network       string            `json:"network"`
	Title         string            `json:"title"`
	Type          string            `json:"type"`
	UnreadCount   int               `json:"unreadCount"`
	IsArchived    bool              `json:"isArchived"`
	IsMuted       bool              `json:"isMuted"`
	IsPinned      bool              `json:"isPinned"`
	IsLowPriority bool              `json:"isLowPriority"`
	LastActivity  string            `json:"lastActivity"`
	Participants  []participantJSON `json:"participants,omitempty"`
}

type attachmentJSON struct {
	Type     string `json:"type"`
	FileName string `json:"fileName"`
	MimeType string `json:"mimeType"`
}

type messageJSON struct {
	ID               string           `json:"id"`
	ChatID           string           `json:"chatID"`
	AccountID        string           `json:"accountID"`
	SenderID         string           `json:"senderID"`
	SenderName       string           `json:"senderName"`
	IsSender         bool             `json:"isSender"`
	Timestamp        string           `json:"timestamp"`
	Text             string           `json:"text"`
	Attachments      []attachmentJSON `json:"attachments"`
	ReplyToMessageID string           `json:"replyToMessageID,omitempty"`
	IsEdited         bool             `json:"isEdited,omitempty"` // its text is its latest edit's
}

// lookups caches what several results of one tool call share: the networks' names, each chat's account.
type lookups struct {
	s        *Server
	ctx      context.Context
	accounts []wireAccount
	loaded   bool
	logins   map[string]string // room ID → account ID
}

func (s *Server) lookups(ctx context.Context) *lookups {
	return &lookups{s: s, ctx: ctx, logins: map[string]string{}}
}

func (l *lookups) load() error {
	if l.loaded {
		return nil
	}
	var res struct {
		Accounts []wireAccount `json:"accounts"`
	}
	if err := l.s.call(l.ctx, "accounts.list", nil, &res); err != nil {
		return err
	}
	l.accounts, l.loaded = res.Accounts, true
	return nil
}

// networkName is the network's name for people (WhatsApp), or its own name when the engine doesn't know it.
func (l *lookups) networkName(network string) string {
	if l.load() == nil {
		for _, a := range l.accounts {
			if a.Network == network && a.DisplayName != "" {
				return a.DisplayName
			}
		}
	}
	return network
}

// accountOf is the account a chat is on: its own login, or the network's only one. "" when a chat every account
// of its network shares can't be pinned to one.
func (l *lookups) accountOf(roomID, network string) string {
	if id, ok := l.logins[roomID]; ok {
		return id
	}
	id := ""
	if r, ok, err := l.s.store.GetRoom(l.ctx, roomID); err == nil && ok {
		id = r.LoginID
		if network == "" {
			network = r.Network
		}
	}
	if id == "" && l.load() == nil {
		for _, a := range l.accounts {
			if a.Network == network && len(a.Logins) == 1 {
				id = a.Logins[0].AccountID
			}
		}
	}
	l.logins[roomID] = id
	return id
}

func (l *lookups) chat(r wireRow) chatJSON {
	typ := "group"
	if r.IsDirect {
		typ = "single"
	}
	return chatJSON{
		ID: r.RoomID, AccountID: l.accountOf(r.RoomID, r.Network), Network: l.networkName(r.Network), Title: r.Name,
		Type: typ, UnreadCount: r.Unread, IsArchived: r.Archived, IsMuted: r.Muted, IsPinned: r.Pinned,
		IsLowPriority: r.LowPriority, LastActivity: rfc3339(r.LastTS),
	}
}

// rows is the inbox rows of roomIDs, wherever they are, keyed by room ID.
func (s *Server) rows(ctx context.Context, roomIDs []string) (map[string]wireRow, error) {
	out := map[string]wireRow{}
	for chunk := range slices.Chunk(roomIDs, maxSearchChatIDs) {
		var res struct {
			Rooms []wireRow `json:"rooms"`
		}
		if err := s.call(ctx, "inbox.list", map[string]any{"room_ids": chunk}, &res); err != nil {
			return nil, err
		}
		for _, r := range res.Rooms {
			out[r.RoomID] = r
		}
	}
	return out, nil
}

// ---- Messages ----

const (
	pollStartType = "org.matrix.msc3381.poll.start"
	msgType       = "m.room.message"
	stickerType   = "m.sticker"
)

type messageContent struct {
	MsgType  string `json:"msgtype"`
	Body     string `json:"body"`
	FileName string `json:"filename"`
	Info     struct {
		MimeType string `json:"mimetype"`
	} `json:"info"`
	RelatesTo struct {
		RelType   string `json:"rel_type"`
		InReplyTo struct {
			EventID string `json:"event_id"`
		} `json:"m.in_reply_to"`
	} `json:"m.relates_to"`
	PollStart struct {
		Question struct {
			Body string `json:"body"`
			Text string `json:"org.matrix.msc1767.text"`
		} `json:"question"`
	} `json:"org.matrix.msc3381.poll.start"`
}

// isMessage is whether an event is something a person would call a message: a message, a sticker or a poll, but
// not an edit, a reaction, a deletion or something Courier can't read.
func isMessage(typ string, content json.RawMessage) bool {
	switch typ {
	case msgType, stickerType, pollStartType:
	default:
		return false
	}
	var c messageContent
	if json.Unmarshal(content, &c) != nil {
		return false
	}
	if c.RelatesTo.RelType == "m.replace" {
		return false
	}
	return typ != msgType || c.MsgType != "" || c.Body != ""
}

// message is one message as the tools show it.
func (l *lookups) message(id, roomID, sender, senderName string, mine bool, typ string, content json.RawMessage, ts int64) messageJSON {
	var c messageContent
	_ = json.Unmarshal(content, &c)
	m := messageJSON{
		ID: id, ChatID: roomID, AccountID: l.accountOf(roomID, ""), SenderID: sender, SenderName: senderName,
		IsSender: mine, Timestamp: rfc3339(ts), Attachments: []attachmentJSON{},
		ReplyToMessageID: c.RelatesTo.InReplyTo.EventID,
	}
	switch {
	case typ == stickerType:
		m.Attachments = append(m.Attachments, attachmentJSON{Type: "sticker", FileName: c.Body, MimeType: c.Info.MimeType})
	case typ == pollStartType:
		m.Text = cmp.Or(c.PollStart.Question.Text, c.PollStart.Question.Body, c.Body)
	case c.MsgType == "m.image" || c.MsgType == "m.video" || c.MsgType == "m.audio" || c.MsgType == "m.file":
		name := cmp.Or(c.FileName, c.Body)
		m.Attachments = append(m.Attachments, attachmentJSON{Type: strings.TrimPrefix(c.MsgType, "m."), FileName: name, MimeType: c.Info.MimeType})
		if c.FileName != "" && c.Body != c.FileName {
			m.Text = c.Body // a caption
		}
	default:
		m.Text = c.Body
	}
	return m
}

// current is message id as it reads now: its latest edit's content and true when it has been edited (the store's
// CurrentContent, the rule search and the edit history keep to), else content as it is.
func (s *Server) current(ctx context.Context, id, roomID, sender string, content json.RawMessage) (json.RawMessage, bool) {
	c, edited, err := s.store.CurrentContent(ctx, store.Event{RoomID: roomID, EventID: id, Sender: sender, Content: content})
	if err != nil {
		return content, false
	}
	return c, edited
}

// currentMessage is l.message with the message's text as it reads now (current).
func (s *Server) currentMessage(l *lookups, id, roomID, sender, senderName string, mine bool, typ string, content json.RawMessage, ts int64) messageJSON {
	c, edited := s.current(l.ctx, id, roomID, sender, content)
	m := l.message(id, roomID, sender, senderName, mine, typ, c, ts)
	m.IsEdited = edited
	return m
}

// ---- The tools ----

func (s *Server) getAccounts(ctx context.Context, _ *mcp.CallToolRequest, _ json.RawMessage) (any, error) {
	l := s.lookups(ctx)
	if err := l.load(); err != nil {
		return nil, err
	}
	out := []accountJSON{}
	for _, a := range l.accounts {
		for _, login := range a.Logins {
			out = append(out, accountJSON{
				AccountID: login.AccountID, Network: cmp.Or(a.DisplayName, a.Network),
				DisplayName: cmp.Or(login.RemoteName, a.DisplayName, a.Network), Status: login.State,
			})
		}
	}
	return out, nil
}

func (s *Server) search(ctx context.Context, _ *mcp.CallToolRequest, raw json.RawMessage) (any, error) {
	var a struct {
		Query *string `json:"query"`
	}
	if err := args(raw, &a); err != nil {
		return nil, err
	}
	if a.Query == nil || strings.TrimSpace(*a.Query) == "" {
		return nil, fail("query is required.")
	}
	var res struct {
		Chats    []wireRow `json:"chats"`
		InGroups []struct {
			UserID   string `json:"user_id"`
			Name     string `json:"name"`
			Network  string `json:"network"`
			RoomID   string `json:"room_id"`
			RoomName string `json:"room_name"`
		} `json:"in_groups"`
		Messages *wireHits `json:"messages"`
		Media    *wireHits `json:"media"`
	}
	if err := s.call(ctx, "search.query", map[string]any{
		"text": *a.Query, "sections": []string{"chats", "in_groups", "media", "messages"},
	}, &res); err != nil {
		return nil, err
	}
	l := s.lookups(ctx)
	type personJSON struct {
		ID        string `json:"id"`
		Name      string `json:"name"`
		Network   string `json:"network"`
		ChatID    string `json:"chatID"`
		ChatTitle string `json:"chatTitle"`
	}
	out := struct {
		Chats                   []chatJSON    `json:"chats"`
		GroupParticipantMatches []personJSON  `json:"groupParticipantMatches"`
		Messages                []messageJSON `json:"messages"`
	}{Chats: []chatJSON{}, GroupParticipantMatches: []personJSON{}, Messages: []messageJSON{}}
	for _, r := range res.Chats {
		out.Chats = append(out.Chats, l.chat(r))
	}
	for _, p := range res.InGroups {
		out.GroupParticipantMatches = append(out.GroupParticipantMatches, personJSON{
			ID: p.UserID, Name: p.Name, Network: l.networkName(p.Network), ChatID: p.RoomID, ChatTitle: p.RoomName,
		})
	}
	var hits []wireHit
	for _, h := range []*wireHits{res.Messages, res.Media} {
		if h != nil {
			hits = append(hits, h.Hits...)
		}
	}
	slices.SortFunc(hits, func(a, b wireHit) int { return cmp.Or(cmp.Compare(b.TS, a.TS), cmp.Compare(b.Seq, a.Seq)) })
	for _, h := range hits {
		if gone, err := s.store.Redacted(ctx, h.EventID); err != nil || gone {
			continue // deleted since it was indexed: its text is not shown
		}
		out.Messages = append(out.Messages, s.hitMessage(l, h))
	}
	return out, nil
}

// hitMessage is a search hit as a message: its whole text from the store, not the snippet.
func (s *Server) hitMessage(l *lookups, h wireHit) messageJSON {
	typ, content := msgType, json.RawMessage(`{"msgtype":"m.text"}`)
	if e, ok, err := s.store.GetEvent(l.ctx, h.EventID); err == nil && ok {
		typ, content = e.Type, e.Content
	}
	return s.currentMessage(l, h.EventID, h.RoomID, h.Sender, h.SenderName, h.Mine, typ, content, h.TS)
}

func (s *Server) searchChats(ctx context.Context, _ *mcp.CallToolRequest, raw json.RawMessage) (any, error) {
	var a struct {
		AccountIDs         []string `json:"accountIDs"`
		Cursor             *string  `json:"cursor"`
		Direction          *string  `json:"direction"`
		Inbox              *string  `json:"inbox"`
		IncludeMuted       *bool    `json:"includeMuted"`
		LastActivityAfter  *string  `json:"lastActivityAfter"`
		LastActivityBefore *string  `json:"lastActivityBefore"`
		Limit              *int     `json:"limit"`
		Query              *string  `json:"query"`
		Scope              *string  `json:"scope"`
		Type               *string  `json:"type"`
		UnreadOnly         *bool    `json:"unreadOnly"`
	}
	if err := args(raw, &a); err != nil {
		return nil, err
	}
	limit := clampLimit(a.Limit, defaultChatsLimit)
	cur, err := parseCursor(a.Cursor)
	if err != nil {
		return nil, err
	}
	after, err := directionOf(a.Direction)
	if err != nil {
		return nil, err
	}
	since, hasSince, err := parseTime("lastActivityAfter", a.LastActivityAfter)
	if err != nil {
		return nil, err
	}
	until, hasUntil, err := parseTime("lastActivityBefore", a.LastActivityBefore)
	if err != nil {
		return nil, err
	}
	places := map[string][][]string{
		"primary":      {nil},
		"low-priority": {{"low_priority"}},
		"archive":      {{"archived"}},
	}
	filters := [][]string{nil, {"low_priority"}, {"archived"}}
	if a.Inbox != nil && *a.Inbox != "" {
		f, ok := places[*a.Inbox]
		if !ok {
			return nil, fail("inbox must be primary, low-priority or archive.")
		}
		filters = f
	}
	scope := "titles"
	if a.Scope != nil && *a.Scope != "" {
		if *a.Scope != "titles" && *a.Scope != "participants" {
			return nil, fail("scope must be titles or participants.")
		}
		scope = *a.Scope
	}
	typ := "any"
	if a.Type != nil && *a.Type != "" {
		if *a.Type != "single" && *a.Type != "group" && *a.Type != "any" {
			return nil, fail("type must be single, group or any.")
		}
		typ = *a.Type
	}
	query := ""
	if a.Query != nil {
		query = strings.TrimSpace(*a.Query)
	}
	accounts := map[string]bool{}
	for _, id := range a.AccountIDs {
		accounts[id] = true
	}
	includeMuted, unreadOnly := boolOr(a.IncludeMuted, true), boolOr(a.UnreadOnly, false)

	// Every chat of the places asked for, then narrowed here: inbox.list pages by its own order (pins first), and
	// these pages go by last activity alone.
	seen := map[string]bool{}
	var rows []wireRow
	calls := 0
	for _, f := range filters {
		var cursor *string
		for {
			calls++
			if calls > maxEngineCalls*5 {
				break
			}
			params := map[string]any{"limit": 500}
			if f != nil {
				params["filters"] = f
			}
			if cursor != nil {
				params["cursor"] = *cursor
			}
			var res struct {
				Rooms      []wireRow `json:"rooms"`
				NextCursor *string   `json:"next_cursor"`
			}
			if err := s.call(ctx, "inbox.list", params, &res); err != nil {
				return nil, err
			}
			for _, r := range res.Rooms {
				if !seen[r.RoomID] {
					seen[r.RoomID] = true
					rows = append(rows, r)
				}
			}
			if res.NextCursor == nil {
				break
			}
			cursor = res.NextCursor
		}
	}
	l := s.lookups(ctx)
	folded := searchtext.Words(searchtext.Normalize(query))
	kept := rows[:0]
	for _, r := range rows {
		switch {
		case r.Hidden,
			typ == "single" && !r.IsDirect, typ == "group" && r.IsDirect,
			!includeMuted && r.Muted,
			unreadOnly && r.Unread == 0 && !r.MarkedUnread,
			hasSince && r.LastTS <= since,
			hasUntil && r.LastTS >= until,
			len(accounts) > 0 && !accounts[l.accountOf(r.RoomID, r.Network)]:
			continue
		}
		if len(folded) > 0 {
			if scope == "titles" && !containsWords(r.Name, folded) {
				continue
			}
			if scope == "participants" {
				var m struct {
					Members []json.RawMessage `json:"members"`
				}
				if err := s.call(ctx, "room.members", map[string]any{"room_id": r.RoomID, "query": query, "limit": 1}, &m); err != nil || len(m.Members) == 0 {
					continue
				}
			}
		}
		kept = append(kept, r)
	}
	newestFirst := func(a, b wireRow) int {
		return cmp.Or(cmp.Compare(b.LastTS, a.LastTS), cmp.Compare(b.RoomID, a.RoomID))
	}
	slices.SortFunc(kept, newestFirst)
	older := func(r wireRow, c *pageCursor) bool { // r comes after c, newest first
		return r.LastTS < c.T || (r.LastTS == c.T && r.RoomID < c.ID)
	}
	var page []wireRow
	hasMore := false
	switch {
	case cur != nil && after:
		var newer []wireRow
		for _, r := range kept {
			if !older(r, cur) && !(r.LastTS == cur.T && r.RoomID == cur.ID) {
				newer = append(newer, r)
			}
		}
		// The oldest limit of those newer than the cursor, shown newest first.
		if len(newer) > limit {
			hasMore = true
			newer = newer[len(newer)-limit:]
		}
		page = newer
	default:
		for _, r := range kept {
			if cur == nil || older(r, cur) {
				if len(page) == limit {
					hasMore = true
					break
				}
				page = append(page, r)
			}
		}
	}
	out := struct {
		Chats        []chatJSON `json:"chats"`
		HasMore      bool       `json:"hasMore"`
		OldestCursor *string    `json:"oldestCursor"`
		NewestCursor *string    `json:"newestCursor"`
	}{Chats: []chatJSON{}, HasMore: hasMore}
	for _, r := range page {
		out.Chats = append(out.Chats, l.chat(r))
	}
	if len(page) > 0 {
		o := pageCursor{T: page[len(page)-1].LastTS, ID: page[len(page)-1].RoomID}.String()
		n := pageCursor{T: page[0].LastTS, ID: page[0].RoomID}.String()
		out.OldestCursor, out.NewestCursor = &o, &n
	}
	return out, nil
}

// containsWords is whether every word of want begins a word of name, as search folds them (case, accents).
func containsWords(name string, want []string) bool {
	have := searchtext.Words(searchtext.Normalize(name))
	for _, w := range want {
		if !slices.ContainsFunc(have, func(h string) bool { return strings.HasPrefix(h, w) }) {
			return false
		}
	}
	return true
}

func (s *Server) getChat(ctx context.Context, _ *mcp.CallToolRequest, raw json.RawMessage) (any, error) {
	var a struct {
		ChatID              *string `json:"chatID"`
		MaxParticipantCount *int    `json:"maxParticipantCount"`
	}
	if err := args(raw, &a); err != nil {
		return nil, err
	}
	if a.ChatID == nil || *a.ChatID == "" {
		return nil, fail("chatID is required.")
	}
	maxCount := defaultParticipants
	if a.MaxParticipantCount != nil {
		maxCount = *a.MaxParticipantCount
		if maxCount != -1 && (maxCount < 0 || maxCount > maxParticipants) {
			return nil, fail("maxParticipantCount must be 0 to %d, or -1 for all.", maxParticipants)
		}
	}
	var info struct {
		Members []struct {
			UserID  string `json:"user_id"`
			Name    string `json:"name"`
			IsAdmin bool   `json:"is_admin"`
		} `json:"members"`
	}
	if err := s.call(ctx, "room.info", map[string]any{"room_id": *a.ChatID}, &info); err != nil {
		return nil, err
	}
	rows, err := s.rows(ctx, []string{*a.ChatID})
	if err != nil {
		return nil, err
	}
	row, ok := rows[*a.ChatID]
	if !ok {
		return nil, fail("No chat or message with that ID.")
	}
	l := s.lookups(ctx)
	chat := l.chat(row)
	chat.Participants = []participantJSON{}
	for _, m := range info.Members {
		if maxCount >= 0 && len(chat.Participants) >= maxCount {
			break
		}
		chat.Participants = append(chat.Participants, participantJSON{
			ID: m.UserID, Name: m.Name, IsAdmin: m.IsAdmin, IsSelf: m.UserID == string(ids.Me),
		})
	}
	return chat, nil
}

// position is an event's place in its chat's history.
type position struct{ ts, seq int64 }

// cursorPosition is where a message cursor points: its ts and seq, the seq looked up by its message when the
// cursor has none.
func (s *Server) cursorPosition(ctx context.Context, c *pageCursor) (position, error) {
	if c.S != nil {
		return position{c.T, *c.S}, nil
	}
	e, ok, err := s.store.GetEvent(ctx, c.ID)
	if err != nil || !ok {
		return position{}, fail("That cursor isn't one Courier handed out.")
	}
	return position{c.T, e.Seq}, nil
}

func messageCursor(e wireEvent) *string {
	seq := e.Seq
	c := pageCursor{T: e.TS, ID: e.EventID, S: &seq}.String()
	return &c
}

func (s *Server) listMessages(ctx context.Context, _ *mcp.CallToolRequest, raw json.RawMessage) (any, error) {
	var a struct {
		ChatID    *string `json:"chatID"`
		Cursor    *string `json:"cursor"`
		Direction *string `json:"direction"`
	}
	if err := args(raw, &a); err != nil {
		return nil, err
	}
	if a.ChatID == nil || *a.ChatID == "" {
		return nil, fail("chatID is required.")
	}
	cur, err := parseCursor(a.Cursor)
	if err != nil {
		return nil, err
	}
	after, err := directionOf(a.Direction)
	if err != nil {
		return nil, err
	}
	var from *position
	if cur != nil {
		p, err := s.cursorPosition(ctx, cur)
		if err != nil {
			return nil, err
		}
		from = &p
	}
	if after && from == nil {
		return nil, fail("direction after needs a cursor.")
	}

	var got []wireEvent // newest first when going before, oldest first when going after
	hasMore := false
	params := map[string]any{"room_id": *a.ChatID, "limit": enginePage}
	if from != nil {
		key := "before"
		if after {
			key = "after"
		}
		params[key] = wireCursor{TS: from.ts, Seq: from.seq}
	}
gather:
	for calls := 0; calls < maxEngineCalls; calls++ {
		var page wirePage
		if err := s.call(ctx, "room.events", params, &page); err != nil {
			return nil, err
		}
		evs := page.Events // newest first
		if after {
			slices.Reverse(evs)
		}
		// A deleted message stays in the history (the app shows where it was) with its old content: it is left
		// out here, so its text never reaches the client.
		var msgIDs []string
		for _, e := range evs {
			if isMessage(e.Type, e.Content) {
				msgIDs = append(msgIDs, e.EventID)
			}
		}
		deleted, err := s.store.RedactedAmong(ctx, msgIDs)
		if err != nil {
			return nil, err
		}
		for _, e := range evs {
			if !isMessage(e.Type, e.Content) || deleted[e.EventID] {
				continue
			}
			if len(got) == messagesPage {
				hasMore = true
				break gather
			}
			got = append(got, e)
		}
		next := page.Before
		key := "before"
		if after {
			next, key = page.After, "after"
		}
		if next == nil {
			break
		}
		delete(params, "before")
		delete(params, "after")
		params[key] = *next
	}
	if after {
		slices.Reverse(got)
	}
	l := s.lookups(ctx)
	out := struct {
		Messages     []messageJSON `json:"messages"`
		HasMore      bool          `json:"hasMore"`
		OldestCursor *string       `json:"oldestCursor"`
		NewestCursor *string       `json:"newestCursor"`
	}{Messages: []messageJSON{}, HasMore: hasMore}
	for _, e := range got {
		out.Messages = append(out.Messages, s.currentMessage(l, e.EventID, e.RoomID, e.Sender, e.SenderName, e.Mine, e.Type, e.Content, e.TS))
	}
	if len(got) > 0 {
		out.OldestCursor, out.NewestCursor = messageCursor(got[len(got)-1]), messageCursor(got[0])
	} else if a.Cursor != nil && *a.Cursor != "" {
		out.OldestCursor, out.NewestCursor = a.Cursor, a.Cursor // nothing there yet: the same place again
	}
	return out, nil
}

func (s *Server) searchMessages(ctx context.Context, _ *mcp.CallToolRequest, raw json.RawMessage) (any, error) {
	var a struct {
		AccountIDs         []string `json:"accountIDs"`
		ChatIDs            []string `json:"chatIDs"`
		ChatType           *string  `json:"chatType"`
		Cursor             *string  `json:"cursor"`
		DateAfter          *string  `json:"dateAfter"`
		DateBefore         *string  `json:"dateBefore"`
		Direction          *string  `json:"direction"`
		ExcludeLowPriority *bool    `json:"excludeLowPriority"`
		IncludeMuted       *bool    `json:"includeMuted"`
		Limit              *int     `json:"limit"`
		MediaTypes         []string `json:"mediaTypes"`
		Query              *string  `json:"query"`
		Sender             *string  `json:"sender"`
	}
	if err := args(raw, &a); err != nil {
		return nil, err
	}
	limit := clampLimit(a.Limit, defaultMessagesLimit)
	query := ""
	if a.Query != nil {
		query = strings.TrimSpace(*a.Query)
	}
	if query == "" {
		return nil, fail("query is required: Courier searches messages by their words. To read a chat's latest messages, use list_messages.")
	}
	cur, err := parseCursor(a.Cursor)
	if err != nil {
		return nil, err
	}
	after, err := directionOf(a.Direction)
	if err != nil {
		return nil, err
	}
	since, hasSince, err := parseTime("dateAfter", a.DateAfter)
	if err != nil {
		return nil, err
	}
	until, hasUntil, err := parseTime("dateBefore", a.DateBefore)
	if err != nil {
		return nil, err
	}
	var from *position
	if cur != nil {
		p, err := s.cursorPosition(ctx, cur)
		if err != nil {
			return nil, err
		}
		from = &p
		if after {
			since, hasSince = max(since, p.ts), true
		} else {
			until, hasUntil = p.ts+1, true
			if a.DateBefore != nil && *a.DateBefore != "" {
				u, _, _ := parseTime("dateBefore", a.DateBefore)
				until = min(until, u)
			}
		}
	}
	if after && from == nil {
		return nil, fail("direction after needs a cursor.")
	}
	if len(a.ChatIDs) > maxSearchChatIDs {
		return nil, fail("chatIDs can name at most %d chats.", maxSearchChatIDs)
	}

	filters := map[string]any{}
	if len(a.ChatIDs) > 0 {
		filters["room_ids"] = a.ChatIDs
	}
	if a.ChatType != nil && *a.ChatType != "" {
		switch *a.ChatType {
		case "group":
			filters["chat_type"] = "group"
		case "single":
			filters["chat_type"] = "dm"
		default:
			return nil, fail("chatType must be group or single.")
		}
	}
	senderID := ""
	if a.Sender != nil && *a.Sender != "" {
		switch *a.Sender {
		case "me", "others":
			filters["sender"] = *a.Sender
		default:
			senderID = *a.Sender
		}
	}
	if hasSince {
		filters["since"] = since
	}
	if hasUntil {
		filters["until"] = until
	}
	sections := []string{"messages", "media"}
	if len(a.MediaTypes) > 0 {
		kinds := map[string]bool{}
		for _, t := range a.MediaTypes {
			switch t {
			case "any":
				for _, k := range []string{"image", "video", "audio", "file", "sticker", "link"} {
					kinds[k] = true
				}
			case "image", "video", "link", "file":
				kinds[t] = true
			default:
				return nil, fail("mediaTypes may hold any, video, image, link and file.")
			}
		}
		list := make([]string, 0, len(kinds))
		for k := range kinds {
			list = append(list, k)
		}
		slices.Sort(list)
		filters["kinds"] = list
		sections = sections[:0]
		if kinds["image"] || kinds["video"] {
			sections = append(sections, "media")
		}
		if kinds["file"] || kinds["link"] || kinds["audio"] || kinds["sticker"] {
			sections = append(sections, "messages")
		}
	}
	empty := struct {
		Messages     []messageJSON       `json:"messages"`
		Chats        map[string]chatJSON `json:"chats"`
		HasMore      bool                `json:"hasMore"`
		OldestCursor *string             `json:"oldestCursor"`
		NewestCursor *string             `json:"newestCursor"`
	}{Messages: []messageJSON{}, Chats: map[string]chatJSON{}}
	if hasSince && hasUntil && since >= until {
		return empty, nil
	}

	// Each section is its own stream of hits, newest first; they are merged here.
	type stream struct {
		section string
		cursor  *string
		buf     []wireHit
		done    bool
	}
	streams := make([]*stream, 0, len(sections))
	for _, sec := range sections {
		streams = append(streams, &stream{section: sec})
	}
	calls := 0
	fill := func(st *stream) error {
		for len(st.buf) == 0 && !st.done {
			if calls++; calls > maxEngineCalls {
				st.done = true
				return nil
			}
			params := map[string]any{"text": query, "sections": []string{st.section}, "filters": filters, "limit": enginePage}
			if st.cursor != nil {
				params["cursor"] = *st.cursor
			}
			var res struct {
				Messages *wireHits `json:"messages"`
				Media    *wireHits `json:"media"`
			}
			if err := s.call(ctx, "search.query", params, &res); err != nil {
				return err
			}
			h := res.Messages
			if st.section == "media" {
				h = res.Media
			}
			if h == nil {
				st.done = true
				return nil
			}
			st.buf = h.Hits
			st.cursor = h.NextCursor
			st.done = h.NextCursor == nil
		}
		return nil
	}
	l := s.lookups(ctx)
	var rowCache map[string]wireRow
	rowOf := func(roomID string) (wireRow, bool) {
		if rowCache == nil {
			rowCache = map[string]wireRow{}
		}
		if r, ok := rowCache[roomID]; ok {
			return r, true
		}
		rows, err := s.rows(ctx, []string{roomID})
		if err != nil {
			return wireRow{}, false
		}
		r, ok := rows[roomID]
		if ok {
			rowCache[roomID] = r
		}
		return r, ok
	}
	accounts := map[string]bool{}
	for _, id := range a.AccountIDs {
		accounts[id] = true
	}
	excludeLow, includeMuted := boolOr(a.ExcludeLowPriority, true), boolOr(a.IncludeMuted, true)
	keep := func(h wireHit) bool {
		if gone, err := s.store.Redacted(ctx, h.EventID); err != nil || gone {
			return false // deleted since it was indexed: its text is not shown
		}
		if from != nil {
			if after && (h.TS < from.ts || (h.TS == from.ts && h.Seq <= from.seq)) {
				return false
			}
			if !after && (h.TS > from.ts || (h.TS == from.ts && h.Seq >= from.seq)) {
				return false
			}
		}
		if senderID != "" && h.Sender != senderID {
			return false
		}
		if excludeLow && h.Place == "low_priority" {
			return false
		}
		if len(accounts) > 0 && !accounts[l.accountOf(h.RoomID, "")] {
			return false
		}
		if !includeMuted {
			if r, ok := rowOf(h.RoomID); ok && r.Muted {
				return false
			}
		}
		return true
	}
	// want is how many to gather: one more than a page says whether there is more. Going after, every hit newer
	// than the cursor is gathered (they come newest first) and the oldest are kept.
	want := limit + 1
	if after {
		want = math.MaxInt
	}
	var got []wireHit
	for len(got) < want {
		var best *stream
		for _, st := range streams {
			if err := fill(st); err != nil {
				return nil, err
			}
			if len(st.buf) == 0 {
				continue
			}
			if best == nil || st.buf[0].TS > best.buf[0].TS || (st.buf[0].TS == best.buf[0].TS && st.buf[0].Seq > best.buf[0].Seq) {
				best = st
			}
		}
		if best == nil {
			break
		}
		h := best.buf[0]
		best.buf = best.buf[1:]
		if keep(h) {
			got = append(got, h)
		}
	}
	out := empty
	if after {
		if len(got) > limit {
			out.HasMore = true
			got = got[len(got)-limit:]
		}
	} else if len(got) > limit {
		out.HasMore = true
		got = got[:limit]
	}
	var roomIDs []string
	for _, h := range got {
		out.Messages = append(out.Messages, s.hitMessage(l, h))
		if !slices.Contains(roomIDs, h.RoomID) {
			roomIDs = append(roomIDs, h.RoomID)
		}
	}
	rows, err := s.rows(ctx, roomIDs)
	if err != nil {
		return nil, err
	}
	for id, r := range rows {
		out.Chats[id] = l.chat(r)
	}
	if len(got) > 0 {
		oldest, newest := got[len(got)-1], got[0]
		o := pageCursor{T: oldest.TS, ID: oldest.EventID, S: &oldest.Seq}.String()
		n := pageCursor{T: newest.TS, ID: newest.EventID, S: &newest.Seq}.String()
		out.OldestCursor, out.NewestCursor = &o, &n
	}
	return out, nil
}

// canSend is whether the request's token may send messages, as it was when this request arrived.
func canSend(req *mcp.CallToolRequest) bool {
	if req == nil || req.Extra == nil || req.Extra.TokenInfo == nil {
		return false
	}
	v, _ := req.Extra.TokenInfo.Extra["canSend"].(bool)
	return v
}

func (s *Server) sendMessage(ctx context.Context, req *mcp.CallToolRequest, raw json.RawMessage) (any, error) {
	if !canSend(req) {
		return nil, fail("This connection isn't allowed to send messages. Turn on \"Can send messages\" for it in Courier's Settings → Integrations.")
	}
	var a struct {
		ChatID           *string `json:"chatID"`
		ReplyToMessageID *string `json:"replyToMessageID"`
		Text             *string `json:"text"`
	}
	if err := args(raw, &a); err != nil {
		return nil, err
	}
	if a.ChatID == nil || *a.ChatID == "" {
		return nil, fail("chatID is required.")
	}
	if a.Text == nil || strings.TrimSpace(*a.Text) == "" {
		return nil, fail("text is required: there is nothing to send.")
	}
	text, ents := fromMarkdown(*a.Text)
	params := map[string]any{"room_id": *a.ChatID, "text": text}
	if len(ents) > 0 {
		params["entities"] = ents
	}
	if a.ReplyToMessageID != nil && *a.ReplyToMessageID != "" {
		params["reply_to"] = *a.ReplyToMessageID
	}
	var sent struct {
		EventID string `json:"event_id"`
	}
	if err := s.call(ctx, "message.send", params, &sent); err != nil {
		return nil, err
	}
	return map[string]string{"messageID": sent.EventID, "chatID": *a.ChatID, "deeplink": "courier://chat/" + *a.ChatID}, nil
}

func (s *Server) archiveChat(ctx context.Context, _ *mcp.CallToolRequest, raw json.RawMessage) (any, error) {
	var a struct {
		Archived *bool   `json:"archived"`
		ChatID   *string `json:"chatID"`
	}
	if err := args(raw, &a); err != nil {
		return nil, err
	}
	if a.ChatID == nil || *a.ChatID == "" {
		return nil, fail("chatID is required.")
	}
	archived := boolOr(a.Archived, true)
	if err := s.call(ctx, "room.setArchived", map[string]any{"room_ids": []string{*a.ChatID}, "archived": archived}, nil); err != nil {
		return nil, err
	}
	return map[string]any{"chatID": *a.ChatID, "archived": archived}, nil
}

func (s *Server) setChatReminder(ctx context.Context, _ *mcp.CallToolRequest, raw json.RawMessage) (any, error) {
	var a struct {
		ChatID   *string `json:"chatID"`
		Reminder *struct {
			DismissOnIncomingMessage *bool    `json:"dismissOnIncomingMessage"`
			RemindAtMs               *float64 `json:"remindAtMs"`
		} `json:"reminder"`
	}
	if err := args(raw, &a); err != nil {
		return nil, err
	}
	if a.ChatID == nil || *a.ChatID == "" {
		return nil, fail("chatID is required.")
	}
	if a.Reminder == nil || a.Reminder.RemindAtMs == nil {
		return nil, fail("reminder.remindAtMs is required.")
	}
	at := *a.Reminder.RemindAtMs
	if math.IsNaN(at) || math.IsInf(at, 0) || at > math.MaxInt64/2 {
		return nil, fail("reminder.remindAtMs must be a time in Unix milliseconds.")
	}
	due := int64(math.Ceil(at))
	if due <= time.Now().UnixMilli() {
		return nil, fail("reminder.remindAtMs is in the past: a reminder must be set for later.")
	}
	condition := "always"
	if boolOr(a.Reminder.DismissOnIncomingMessage, false) {
		condition = "if_no_incoming" // dropped when someone else sends a message in the chat first
	}
	if err := s.call(ctx, "reminder.set", map[string]any{"room_ids": []string{*a.ChatID}, "due_at": due, "condition": condition}, nil); err != nil {
		return nil, err
	}
	return map[string]any{"chatID": *a.ChatID, "remindAt": rfc3339(due)}, nil
}

func (s *Server) clearChatReminder(ctx context.Context, _ *mcp.CallToolRequest, raw json.RawMessage) (any, error) {
	var a struct {
		ChatID *string `json:"chatID"`
	}
	if err := args(raw, &a); err != nil {
		return nil, err
	}
	if a.ChatID == nil || *a.ChatID == "" {
		return nil, fail("chatID is required.")
	}
	if err := s.call(ctx, "reminder.clear", map[string]any{"room_ids": []string{*a.ChatID}}, nil); err != nil {
		return nil, err
	}
	return map[string]any{"chatID": *a.ChatID, "cleared": true}, nil
}

// FocusParams is the app.focus notification's params: what the app opens and puts in the composer, unsent.
type FocusParams struct {
	ChatID              string `json:"chatID,omitempty"`
	MessageID           string `json:"messageID,omitempty"`
	DraftText           string `json:"draftText,omitempty"`
	DraftAttachmentPath string `json:"draftAttachmentPath,omitempty"`
}

func (s *Server) focusApp(ctx context.Context, req *mcp.CallToolRequest, raw json.RawMessage) (any, error) {
	var a struct {
		ChatID              *string `json:"chatID"`
		DraftAttachmentPath *string `json:"draftAttachmentPath"`
		DraftText           *string `json:"draftText"`
		MessageID           *string `json:"messageID"`
	}
	if err := args(raw, &a); err != nil {
		return nil, err
	}
	var p FocusParams
	if a.ChatID != nil && *a.ChatID != "" {
		if _, ok, err := s.store.GetRoom(ctx, *a.ChatID); err != nil {
			return nil, err
		} else if !ok {
			return nil, fail("No chat with that ID.")
		}
		p.ChatID = *a.ChatID
	}
	if a.MessageID != nil && *a.MessageID != "" {
		e, ok, err := s.store.GetEvent(ctx, *a.MessageID)
		if err != nil {
			return nil, err
		}
		if !ok || (p.ChatID != "" && e.RoomID != p.ChatID) {
			return nil, fail("No message with that ID in that chat.")
		}
		p.ChatID, p.MessageID = e.RoomID, e.EventID
	}
	if a.DraftText != nil && *a.DraftText != "" {
		p.DraftText = *a.DraftText
	}
	attach := a.DraftAttachmentPath != nil && *a.DraftAttachmentPath != ""
	// Everything that needs no file is checked first, so a call that would fail anyway never looks at the disk:
	// the file is the last thing checked, and every way it can be wrong reads the same (fileError), so the tool
	// can't be used to learn what exists on this Mac.
	if (p.DraftText != "" || attach) && p.ChatID == "" {
		return nil, fail("draftText and draftAttachmentPath need a chatID: a draft belongs to a chat.")
	}
	if s.pub == nil || s.pub.Listeners() == 0 {
		return nil, fail("Courier's window isn't open to bring forward.")
	}
	if attach {
		if !canSend(req) {
			return nil, fail("Attaching a file needs permission to send messages. Turn on \"Can send messages\" for this connection in Courier's Settings → Integrations.")
		}
		path, ok := readableFile(*a.DraftAttachmentPath)
		if !ok {
			return nil, fail(fileError)
		}
		p.DraftAttachmentPath = path
	}
	if s.pub.Publish("app.focus", p) == 0 {
		return nil, fail("Courier's window isn't open to bring forward.")
	}
	return map[string]any{"focused": true, "chatID": p.ChatID, "messageID": p.MessageID}, nil
}

// fileError is focus_app's one answer for an attachment it won't take, whatever is wrong with it.
const fileError = "Courier can't attach that file."

// readableFile is path, cleaned, and whether it is an absolute path to a regular file this engine can read.
func readableFile(path string) (string, bool) {
	if !filepath.IsAbs(path) {
		return "", false
	}
	path = filepath.Clean(path)
	fi, err := os.Stat(path)
	if err != nil || !fi.Mode().IsRegular() {
		return "", false
	}
	f, err := os.Open(path)
	if err != nil {
		return "", false
	}
	f.Close()
	return path, true
}

func (s *Server) searchDocs(context.Context, *mcp.CallToolRequest, json.RawMessage) (any, error) {
	return textResult(SearchDocsText), nil
}

// textResult is a result that is plain text rather than JSON.
type textResult string
