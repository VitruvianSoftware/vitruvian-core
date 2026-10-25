// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/media"
)

// seedHistory gives roomID n messages $000…, oldest first, perTS of them sharing each timestamp (so that, within a
// timestamp, only seq orders them). It returns their IDs, oldest first.
func seedHistory(t *testing.T, s *Store, roomID string, n, perTS int) []string {
	t.Helper()
	mkRoom(t, s, roomID, time.Unix(1, 0))
	var ids []string
	for i := 0; i < n; i++ {
		id := fmt.Sprintf("$%s-%03d", strings.TrimPrefix(roomID, "!"), i)
		ids = append(ids, id)
		mkMsg(t, s, roomID, id, ghost, "m.room.message", text("x"), time.Unix(int64(1000+i/perTS), 0))
	}
	return ids
}

func idsOf(evs []Event) []string {
	out := make([]string, 0, len(evs))
	for _, e := range evs {
		out = append(out, e.EventID)
	}
	return out
}

// newestFirst is ids[lo:hi] reversed: how a page of them comes back.
func newestFirst(ids []string, lo, hi int) []string {
	var out []string
	for i := hi - 1; i >= lo; i-- {
		out = append(out, ids[i])
	}
	return out
}

func cursorOf(t *testing.T, s *Store, eventID string) *Cursor {
	t.Helper()
	e, ok, err := s.GetEvent(context.Background(), eventID)
	require.NoError(t, err)
	require.True(t, ok)
	return &Cursor{TS: e.TS, Seq: e.Seq}
}

func TestAroundCentresOnTheMessage(t *testing.T) {
	s, ctx := open(t), context.Background()
	ids := seedHistory(t, s, "!r", 100, 1)

	evs, before, after, err := s.EventsAround(ctx, "!r", ids[29], 10)
	require.NoError(t, err)
	require.Equal(t, newestFirst(ids, 25, 35), idsOf(evs), "the 4 older, the 30th itself, the 5 newer; newest first")
	require.Equal(t, cursorOf(t, s, ids[25]), before, "before is the oldest of the page")
	require.Equal(t, cursorOf(t, s, ids[34]), after, "after is the newest of the page")

	// The pages either side carry on exactly where this one stops.
	older, _, err := s.EventsBefore(ctx, "!r", before, 5)
	require.NoError(t, err)
	require.Equal(t, newestFirst(ids, 20, 25), idsOf(older))
	newer, _, err := s.EventsAfter(ctx, "!r", *after, 5)
	require.NoError(t, err)
	require.Equal(t, newestFirst(ids, 35, 40), idsOf(newer))
}

func TestAroundAtTheEdges(t *testing.T) {
	s, ctx := open(t), context.Background()
	ids := seedHistory(t, s, "!r", 100, 1)

	evs, before, after, err := s.EventsAround(ctx, "!r", ids[99], 10)
	require.NoError(t, err)
	require.Equal(t, newestFirst(ids, 90, 100), idsOf(evs), "the newest: the older side takes the slots the newer can't fill")
	require.Nil(t, after, "the page has the room's newest event")
	require.Equal(t, cursorOf(t, s, ids[90]), before)

	evs, before, after, err = s.EventsAround(ctx, "!r", ids[97], 10)
	require.NoError(t, err)
	require.Equal(t, newestFirst(ids, 90, 100), idsOf(evs), "near the newest: 2 newer, so 7 older")
	require.Nil(t, after, "the page has the room's newest event")
	require.Equal(t, cursorOf(t, s, ids[90]), before)

	evs, before, after, err = s.EventsAround(ctx, "!r", ids[0], 10)
	require.NoError(t, err)
	require.Equal(t, newestFirst(ids, 0, 10), idsOf(evs), "the oldest: itself and the rest newer")
	require.Nil(t, before, "nothing is older than the oldest")
	require.Equal(t, cursorOf(t, s, ids[9]), after)

	evs, before, after, err = s.EventsAround(ctx, "!r", ids[2], 10)
	require.NoError(t, err)
	require.Equal(t, newestFirst(ids, 0, 10), idsOf(evs), "near the oldest: 2 older, so 7 newer")
	require.Nil(t, before, "the page has the room's oldest event")
	require.Equal(t, cursorOf(t, s, ids[9]), after)

	// A room shorter than the page: all of it, no cursor either way.
	short := seedHistory(t, s, "!short", 6, 1)
	evs, before, after, err = s.EventsAround(ctx, "!short", short[4], 10)
	require.NoError(t, err)
	require.Equal(t, newestFirst(short, 0, 6), idsOf(evs))
	require.Nil(t, before)
	require.Nil(t, after)

	// One short of an edge still reports the edge's cursor: the extra row is what decides.
	evs, before, after, err = s.EventsAround(ctx, "!r", ids[94], 10)
	require.NoError(t, err)
	require.Equal(t, newestFirst(ids, 90, 100), idsOf(evs))
	require.Nil(t, after, "the page reaches the newest event exactly")
	require.NotNil(t, before)

	// A page of one is just the event, with cursors both ways.
	evs, before, after, err = s.EventsAround(ctx, "!r", ids[50], 1)
	require.NoError(t, err)
	require.Equal(t, []string{ids[50]}, idsOf(evs))
	require.Equal(t, cursorOf(t, s, ids[50]), before)
	require.Equal(t, cursorOf(t, s, ids[50]), after)

	// A room of one event: no cursor either way.
	only := seedHistory(t, s, "!one", 1, 1)
	evs, before, after, err = s.EventsAround(ctx, "!one", only[0], 10)
	require.NoError(t, err)
	require.Equal(t, only, idsOf(evs))
	require.Nil(t, before)
	require.Nil(t, after)
}

func TestAfterWalksForwardToTheNewest(t *testing.T) {
	for _, limit := range []int{7, 33} { // 99 events after the oldest: 7 leaves a short last page, 33 divides exactly
		t.Run(fmt.Sprint(limit), func(t *testing.T) {
			s, ctx := open(t), context.Background()
			ids := seedHistory(t, s, "!r", 100, 1)

			_, _, cur, err := s.EventsAround(ctx, "!r", ids[0], 1)
			require.NoError(t, err)
			require.NotNil(t, cur)
			got := []string{ids[0]}
			for pages := 0; cur != nil; pages++ {
				require.Less(t, pages, 100, "the walk ends")
				evs, next, err := s.EventsAfter(ctx, "!r", *cur, limit)
				require.NoError(t, err)
				require.NotEmpty(t, evs, "a cursor never leads to an empty page")
				require.LessOrEqual(t, len(evs), limit)
				// Each page is newest first, so walking forward reads it from its end.
				for i := len(evs) - 1; i >= 0; i-- {
					got = append(got, evs[i].EventID)
				}
				if next != nil {
					require.Equal(t, &Cursor{TS: evs[0].TS, Seq: evs[0].Seq}, next, "the cursor is the newest of the page")
				}
				cur = next
			}
			require.Equal(t, ids, got, "every event once, in order, ending at the newest")
		})
	}

	s, ctx := open(t), context.Background()
	ids := seedHistory(t, s, "!r", 3, 1)
	evs, next, err := s.EventsAfter(ctx, "!r", *cursorOf(t, s, ids[2]), 10)
	require.NoError(t, err)
	require.Empty(t, evs, "nothing is newer than the newest")
	require.Nil(t, next)
}

func TestEqualTimestampsKeepSeqOrder(t *testing.T) {
	s, ctx := open(t), context.Background()
	ids := seedHistory(t, s, "!r", 60, 3) // three events share each timestamp

	for _, centre := range []int{0, 1, 2, 28, 29, 30, 31, 57, 58, 59} {
		for _, limit := range []int{1, 2, 5, 10} {
			evs, before, after, err := s.EventsAround(ctx, "!r", ids[centre], limit)
			require.NoError(t, err)
			require.Contains(t, idsOf(evs), ids[centre])

			// Older pages through EventsBefore, newer through EventsAfter: together with this page, the whole
			// history exactly once, in order.
			all := idsOf(evs)
			for cur := before; cur != nil; {
				page, next, err := s.EventsBefore(ctx, "!r", cur, limit)
				require.NoError(t, err)
				all = append(all, idsOf(page)...)
				cur = next
			}
			for cur := after; cur != nil; {
				page, next, err := s.EventsAfter(ctx, "!r", *cur, limit)
				require.NoError(t, err)
				all = append(idsOf(page), all...)
				cur = next
			}
			require.Equal(t, newestFirst(ids, 0, len(ids)), all, "centre %d, limit %d", centre, limit)
		}
	}
}

func TestAroundAnEventInAnotherRoomIsNotFound(t *testing.T) {
	s, ctx := open(t), context.Background()
	seedHistory(t, s, "!a", 5, 1)
	b := seedHistory(t, s, "!b", 5, 1)

	evs, before, after, err := s.EventsAround(ctx, "!a", b[2], 10)
	require.ErrorIs(t, err, ErrNotFound, "never a page from the wrong chat")
	require.Nil(t, evs)
	require.Nil(t, before)
	require.Nil(t, after)

	_, _, _, err = s.EventsAround(ctx, "!a", "$nope", 10)
	require.ErrorIs(t, err, ErrNotFound)
	_, _, _, err = s.EventsAround(ctx, "!nope", b[2], 10)
	require.ErrorIs(t, err, ErrNotFound)
}

func TestAroundAndAfterAreIndexed(t *testing.T) {
	s := open(t)
	seedBig(t, s, 2000, 5, 10000)

	for name, plan := range map[string][]string{
		"centre": planOf(t, s, eventAtSQL, "$!long-5000", "!long"),
		"older":  planOf(t, s, eventsBeforeSQL, "!long", int64(1_002_500), int64(5000), 6),
		"newer":  planOf(t, s, eventsAfterSQL, "!long", int64(1_002_500), int64(5000), 6),
	} {
		t.Run(name, func(t *testing.T) {
			requireIndexed(t, plan)
			if name != "centre" { // the centre is a primary-key lookup by event ID
				require.Contains(t, strings.Join(plan, "\n"), "events_room_ts")
			}
		})
	}
}

func newTestStoreWithMedia(t *testing.T) (*Store, *media.Store) {
	t.Helper()
	dir := t.TempDir()
	s, err := Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	return s, &media.Store{Dir: filepath.Join(dir, "media")}
}

func TestExtractEventPopulatesWaveformBlurHashLocationLinkPreviewsAndViewOnce(t *testing.T) {
	ctx := context.Background()
	s, ms := newTestStoreWithMedia(t)

	mediaHash, err := ms.Put([]byte("fake-media-bytes"))
	require.NoError(t, err)
	mxcURI := "mxc://courier.local/" + mediaHash
	localMediaPath, err := ms.Path(mediaHash)
	require.NoError(t, err)

	voiceEvt := extractEvent(ctx, s, ms, "!r:courier.local", rawRow{
		eventID: "$v1",
		sender:  "@alice:courier.local",
		evtType: "m.room.message",
		content: `{"msgtype":"m.audio","body":"Voice message.ogg","url":"` + mxcURI + `","org.matrix.msc3245.voice":{},"org.matrix.msc1767.audio":{"duration":4200,"waveform":[10,200,500,900]}}`,
	})
	require.Equal(t, "voice", voiceEvt.Kind)
	require.Equal(t, 4200, voiceEvt.DurationMS)
	require.Equal(t, []int{10, 200, 500, 900}, voiceEvt.Waveform)
	require.Equal(t, localMediaPath, voiceEvt.MediaPath)

	imgEvt := extractEvent(ctx, s, ms, "!r:courier.local", rawRow{
		eventID: "$img1",
		sender:  "@alice:courier.local",
		evtType: "m.room.message",
		content: `{"msgtype":"m.image","body":"secret.jpg","url":"` + mxcURI + `","info":{"mimetype":"image/gif","w":320,"h":240,"xyz.amorgan.blurhash":"LEHV6nWB2yk8pyo0adR*.7kCMdnj","thumbnail_url":"` + mxcURI + `","fi.mau.gif":true,"is_animated":true},"com.beeper.disappearing_timer":{"type":"after_read","timer":300000}}`,
	})
	require.Equal(t, "image", imgEvt.Kind)
	require.Equal(t, "LEHV6nWB2yk8pyo0adR*.7kCMdnj", imgEvt.BlurHash)
	require.Equal(t, localMediaPath, imgEvt.ThumbnailPath)
	require.True(t, imgEvt.IsGIF)
	require.True(t, imgEvt.IsAnimated)
	require.True(t, imgEvt.ViewOnce)

	require.NoError(t, s.MarkMediaPlayed(ctx, "!r:courier.local", "$img1", 1700000000000))
	playedEvt := extractEvent(ctx, s, ms, "!r:courier.local", rawRow{
		eventID: "$img1",
		sender:  "@alice:courier.local",
		evtType: "m.room.message",
		content: `{"msgtype":"m.image","body":"secret.jpg","url":"` + mxcURI + `","info":{"thumbnail_url":"` + mxcURI + `"},"com.beeper.disappearing_timer":{"type":"after_read","timer":300000}}`,
	})
	require.True(t, playedEvt.Played)
	require.Empty(t, playedEvt.MediaPath, "view-once media path must be redacted once played")
	require.Empty(t, playedEvt.ThumbnailPath, "view-once thumbnail path must be redacted once played")

	locEvt := extractEvent(ctx, s, ms, "!r:courier.local", rawRow{
		eventID: "$loc1",
		sender:  "@alice:courier.local",
		evtType: "m.room.message",
		content: `{"msgtype":"m.location","body":"Golden Gate Bridge","geo_uri":"geo:37.8199,-122.4783"}`,
	})
	require.Equal(t, "location", locEvt.Kind)
	require.Equal(t, "geo:37.8199,-122.4783", locEvt.GeoURI)

	linkEvt := extractEvent(ctx, s, ms, "!r:courier.local", rawRow{
		eventID: "$link1",
		sender:  "@alice:courier.local",
		evtType: "m.room.message",
		content: `{"msgtype":"m.text","body":"check https://example.com","com.beeper.linkpreviews":[{"matched_url":"https://example.com","og:url":"https://example.com/page","og:title":"Example Domain","og:site_name":"Example","og:description":"Illustrative examples","og:image":"https://remote.example.com/track.png","og:image:width":600,"og:image:height":315,"matrix:image:blurhash":"LEHV6nWB2yk8pyo0adR*.7kCMdnj"}]}`,
	})
	require.Len(t, linkEvt.LinkPreviews, 1)
	require.Equal(t, "Example Domain", linkEvt.LinkPreviews[0].Title)
	require.Empty(t, linkEvt.LinkPreviews[0].ImagePath, "remote HTTP og:image URLs must never be resolved or fetched")
}
