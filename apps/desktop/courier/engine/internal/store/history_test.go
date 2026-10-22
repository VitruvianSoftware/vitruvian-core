// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestHistoryListsTheOriginalThenLiveEdits(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mine := func(id, content string, ts int64, status string) {
		insert(t, s, Event{
			RoomID: "!r", EventID: id, Sender: me, Type: "m.room.message", Content: json.RawMessage(content),
			TS: time.Unix(ts, 0), Status: status,
		})
	}
	mine("$m", `{"msgtype":"m.text","body":"v1","format":"org.matrix.custom.html","formatted_body":"<b>v1</b>"}`, 10, "sent")
	mine("$e1", editTo("$m", "v2"), 20, "sent")
	mine("$e2", editTo("$m", "v3"), 30, "failed")  // the network refused it
	mine("$e3", editTo("$m", "v4"), 40, "sent")    // deleted below
	mine("$e4", editTo("$m", "v5"), 60, "pending") // still on its way: it counts, as CurrentText says
	mkMsg(t, s, "!r", "$x", me, "m.room.redaction", redactionOf("$e3"), time.Unix(50, 0))
	mkMsg(t, s, "!r", "$g", ghost, "m.room.message", editTo("$m", "not theirs to edit"), time.Unix(70, 0))

	got, err := s.EditHistory(ctx, "$m")
	require.NoError(t, err)
	require.Equal(t, []Version{
		{Body: "v1", FormattedBody: "<b>v1</b>", TS: time.Unix(10, 0)},
		{Body: "v2", TS: time.Unix(20, 0)},
		{Body: "v5", TS: time.Unix(60, 0)},
	}, got)

	// A reply's history leaves out its fallback; a message never edited is just itself.
	mkMsg(t, s, "!r", "$reply", ghost, "m.room.message", `{"msgtype":"m.text","body":"> <@me:courier.local> v5\n\nagreed",
		"format":"org.matrix.custom.html","formatted_body":"<mx-reply><blockquote>v5</blockquote></mx-reply>agreed",
		"m.relates_to":{"m.in_reply_to":{"event_id":"$m"}}}`, time.Unix(80, 0))
	got, err = s.EditHistory(ctx, "$reply")
	require.NoError(t, err)
	require.Equal(t, []Version{{Body: "agreed", FormattedBody: "agreed", TS: time.Unix(80, 0)}}, got)

	_, err = s.EditHistory(ctx, "$nowhere")
	require.ErrorIs(t, err, ErrNotFound)
	mkMsg(t, s, "!r", "$y", me, "m.room.redaction", redactionOf("$reply"), time.Unix(90, 0))
	_, err = s.EditHistory(ctx, "$reply")
	require.ErrorIs(t, err, ErrNotFound, "a deleted message has no history to show")
}
