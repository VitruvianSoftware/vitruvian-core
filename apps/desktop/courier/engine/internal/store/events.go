// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"cmp"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"slices"
	"strings"

	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
)

const (
	// signalViewOnceTimerMS is the 5-minute after_read disappearing timer mautrix-signal stamps on view-once media
	// when the message's own ExpireTimer is 0 (mautrix-signal v0.2609.0 pkg/msgconv/from-signal.go:81,162-164).
	signalViewOnceTimerMS int64 = 5 * 60 * 1000
	// telegramViewOnceTimerMS is the 15-second after_read disappearing timer mautrix-telegram stamps on view-once
	// media when ttl == 2147483647 (mautrix-telegram v0.2609.0 pkg/connector/tomatrix.go:565-567).
	telegramViewOnceTimerMS int64 = 15 * 1000
)

// IsViewOnceTimer reports whether a media message's after_read disappearing timer (msgTimerMS) represents a
// view-once attachment in a chat on network whose current after_read room timer is roomAfterReadTimerMS (0 when off
// or not after_read). A message whose timer equals the room's timer is a normal disappearing message, never view-once.
func IsViewOnceTimer(network string, msgTimerMS int64, roomAfterReadTimerMS int64) bool {
	if msgTimerMS <= 0 {
		return false
	}
	if roomAfterReadTimerMS > 0 && msgTimerMS == roomAfterReadTimerMS {
		return false
	}
	switch network {
	case "signal":
		return msgTimerMS == signalViewOnceTimerMS
	case "telegram":
		return msgTimerMS == telegramViewOnceTimerMS
	default:
		return msgTimerMS == signalViewOnceTimerMS || msgTimerMS == telegramViewOnceTimerMS
	}
}

// RoomViewOnceContext returns roomID's network name and its current after_read disappearing timer duration in
// milliseconds (0 when no after_read timer is active on the room).
func (s *Store) RoomViewOnceContext(ctx context.Context, roomID string) (network string, roomAfterReadTimerMS int64) {
	if s == nil || roomID == "" {
		return "", 0
	}
	_ = s.db.QueryRow(ctx, `SELECT network FROM rooms WHERE room_id = $1`, roomID).Scan(&network)
	var raw string
	if err := s.db.QueryRow(ctx, `SELECT content FROM state WHERE room_id = $1 AND type = 'com.beeper.disappearing_timer' AND state_key = ''`, roomID).Scan(&raw); err == nil && raw != "" {
		var dt struct {
			Type  string `json:"type"`
			Timer int64  `json:"timer"`
		}
		if json.Unmarshal([]byte(raw), &dt) == nil && dt.Type == "after_read" && dt.Timer > 0 {
			roomAfterReadTimerMS = dt.Timer
		}
	}
	return network, roomAfterReadTimerMS
}

type rawRow struct {
	eventID string
	sender  string
	evtType string
	content string
}

func resolveMediaPath(ms *media.Store, uri string) string {
	if ms == nil || uri == "" {
		return ""
	}
	hash, ok := ids.ParseContentURI(id.ContentURIString(uri))
	if !ok {
		return ""
	}
	p, err := ms.Path(hash)
	if err != nil {
		return ""
	}
	return p
}

// ExtractEventMedia populates media inspection, location, link preview, and view-once fields on e from e.Content.
// When ViewOnce && played is true, MediaPath and ThumbnailPath are cleared so view-once media cannot be re-opened.
func ExtractEventMedia(e *Event, ms *media.Store, played bool) {
	ExtractEventMediaWithRoom(e, ms, played, "", 0)
}

// ExtractEventMediaWithRoom populates media fields on e using the room's network and current after_read disappearing
// timer (roomAfterReadTimerMS) so normal disappearing messages in an after_read room are not mistaken for view-once.
func ExtractEventMediaWithRoom(e *Event, ms *media.Store, played bool, network string, roomAfterReadTimerMS int64) {
	if e == nil {
		return
	}
	e.Played = played
	if len(e.Content) == 0 {
		return
	}

	var c struct {
		MsgType string          `json:"msgtype"`
		URL     string          `json:"url"`
		GeoURI  string          `json:"geo_uri"`
		Voice   json.RawMessage `json:"org.matrix.msc3245.voice"`
		Audio   *struct {
			Duration int   `json:"duration"`
			Waveform []int `json:"waveform"`
		} `json:"org.matrix.msc1767.audio"`
		Info *struct {
			MimeType     string `json:"mimetype"`
			ThumbnailURL string `json:"thumbnail_url"`
			Blurhash     string `json:"blurhash"`
			AnoaBlurhash string `json:"xyz.amorgan.blurhash"`
			Duration     int    `json:"duration"`
			MauGIF       bool   `json:"fi.mau.gif"`
		} `json:"info"`
		MauGIF            bool `json:"fi.mau.gif"`
		DisappearingTimer *struct {
			Type  string `json:"type"`
			Timer int64  `json:"timer"`
		} `json:"com.beeper.disappearing_timer"`
		LinkPreviews []struct {
			MatchedURL  string `json:"matched_url"`
			URL         string `json:"og:url"`
			Title       string `json:"og:title"`
			SiteName    string `json:"og:site_name"`
			Description string `json:"og:description"`
			ImageURL    string `json:"og:image"`
			ImageWidth  int    `json:"og:image:width"`
			ImageHeight int    `json:"og:image:height"`
			BlurHash    string `json:"matrix:image:blurhash"`
		} `json:"com.beeper.linkpreviews"`
	}
	if err := json.Unmarshal(e.Content, &c); err != nil {
		return
	}

	switch e.Type {
	case "m.sticker":
		e.Kind = "sticker"
	case "m.room.message":
		switch c.MsgType {
		case "m.image":
			e.Kind = "image"
		case "m.video":
			e.Kind = "video"
		case "m.audio":
			if len(c.Voice) > 0 && string(c.Voice) != "null" {
				e.Kind = "voice"
			} else {
				e.Kind = "audio"
			}
		case "m.file":
			e.Kind = "file"
		case "m.location":
			e.Kind = "location"
		default:
			e.Kind = "text"
		}
	}

	e.MediaPath = resolveMediaPath(ms, c.URL)
	if c.Info != nil {
		e.ThumbnailPath = resolveMediaPath(ms, c.Info.ThumbnailURL)
		e.BlurHash = cmp.Or(c.Info.AnoaBlurhash, c.Info.Blurhash)
		e.DurationMS = c.Info.Duration
		mime := strings.ToLower(strings.TrimSpace(c.Info.MimeType))
		e.IsGIF = c.Info.MauGIF || c.MauGIF || mime == "image/gif"
		e.IsAnimated = e.IsGIF || mime == "image/apng" || (e.Kind == "sticker" && strings.HasPrefix(mime, "video/"))
	} else if c.MauGIF {
		e.IsGIF = true
		e.IsAnimated = true
	}
	if c.Audio != nil {
		if c.Audio.Duration > 0 {
			e.DurationMS = c.Audio.Duration
		}
		if len(c.Audio.Waveform) > 0 {
			e.Waveform = slices.Clone(c.Audio.Waveform)
		}
	}
	if c.MsgType == "m.location" {
		e.GeoURI = c.GeoURI
	}
	if len(c.LinkPreviews) > 0 {
		previews := make([]LinkPreview, 0, len(c.LinkPreviews))
		for _, lp := range c.LinkPreviews {
			previews = append(previews, LinkPreview{
				MatchedURL:  lp.MatchedURL,
				URL:         cmp.Or(lp.URL, lp.MatchedURL),
				Title:       lp.Title,
				SiteName:    lp.SiteName,
				Description: lp.Description,
				ImagePath:   resolveMediaPath(ms, lp.ImageURL),
				ImageWidth:  lp.ImageWidth,
				ImageHeight: lp.ImageHeight,
				BlurHash:    lp.BlurHash,
			})
		}
		e.LinkPreviews = previews
	}

	isMediaKind := e.Kind == "image" || e.Kind == "video" || e.Kind == "voice" || e.Kind == "audio" || e.Kind == "file"
	e.ViewOnce = isMediaKind &&
		c.DisappearingTimer != nil &&
		c.DisappearingTimer.Type == "after_read" &&
		IsViewOnceTimer(network, c.DisappearingTimer.Timer, roomAfterReadTimerMS)

	if e.ViewOnce && e.Played {
		e.MediaPath = ""
		e.ThumbnailPath = ""
	}
}

func extractEvents(ctx context.Context, s *Store, ms *media.Store, roomID string, rows []rawRow) []Event {
	if len(rows) == 0 {
		return nil
	}
	var playedSet map[string]bool
	var network string
	var roomTimerMS int64
	if s != nil && roomID != "" {
		ids := make([]string, 0, len(rows))
		for _, r := range rows {
			if r.eventID != "" {
				ids = append(ids, r.eventID)
			}
		}
		playedSet, _ = s.MediaPlayedSet(ctx, roomID, ids)
		network, roomTimerMS = s.RoomViewOnceContext(ctx, roomID)
	}
	out := make([]Event, len(rows))
	for i, r := range rows {
		e := Event{
			RoomID:  roomID,
			EventID: r.eventID,
			Sender:  r.sender,
			Type:    r.evtType,
			Content: json.RawMessage(r.content),
		}
		ExtractEventMediaWithRoom(&e, ms, playedSet[r.eventID], network, roomTimerMS)
		out[i] = e
	}
	return out
}

func extractEvent(ctx context.Context, s *Store, ms *media.Store, roomID string, r rawRow) Event {
	return extractEvents(ctx, s, ms, roomID, []rawRow{r})[0]
}

// CleanupPlayedViewOnceMedia deletes the local media blob(s) of (roomID, eventID) when it is a view-once attachment
// and no other non-redacted, non-deleted event references the same content hash.
func (s *Store) CleanupPlayedViewOnceMedia(ctx context.Context, roomID, eventID string, ms *media.Store) {
	if s == nil || ms == nil || eventID == "" {
		return
	}
	var eType, rawContent string
	err := s.db.QueryRow(ctx, `SELECT type, content FROM events WHERE room_id = $1 AND event_id = $2`, roomID, eventID).Scan(&eType, &rawContent)
	if err != nil {
		return
	}
	network, roomTimerMS := s.RoomViewOnceContext(ctx, roomID)
	ev := Event{RoomID: roomID, EventID: eventID, Type: eType, Content: json.RawMessage(rawContent)}
	ExtractEventMediaWithRoom(&ev, nil, false, network, roomTimerMS)
	if !ev.ViewOnce {
		return
	}
	var c struct {
		URL  string `json:"url"`
		Info *struct {
			ThumbnailURL string `json:"thumbnail_url"`
		} `json:"info"`
	}
	if json.Unmarshal([]byte(rawContent), &c) != nil {
		return
	}
	uris := []string{c.URL}
	if c.Info != nil && c.Info.ThumbnailURL != "" && c.Info.ThumbnailURL != c.URL {
		uris = append(uris, c.Info.ThumbnailURL)
	}
	for _, uri := range uris {
		if uri == "" {
			continue
		}
		hash, ok := ids.ParseContentURI(id.ContentURIString(uri))
		if !ok {
			continue
		}
		var stillReferenced int
		err := s.db.QueryRow(ctx, `
			SELECT 1 FROM events
			WHERE event_id <> $1 AND redacted = 0 AND deleted_for_me = 0
			  AND (
			    (CASE WHEN json_valid(content) THEN json_extract(content, '$.url') END) = $2
			    OR (CASE WHEN json_valid(content) THEN json_extract(content, '$.info.thumbnail_url') END) = $2
			  )
			LIMIT 1`, eventID, uri).Scan(&stillReferenced)
		if errors.Is(err, sql.ErrNoRows) {
			_ = ms.Delete(hash)
		}
	}
}

// A chat's history read from a point inside it, so that a search result can open the chat at an old message.
// EventsAround and EventsAfter read the same events (the main timeline: no reply that stays in its thread), in the
// same (ts, seq) order, as EventsBefore: a page around a message, the older pages EventsBefore gives from its before
// cursor and the newer pages EventsAfter gives from its after cursor cover the chat's history exactly once.

// eventAtSQL reads one event of one room: $1 the event ID, $2 the room. An event of another room is no row.
const eventAtSQL = `SELECT ` + eventCols + ` FROM events WHERE event_id = $1 AND room_id = $2`

// eventsAfterSQL pages oldest-first forward through events_room_ts (walking the index backwards, so no sort):
// $1 room, $2 and $3 the cursor's ts (ms) and seq, $4 the number of rows wanted.
var eventsAfterSQL = `SELECT ` + eventCols + ` FROM events
WHERE room_id = $1 AND (ts, seq) > ($2, $3) AND ` + mainTimelineSQL + `
ORDER BY ts ASC, seq ASC LIMIT $4`

// EventsAround is the page of roomID's history centred on eventID, newest first: up to limit events, about half
// older than it, the event itself, and the rest newer. before is the cursor for the next older page (nil at the
// oldest); after is the newest event of the page (nil when the page has the room's newest event). ErrNotFound when
// eventID isn't in roomID.
//
// Precisely: (limit-1)/2 older events and the rest newer, so an even limit leans newer (10 is 4 older, the event,
// 5 newer). When one side has fewer events than its share, the other side takes the spare slots, so the page is
// full near either end of the history (around the newest message, limit 10 is its 9 older and itself); only a room
// with fewer than limit events gives a shorter page.
func (s *Store) EventsAround(ctx context.Context, roomID, eventID string, limit int) (evs []Event, before, after *Cursor, err error) {
	if limit <= 0 {
		limit = 50
	}
	centre, err := scanEvent(s.db.QueryRow(ctx, eventAtSQL, eventID, roomID))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil, nil, ErrNotFound
	} else if err != nil {
		return nil, nil, nil, err
	}
	at := centre.TS.UnixMilli()

	// Each side may fill the whole page but the event itself: read limit-1 rows, plus one extra to know whether
	// more exist. Both are bounded range scans of events_room_ts.
	older, err := s.queryEvents(ctx, eventsBeforeSQL, roomID, at, centre.Seq, limit) // newest first
	if err != nil {
		return nil, nil, nil, err
	}
	newer, err := s.queryEvents(ctx, eventsAfterSQL, roomID, at, centre.Seq, limit) // oldest first
	if err != nil {
		return nil, nil, nil, err
	}
	nOlder := min(len(older), (limit-1)/2)
	nNewer := min(len(newer), limit-1-nOlder)
	nOlder = min(len(older), limit-1-nNewer) // the older side takes what the newer side left
	moreOlder, moreNewer := len(older) > nOlder, len(newer) > nNewer
	older, newer = older[:nOlder], newer[:nNewer]

	slices.Reverse(newer)
	evs = make([]Event, 0, len(newer)+1+len(older))
	evs = append(append(append(evs, newer...), centre), older...)
	if moreOlder {
		oldest := evs[len(evs)-1]
		before = &Cursor{TS: oldest.TS, Seq: oldest.Seq}
	}
	if moreNewer {
		after = &Cursor{TS: evs[0].TS, Seq: evs[0].Seq}
	}
	return evs, before, after, nil
}

// EventsAfter is the limit events just newer than after, newest first, with the cursor of the newest of them (nil
// when that is the room's newest event).
func (s *Store) EventsAfter(ctx context.Context, roomID string, after Cursor, limit int) ([]Event, *Cursor, error) {
	if limit <= 0 {
		limit = 50
	}
	evs, err := s.queryEvents(ctx, eventsAfterSQL, roomID, after.TS.UnixMilli(), after.Seq, limit+1) // one extra row says whether a newer page exists
	if err != nil {
		return nil, nil, err
	}
	more := len(evs) > limit
	evs = evs[:min(len(evs), limit)]
	slices.Reverse(evs)
	if !more {
		return evs, nil, nil
	}
	return evs, &Cursor{TS: evs[0].TS, Seq: evs[0].Seq}, nil
}

// queryEvents runs a query of eventCols and returns its rows as events, in the query's order.
func (s *Store) queryEvents(ctx context.Context, query string, args ...any) ([]Event, error) {
	rows, err := s.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Event
	for rows.Next() {
		e, err := scanEvent(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}
