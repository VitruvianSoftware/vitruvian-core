// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestListRecentStickersAndGIFs(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r1", time.Unix(100, 0))

	// Insert duplicate stickers with same URL at different timestamps; newest must win and deduplicate by URL.
	mkMsg(t, s, "!r1", "$st1", me, "m.sticker",
		`{"msgtype":"m.image","body":"Wave Old","url":"mxc://courier.local/aaaaaaaa","info":{"mimetype":"image/webp","w":512,"h":512,"fi.mau.bridged_sticker":{"network":"signal","pack_url":"https://signal.art/pack1","id":"1","emoji":"👋"}}}`,
		time.Unix(110, 0))
	mkMsg(t, s, "!r1", "$st2", ghost, "m.sticker",
		`{"msgtype":"m.image","body":"Cat","url":"mxc://courier.local/bbbbbbbb","info":{"mimetype":"image/png","w":256,"h":256}}`,
		time.Unix(120, 0))
	mkMsg(t, s, "!r1", "$st3", me, "m.sticker",
		`{"msgtype":"m.image","body":"Wave New","url":"mxc://courier.local/aaaaaaaa","info":{"mimetype":"image/webp","w":512,"h":512,"fi.mau.bridged_sticker":{"network":"signal","pack_url":"https://signal.art/pack1","id":"1","emoji":"👋"}}}`,
		time.Unix(130, 0))
	// Redacted sticker must be excluded.
	mkMsg(t, s, "!r1", "$st-redacted", me, "m.sticker",
		`{"msgtype":"m.image","body":"Redacted","url":"mxc://courier.local/cccccccc","info":{"mimetype":"image/png","w":128,"h":128}}`,
		time.Unix(140, 0))
	mkMsg(t, s, "!r1", "$redact1", me, "m.room.redaction", `{"redacts":"$st-redacted"}`, time.Unix(141, 0))

	stickers, err := s.ListRecentStickers(ctx, 40)
	require.NoError(t, err)
	require.Len(t, stickers, 2)
	require.Equal(t, "mxc://courier.local/aaaaaaaa", stickers[0].URL)
	require.Equal(t, "Wave New", stickers[0].Body)
	require.Equal(t, "image/webp", stickers[0].MimeType)
	require.Equal(t, 512, stickers[0].Width)
	require.Equal(t, 512, stickers[0].Height)
	require.Equal(t, "signal", stickers[0].BridgedNetwork)
	require.Equal(t, "https://signal.art/pack1", stickers[0].BridgedPackURL)
	require.Equal(t, "1", stickers[0].BridgedStickerID)
	require.Equal(t, "👋", stickers[0].BridgedEmoji)

	require.Equal(t, "mxc://courier.local/bbbbbbbb", stickers[1].URL)
	require.Equal(t, "Cat", stickers[1].Body)

	// Insert GIFs (both info."fi.mau.gif" = true and top-level "fi.mau.gif" = true) and a non-GIF image.
	mkMsg(t, s, "!r1", "$gif1", me, "m.room.message",
		`{"msgtype":"m.image","body":"Party","url":"mxc://courier.local/gif11111","info":{"mimetype":"image/gif","w":320,"h":240,"fi.mau.gif":true}}`,
		time.Unix(200, 0))
	mkMsg(t, s, "!r1", "$img1", me, "m.room.message",
		`{"msgtype":"m.image","body":"Photo","url":"mxc://courier.local/photo111","info":{"mimetype":"image/jpeg","w":800,"h":600}}`,
		time.Unix(210, 0))
	mkMsg(t, s, "!r1", "$gif2", ghost, "m.room.message",
		`{"msgtype":"m.video","body":"Loop","url":"mxc://courier.local/gif22222","info":{"mimetype":"video/mp4","w":400,"h":300,"fi.mau.gif":true}}`,
		time.Unix(220, 0))
	// Duplicate of gif1 at a newer timestamp.
	mkMsg(t, s, "!r1", "$gif3", me, "m.room.message",
		`{"msgtype":"m.image","body":"Party Again","url":"mxc://courier.local/gif11111","info":{"mimetype":"image/gif","w":320,"h":240,"fi.mau.gif":true}}`,
		time.Unix(230, 0))

	gifs, err := s.ListRecentGIFs(ctx, 40)
	require.NoError(t, err)
	require.Len(t, gifs, 2)
	require.Equal(t, "mxc://courier.local/gif11111", gifs[0].URL)
	require.Equal(t, "Party Again", gifs[0].Body)
	require.Equal(t, "mxc://courier.local/gif22222", gifs[1].URL)
	require.Equal(t, "video/mp4", gifs[1].MimeType)

	// Cap at 40 even when more than 40 unique stickers exist.
	for i := range 45 {
		mkMsg(t, s, "!r1", fmt.Sprintf("$bulk-%d", i), me, "m.sticker",
			fmt.Sprintf(`{"msgtype":"m.image","body":"S%d","url":"mxc://courier.local/bulk%04d","info":{"mimetype":"image/png"}}`, i, i),
			time.Unix(int64(300+i), 0))
	}
	capped, err := s.ListRecentStickers(ctx, 0)
	require.NoError(t, err)
	require.Len(t, capped, 40)

	// Failed and held (queued) sends must be excluded from recent stickers and GIFs.
	_, err = s.InsertEvent(ctx, Event{
		RoomID:  "!r1",
		EventID: "$st-failed",
		Sender:  me,
		Type:    "m.sticker",
		Content: []byte(`{"msgtype":"m.image","body":"Failed Sticker","url":"mxc://courier.local/failed111","info":{"mimetype":"image/png"}}`),
		TS:      time.Unix(500, 0),
		Status:  "failed",
	})
	require.NoError(t, err)
	require.NoError(t, s.Hold(ctx, Event{
		RoomID:  "!r1",
		EventID: "$st-held",
		Sender:  me,
		Type:    "m.sticker",
		Content: []byte(`{"msgtype":"m.image","body":"Held Sticker","url":"mxc://courier.local/held1111","info":{"mimetype":"image/png"}}`),
		TS:      time.Unix(501, 0),
	}, time.Unix(510, 0)))

	afterUnsent, err := s.ListRecentStickers(ctx, 40)
	require.NoError(t, err)
	for _, st := range afterUnsent {
		require.NotEqual(t, "mxc://courier.local/failed111", st.URL, "failed sticker must not be listed")
		require.NotEqual(t, "mxc://courier.local/held1111", st.URL, "held sticker must not be listed")
	}

	// 200 repeats of one sticker at the newest timestamps plus 39 other distinct stickers must still return 40 distinct URLs.
	for i := range 200 {
		mkMsg(t, s, "!r1", fmt.Sprintf("$rep-%d", i), me, "m.sticker",
			`{"msgtype":"m.image","body":"Repeat","url":"mxc://courier.local/repeat000","info":{"mimetype":"image/png"}}`,
			time.Unix(int64(1000+i), 0))
	}
	distinct40, err := s.ListRecentStickers(ctx, 40)
	require.NoError(t, err)
	require.Len(t, distinct40, 40, "200 repeats of one sticker plus 39 others must return 40 distinct stickers")
	require.Equal(t, "mxc://courier.local/repeat000", distinct40[0].URL)
}
