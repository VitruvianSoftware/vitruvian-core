// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

// Protocol 3's search.query: the app's side of search.Service. The handler has the shape of the others (strict
// params, the required ones by name, the service's reasons as -32602), and puts the answer on the wire under
// 1 MiB whatever the store estimated. Nothing here logs what was searched for or found.

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"time"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/search"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

type searchFilters struct {
	RoomIDs  *[]string `json:"room_ids"`
	Networks *[]string `json:"networks"`
	Sender   *string   `json:"sender"`
	ChatType *string   `json:"chat_type"`
	Kinds    *[]string `json:"kinds"`
	Since    *int64    `json:"since"`
	Until    *int64    `json:"until"`
	Partial  *bool     `json:"partial"`
}

type searchParams struct {
	Text       *string        `json:"text"`
	Sections   *[]string      `json:"sections"`
	Filters    *searchFilters `json:"filters"`
	Cursor     *string        `json:"cursor"`
	Limit      *int           `json:"limit"`
	OpenRoomID *string        `json:"open_room_id"`
}

type personHit struct {
	UserID     string `json:"user_id"`
	Name       string `json:"name"`
	Network    string `json:"network"`
	AvatarPath string `json:"avatar_path"`
	RoomID     string `json:"room_id"`
	RoomName   string `json:"room_name"`
	Groups     int    `json:"groups"`
}

type textRange struct {
	Start  int `json:"start"`
	Length int `json:"length"`
}

type messageHit struct {
	EventID    string      `json:"event_id"`
	RoomID     string      `json:"room_id"`
	RoomName   string      `json:"room_name"`
	Network    string      `json:"network"`
	IsDirect   bool        `json:"is_direct"`
	Place      string      `json:"place"`
	Sender     string      `json:"sender"`
	SenderName string      `json:"sender_name"`
	Mine       bool        `json:"mine"`
	TS         int64       `json:"ts"`
	Seq        int64       `json:"seq"`
	Kind       string      `json:"kind"`
	Snippet    string      `json:"snippet"`
	Ranges     []textRange `json:"ranges"`
	MediaPath  string      `json:"media_path"`
	Partial    bool        `json:"partial"`
}

type messageHits struct {
	Hits       []messageHit `json:"hits"`
	NextCursor *string      `json:"next_cursor"`
}

// searchResult is SearchResult. A nil list or page is null: not asked for, or not run.
type searchResult struct {
	Chats        []inboxRow   `json:"chats"`
	InGroups     []personHit  `json:"in_groups"`
	Bookmarks    *messageHits `json:"bookmarks"`
	Media        *messageHits `json:"media"`
	Messages     *messageHits `json:"messages"`
	LastArchived *inboxRow    `json:"last_archived"`
	Complete     bool         `json:"complete"`
	Hint         string       `json:"hint"`
}

// The protocol's values for a filter's sender and chat type. The service takes more (a user ID as sender, for
// milestone 5's API); the app protocol doesn't.
var (
	wireSenders   = []string{"me", "others"}
	wireChatTypes = []string{"dm", "group"}
)

// searchRequest checks p and turns it into the service's request. What only the wire knows is checked here (a
// network the engine doesn't know, room_ids of none, a sender that isn't me or others); the rest the service
// checks and gives its reason for.
func (d *Deps) searchRequest(p searchParams) (search.Request, error) {
	if p.Text == nil {
		return search.Request{}, invalidParams("text is required")
	}
	r := search.Request{Text: *p.Text}
	if p.Sections != nil {
		for _, s := range *p.Sections {
			r.Sections = append(r.Sections, search.Section(s))
		}
	}
	if p.Cursor != nil {
		if *p.Cursor == "" {
			return search.Request{}, invalidParams("cursor is not one this query handed out")
		}
		r.Cursor = *p.Cursor
	}
	if p.Limit != nil {
		r.Limit = *p.Limit
		if r.Limit == 0 {
			r.Limit = -1 // on the wire 0 is out of range, not the default: the service says so with its range
		}
	}
	if p.OpenRoomID != nil {
		r.OpenRoomID = *p.OpenRoomID
	}
	if f := p.Filters; f != nil {
		if f.RoomIDs != nil {
			roomIDs, err := roomIDList(f.RoomIDs, search.MaxRoomIDs)
			if err != nil {
				return search.Request{}, err
			}
			r.Filters.RoomIDs = roomIDs
		}
		if f.Networks != nil {
			for _, n := range *f.Networks {
				if !slices.ContainsFunc(d.Networks, func(i NetworkInfo) bool { return i.Name == n }) {
					return search.Request{}, invalidParams("unknown network")
				}
			}
			r.Filters.Networks = *f.Networks
		}
		if f.Sender != nil {
			if !slices.Contains(wireSenders, *f.Sender) {
				return search.Request{}, invalidParams("unknown sender")
			}
			r.Filters.Sender = *f.Sender
		}
		if f.ChatType != nil {
			if !slices.Contains(wireChatTypes, *f.ChatType) {
				return search.Request{}, invalidParams("unknown chat_type")
			}
			r.Filters.ChatType = *f.ChatType
		}
		if f.Kinds != nil {
			r.Filters.Kinds = *f.Kinds
		}
		if f.Since != nil {
			r.Filters.Since = time.UnixMilli(*f.Since)
		}
		if f.Until != nil {
			r.Filters.Until = time.UnixMilli(*f.Until)
		}
		if f.Partial != nil {
			r.Filters.Partial = *f.Partial
		}
	}
	return r, nil
}

// searchError is the wire's error for one of the service's: its reason as -32602; anything else as classify maps
// it (a cursor of another query, a chat that isn't on this Mac). An error with no code of its own is logged as an
// internal error, so its text is left out: a database error can quote the query (an FTS5 syntax error does), and
// what was searched for is never logged.
func searchError(err error) error {
	var br *search.BadRequestError
	if errors.As(err, &br) {
		return invalidParams(br.Reason)
	}
	if _, unknown := classify(err); unknown {
		return redacted{err}
	}
	return err
}

// redacted is an error whose text is left out of the log. It still unwraps to the error it hides.
type redacted struct{ err error }

func (redacted) Error() string   { return "search failed in the store (its text is left out of the log)" }
func (r redacted) Unwrap() error { return r.err }

func searchQuery(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p searchParams
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	r, err := d.searchRequest(p)
	if err != nil {
		return nil, err
	}
	if d.Search == nil {
		return nil, errMissing
	}
	res, err := d.Search.Query(ctx, r)
	if errors.Is(err, store.ErrNoQuery) {
		return searchResult{Complete: res.Complete}, nil // nothing to look for: an empty answer, not an error
	}
	if err != nil {
		return nil, searchError(err)
	}
	return d.searchAnswer(ctx, r, res)
}

// searchAnswer puts res on the wire. The whole answer stays under maxPageBytes - pageSlack, counted as the wire
// encodes it (Ruling 17: whatever the store estimated). Chats and people come first and are cut short if need be
// (they have no further page); then each page of bookmarks, media and messages is cut to what fits, asked for again
// with only that many hits so its next_cursor is the one after the last hit sent.
func (d *Deps) searchAnswer(ctx context.Context, r search.Request, res search.Response) (searchResult, error) {
	out := searchResult{Complete: res.Complete, Hint: res.Hint}
	budget := maxPageBytes - pageSlack
	if res.Chats != nil {
		rows, err := d.toRows(ctx, res.Chats)
		if err != nil {
			return searchResult{}, err
		}
		out.Chats = rows[:fitting(rows, budget)]
		budget -= encodedLen(out.Chats)
	}
	if res.InGroups != nil {
		people := make([]personHit, 0, len(res.InGroups))
		for _, h := range res.InGroups {
			people = append(people, personHit{
				UserID: h.UserID, Name: h.Name, Network: h.Network, AvatarPath: d.path(h.AvatarURI),
				RoomID: h.RoomID, RoomName: h.RoomName, Groups: h.Groups,
			})
		}
		out.InGroups = people[:fitting(people, budget)]
		budget -= encodedLen(out.InGroups)
	}
	if res.LastArchived != nil {
		rows, err := d.toRows(ctx, []store.InboxRow{*res.LastArchived})
		if err != nil {
			return searchResult{}, err
		}
		out.LastArchived = &rows[0]
		budget -= encodedLen(out.LastArchived)
	}
	senders := map[string]sender{}
	for _, sec := range []search.Section{search.Bookmarks, search.Media, search.Messages} {
		page := pageOf(res, sec)
		if page == nil {
			continue
		}
		hits, err := d.hitPage(ctx, r, sec, page, budget, senders)
		if err != nil {
			return searchResult{}, err
		}
		switch sec {
		case search.Bookmarks:
			out.Bookmarks = hits
		case search.Media:
			out.Media = hits
		default:
			out.Messages = hits
		}
		budget -= encodedLen(hits)
	}
	return out, nil
}

// pageOf is res's page of section sec: Bookmarks, Media or Messages.
func pageOf(res search.Response, sec search.Section) *search.MessagePage {
	switch sec {
	case search.Bookmarks:
		return res.Bookmarks
	case search.Media:
		return res.Media
	}
	return res.Messages
}

// hitPage is page on the wire, at most budget bytes. A page that would pass it is asked for again, alone, with
// only the hits that fit, so the store hands out the cursor after the last of them: the next page starts at the
// first hit left out. Each pass asks for fewer hits, and a page always has at least one.
func (d *Deps) hitPage(ctx context.Context, r search.Request, sec search.Section, page *search.MessagePage, budget int,
	senders map[string]sender,
) (*messageHits, error) {
	for {
		hits := make([]messageHit, 0, len(page.Hits))
		for _, h := range page.Hits {
			hit, err := d.toHit(ctx, h, senders)
			if err != nil {
				return nil, err
			}
			hits = append(hits, hit)
		}
		n := fitting(hits, budget)
		if n == len(hits) {
			out := &messageHits{Hits: hits}
			if page.Next != "" {
				next := page.Next
				out.NextCursor = &next
			}
			return out, nil
		}
		again := r
		again.Sections, again.Limit = []search.Section{sec}, n
		res, err := d.Search.Query(ctx, again)
		if err != nil {
			return nil, searchError(err)
		}
		if page = pageOf(res, sec); page == nil {
			return nil, fmt.Errorf("search: %s ran once and not again", sec)
		}
	}
}

func (d *Deps) toHit(ctx context.Context, h search.Hit, senders map[string]sender) (messageHit, error) {
	who, err := d.sender(ctx, h.Event.Sender, senders)
	if err != nil {
		return messageHit{}, err
	}
	ranges := make([]textRange, 0, len(h.Ranges))
	for _, rg := range h.Ranges {
		ranges = append(ranges, textRange{Start: rg.Start, Length: rg.Length})
	}
	return messageHit{
		EventID: h.Event.EventID, RoomID: h.Event.RoomID, RoomName: h.RoomName, Network: h.Network,
		IsDirect: h.IsDirect, Place: h.Place, Sender: h.Event.Sender, SenderName: who.name,
		Mine: h.Event.Sender == string(ids.Me), TS: ms(h.Event.TS), Seq: h.Event.Seq, Kind: h.Kind,
		Snippet: h.Snippet, Ranges: ranges, MediaPath: d.path(h.MediaURI), Partial: h.Partial,
	}, nil
}

// encodedLen is how long v is as JSON (at least: the wire doesn't escape <, > and &, which this counts as six).
func encodedLen(v any) int {
	b, err := json.Marshal(v)
	if err != nil {
		return 0 // can't happen: plain data
	}
	return len(b)
}
