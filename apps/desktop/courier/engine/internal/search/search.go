// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package search

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/VitruvianSoftware/courier/engine/internal/searchtext"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// Service answers searches over this Mac's chats, people and messages. It is the one search API: the app's
// search.query and milestone 5's local API both call Query, and nothing here knows about JSON-RPC. It never logs
// what is searched for, nor anything it finds.
//
// Answers don't change by themselves: a search is run again for newer results, so nothing moves under the keyboard.
type Service struct {
	store *store.Store
}

// New is a Service over s.
func New(s *store.Store) *Service { return &Service{store: s} }

// Section is one part of an answer.
type Section string

const (
	Chats     Section = "chats"     // chats by name (a DM also by the name of the person it is with)
	InGroups  Section = "in_groups" // people I share a group with and have no direct chat with
	Bookmarks Section = "bookmarks" // messages I bookmarked, of every kind (inventory 01 §12)
	Media     Section = "media"     // images and videos, by their caption or file name
	Messages  Section = "messages"  // every other message
)

// AllSections is what a Request with no Sections asks for, in the order an answer lists them (inventory 01 §12).
var AllSections = []Section{Chats, InGroups, Bookmarks, Media, Messages}

// The hints a Response can carry.
const (
	HintEmojiOnly       = "emoji_only"        // the text has nothing searchable (emoji or punctuation only): nothing ran
	HintNeedMoreLetters = "need_more_letters" // under 2 letters: chats and people ran, media and messages need more
)

const (
	// MaxTextRunes is the longest text a Request takes, in Unicode scalars (searchtext reads no more of it).
	MaxTextRunes = searchtext.MaxQueryRunes
	// SnippetRunes is the most a hit's snippet holds, its "…" included.
	SnippetRunes = 160
	// MaxRoomIDs is how many chats a search can be narrowed to.
	MaxRoomIDs = 100
)

// sectionLimits is each section's default and largest limit.
var sectionLimits = map[Section]struct{ def, most int }{
	Chats: {5, 100}, InGroups: {5, 100}, Bookmarks: {defaultBookmarks, 50}, Media: {12, 50}, Messages: {20, 50},
}

// defaultBookmarks is the Bookmarks section's default limit, and how many the home (no text, no filters) lists.
// Inferred (inventory 01 §12): the five newest bookmarks on the ⌘K home.
const defaultBookmarks = 5

// pagedSections are the sections a Cursor can carry on: the message ones.
var pagedSections = []Section{Bookmarks, Media, Messages}

// kinds are the message kinds a filter takes. A link is a text message holding an http(s) URL: both text and link.
var kinds = []string{"text", "image", "video", "audio", "file", "sticker", "link"}

// mediaKinds are the kinds the Media section holds; Messages holds the others.
var mediaKinds = []string{"image", "video"}

// Filters narrow a search. The zero value narrows nothing.
type Filters struct {
	RoomIDs, Networks, Kinds []string  // RoomIDs 0..100; Kinds of kinds
	Sender                   string    // "" | "me" | "others" | a user ID (milestone 5)
	ChatType                 string    // "" | "dm" | "group"
	Since, Until             time.Time // zero = open; Until is exclusive
	// Partial adds, after the messages with every word, those with some of them. It narrows nothing, so it is not
	// a filter in the sense of "no filters".
	Partial                          bool
	ExcludeLowPriority, ExcludeMuted bool // milestone 5; the app protocol doesn't carry them
}

// none reports whether f narrows nothing (Partial aside).
func (f Filters) none() bool {
	return len(f.RoomIDs) == 0 && len(f.Networks) == 0 && len(f.Kinds) == 0 && f.Sender == "" && f.ChatType == "" &&
		f.Since.IsZero() && f.Until.IsZero() && !f.ExcludeLowPriority && !f.ExcludeMuted
}

// Request is one search.
type Request struct {
	Text     string
	Sections []Section // none is AllSections
	Filters  Filters
	// Cursor is the Next of a page of the same query, for the page after it. It needs Sections to be exactly
	// Media or Messages.
	Cursor string
	// Limit is each asked section's most hits; 0 is each section's own default (chats and in groups 5, media 12,
	// messages 20). Otherwise it is 1 to the smallest most of the sections asked (chats and in groups 100, media and
	// messages 50).
	Limit int
	// OpenRoomID is the chat open now, which LastArchived leaves out.
	OpenRoomID string
}

// Response is the answer to a Request. A section that wasn't asked for, or didn't run, is nil; one that ran and
// found nothing is empty.
type Response struct {
	Chats    []store.InboxRow
	InGroups []store.PersonHit
	Media    *MessagePage
	Messages *MessagePage
	// Bookmarks are the messages I bookmarked that match, of every kind, newest first. For empty text with no
	// filters, the defaultBookmarks newest bookmarks, newest bookmark first, with no further page.
	Bookmarks    *MessagePage
	LastArchived *store.InboxRow // only for empty text with no filters, when there is such a chat
	Complete     bool            // false while older messages are still being added (store.SearchComplete)
	Hint         string          // "" | HintEmojiOnly | HintNeedMoreLetters
}

// MessagePage is one page of media or messages, newest first. Next is the Cursor of the page after it; "" when this
// is the last. A page can hold fewer hits than its limit and still have a Next.
type MessagePage struct {
	Hits []Hit
	Next string
}

// Hit is one message found, with up to SnippetRunes of its text around the first match and the ranges of the
// matched words in that snippet, in UTF-16 code units.
type Hit struct {
	store.MessageHit
	Snippet string
	Ranges  []searchtext.Range
}

// ErrBadRequest is what Query gives for a request it can't run. The error is a *BadRequestError, whose Reason says
// why in words fit to show: fixed text, never anything the request held.
var ErrBadRequest = errors.New("bad search request")

// BadRequestError is ErrBadRequest with its reason.
type BadRequestError struct{ Reason string }

func (e *BadRequestError) Error() string { return ErrBadRequest.Error() + ": " + e.Reason }
func (e *BadRequestError) Unwrap() error { return ErrBadRequest }

func bad(reason string) error { return &BadRequestError{Reason: reason} }

// ErrNoSuchChat is what Query gives when a chat Filters.RoomIDs names isn't on this Mac. It is store.ErrNotFound.
var ErrNoSuchChat = fmt.Errorf("a chat to search in isn't on this Mac: %w", store.ErrNotFound)

// MaxLimit is the largest Limit a Request for sections (none: AllSections) takes.
func MaxLimit(sections []Section) int {
	if len(sections) == 0 {
		sections = AllSections
	}
	most := 0
	for _, s := range sections {
		if l, ok := sectionLimits[s]; ok && (most == 0 || l.most < most) {
			most = l.most
		}
	}
	return most
}

// checked is a Request whose sections and limit have been checked.
type checked struct {
	Request
	sections []Section
}

// check refuses what Query can't run, each with its reason. A network is not checked: one this Mac doesn't know
// finds nothing.
func check(r Request) (checked, error) {
	if utf8.RuneCountInString(r.Text) > MaxTextRunes {
		return checked{}, bad("text is too long")
	}
	c := checked{Request: r}
	if len(r.Sections) == 0 {
		c.sections = AllSections
	} else {
		for _, s := range AllSections { // in AllSections' order, each once
			if slices.Contains(r.Sections, s) {
				c.sections = append(c.sections, s)
			}
		}
		for _, s := range r.Sections {
			if _, ok := sectionLimits[s]; !ok {
				return checked{}, bad("sections is not one of chats, in_groups, bookmarks, media, messages")
			}
		}
	}
	if r.Cursor != "" && (len(c.sections) != 1 || !slices.Contains(pagedSections, c.sections[0])) {
		return checked{}, bad("cursor needs exactly one of bookmarks, media or messages")
	}
	if most := MaxLimit(c.sections); r.Limit < 0 || r.Limit > most {
		return checked{}, bad(fmt.Sprintf("limit must be 1 to %d", most))
	}
	f := r.Filters
	if len(f.RoomIDs) > MaxRoomIDs {
		return checked{}, bad(fmt.Sprintf("room_ids must name 1 to %d chats", MaxRoomIDs))
	}
	for _, k := range f.Kinds {
		if !slices.Contains(kinds, k) {
			return checked{}, bad("unknown kind")
		}
	}
	switch {
	case f.Sender == "", f.Sender == "me", f.Sender == "others", strings.HasPrefix(f.Sender, "@"):
	default:
		return checked{}, bad("unknown sender")
	}
	if f.ChatType != "" && f.ChatType != "dm" && f.ChatType != "group" {
		return checked{}, bad("unknown chat_type")
	}
	if !f.Since.IsZero() && !f.Until.IsZero() && !f.Since.Before(f.Until) {
		return checked{}, bad("since must be before until")
	}
	return c, nil
}

// limit is section s's limit.
func (c checked) limit(s Section) int {
	if c.Limit != 0 {
		return c.Limit
	}
	return sectionLimits[s].def
}

// messageQuery is the store query of Bookmarks, Media or Messages: Bookmarks is the bookmarked messages of Kinds
// (every kind when Kinds is empty), Media is Kinds ∩ {image, video} (both when Kinds is empty), Messages every other
// kind asked for (all of them but images and videos when Kinds is empty). ok is false when Kinds leaves the section
// nothing: a kinds filter of only images has no Messages.
func (c checked) messageQuery(s Section, terms []searchtext.Term) (q store.MessageQuery, ok bool) {
	f := c.Filters
	q = store.MessageQuery{
		Terms: terms, Partial: f.Partial, RoomIDs: f.RoomIDs, Networks: f.Networks, Sender: f.Sender,
		ChatType: f.ChatType, Since: f.Since, Until: f.Until, ExcludeLowPriority: f.ExcludeLowPriority,
		ExcludeMuted: f.ExcludeMuted, After: c.Cursor, Limit: c.limit(s),
	}
	isMedia := func(k string) bool { return slices.Contains(mediaKinds, k) }
	if s == Bookmarks {
		q.BookmarkedOnly, q.Kinds = true, slices.Clone(f.Kinds)
		return q, true
	}
	if s == Media {
		q.Kinds = slices.Clone(mediaKinds)
		if len(f.Kinds) > 0 {
			q.Kinds = slices.DeleteFunc(slices.Clone(f.Kinds), func(k string) bool { return !isMedia(k) })
		}
		return q, len(q.Kinds) > 0
	}
	q.NotKinds = slices.Clone(mediaKinds)
	if len(f.Kinds) > 0 {
		q.Kinds = slices.DeleteFunc(slices.Clone(f.Kinds), isMedia)
		return q, len(q.Kinds) > 0
	}
	return q, true
}

// Query runs r. It runs every section asked for, unless:
//   - the text is empty (or only spaces) and there are no filters: then the answer is only LastArchived, the chat
//     archived most recently that isn't hidden or the open one, and, when Bookmarks is asked for, the five newest
//     bookmarks;
//   - the text has nothing searchable (emoji or punctuation only): nothing runs, and Hint is HintEmojiOnly;
//   - the text has under 2 letters (one character of a script written without spaces counts as 2): chats and in
//     groups run, bookmarks, media and messages don't, and Hint is HintNeedMoreLetters.
//
// Filters.RoomIDs leaves out Chats and InGroups. Sender, Kinds, Since, Until and Partial narrow Bookmarks, Media
// and Messages only; Networks and ChatType narrow every section. Messages need 2 letters (searchtext.Parse); chats and people
// are matched from the first letter (searchtext.ParseName).
//
// A request it can't run is a *BadRequestError; a chat in RoomIDs that isn't on this Mac is ErrNoSuchChat; a
// cursor of another query is store.ErrBadCursor.
func (s *Service) Query(ctx context.Context, r Request) (Response, error) {
	c, err := check(r)
	if err != nil {
		return Response{}, err
	}
	for _, id := range c.Filters.RoomIDs {
		_, ok, err := s.store.GetRoom(ctx, id)
		if err != nil {
			return Response{}, err
		}
		if !ok {
			return Response{}, ErrNoSuchChat
		}
	}
	var res Response
	if res.Complete, err = s.store.SearchComplete(ctx); err != nil {
		return Response{}, err
	}

	if strings.TrimSpace(c.Text) == "" && c.Filters.none() {
		if c.Cursor != "" {
			return Response{}, store.ErrBadCursor // no query of this kind hands one out
		}
		row, ok, err := s.store.LastArchived(ctx, c.OpenRoomID)
		if err != nil {
			return Response{}, err
		}
		if ok {
			res.LastArchived = &row
		}
		if slices.Contains(c.sections, Bookmarks) {
			if res.Bookmarks, err = s.recentBookmarks(ctx, c.limit(Bookmarks)); err != nil {
				return Response{}, err
			}
		}
		return res, nil
	}

	msgTerms, nameTerms := searchtext.Parse(c.Text), searchtext.ParseName(c.Text)
	if strings.TrimSpace(c.Text) != "" && len(msgTerms) == 0 {
		res.Hint = HintEmojiOnly
		return res, nil
	}
	// No words at all (filters only) is the store's to judge: a filter that picks messages lists them, newest first,
	// and anything else is ErrNoQuery. A section that had nothing to look for didn't run, so it stays null (chats
	// and in groups always, with no words), never an empty list that would read as "nothing matches" (Ruling 34).
	messagesRun := len(msgTerms) == 0 || searchtext.Letters(msgTerms) >= 2
	if !messagesRun {
		res.Hint = HintNeedMoreLetters
	}
	names := func(sec Section) store.NameQuery {
		return store.NameQuery{Terms: nameTerms, Networks: c.Filters.Networks, ChatType: c.Filters.ChatType, Limit: c.limit(sec)}
	}
	for _, sec := range c.sections {
		switch sec {
		case Chats:
			if len(c.Filters.RoomIDs) > 0 {
				continue
			}
			rows, err := s.store.SearchChats(ctx, names(sec))
			if errors.Is(err, store.ErrNoQuery) {
				continue // no words: chats didn't run, and stay null
			}
			if err != nil {
				return Response{}, err
			}
			res.Chats = nonNil(rows)
		case InGroups:
			if len(c.Filters.RoomIDs) > 0 {
				continue
			}
			people, err := s.store.SearchPeopleInGroups(ctx, names(sec))
			if errors.Is(err, store.ErrNoQuery) {
				continue
			}
			if err != nil {
				return Response{}, err
			}
			res.InGroups = nonNil(people)
		case Bookmarks, Media, Messages:
			if !messagesRun {
				continue
			}
			q, ok := c.messageQuery(sec, msgTerms)
			if !ok {
				continue
			}
			page, err := s.messages(ctx, q, msgTerms)
			if err != nil {
				return Response{}, err
			}
			switch sec {
			case Bookmarks:
				res.Bookmarks = page
			case Media:
				res.Media = page
			default:
				res.Messages = page
			}
		}
	}
	return res, nil
}

// messages is one page of q, each hit with its snippet; nil when q has nothing to list (store.ErrNoQuery).
func (s *Service) messages(ctx context.Context, q store.MessageQuery, terms []searchtext.Term) (*MessagePage, error) {
	hits, next, err := s.store.SearchMessages(ctx, q)
	if errors.Is(err, store.ErrNoQuery) {
		return nil, nil // nothing to list: the section didn't run
	}
	if err != nil {
		return nil, err
	}
	page := &MessagePage{Hits: make([]Hit, 0, len(hits)), Next: next}
	for _, h := range hits {
		snippet, ranges := searchtext.Snippet(h.Text, terms, SnippetRunes)
		page.Hits = append(page.Hits, Hit{MessageHit: h, Snippet: snippet, Ranges: ranges})
	}
	return page, nil
}

// recentBookmarks is the home's Bookmarks: the limit newest bookmarks, newest bookmark first, each with a snippet of
// its start, and no further page.
func (s *Service) recentBookmarks(ctx context.Context, limit int) (*MessagePage, error) {
	hits, err := s.store.RecentBookmarks(ctx, limit)
	if err != nil {
		return nil, err
	}
	page := &MessagePage{Hits: make([]Hit, 0, len(hits))}
	for _, h := range hits {
		snippet, ranges := searchtext.Snippet(h.Text, nil, SnippetRunes)
		page.Hits = append(page.Hits, Hit{MessageHit: h, Snippet: snippet, Ranges: ranges})
	}
	return page, nil
}

func nonNil[T any](s []T) []T {
	if s == nil {
		return []T{}
	}
	return s
}
