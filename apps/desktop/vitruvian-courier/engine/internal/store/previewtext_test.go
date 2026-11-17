// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestPlainPreview(t *testing.T) {
	for _, tc := range []struct{ name, in, want string }{
		{"bold in the middle", "⏳ **Tournament run - Mon 16 Nov 2026** — running", "⏳ Tournament run - Mon 16 Nov 2026 — running"},
		{"quoted line with bold", "> **Chandini**\n> New channel is live: #inference-g4-prod…", "Chandini New channel is live: #inference-g4-prod…"},
		{"entities", "&gt; hello &amp; goodbye &lt;3", "hello & goodbye <3"},
		{"slack marks", "*bold* and _italic_ and ~gone~", "bold and italic and gone"},
		{"double marks", "__under__ ~~strike~~ **star**", "under strike star"},
		{"snake_case survives", "restart my_service_name now", "restart my_service_name now"},
		{"snake_case next to italics", "_note_ use file_name_v2", "note use file_name_v2"},
		{"math stars survive", "2 * 3 * 4", "2 * 3 * 4"},
		{"inline code", "run `kubectl get pods` now", "run kubectl get pods now"},
		{"fenced code", "look:\n```go\nfmt.Println(1)\n```\ndone", "look: fmt.Println(1) done"},
		{"nested quotes", ">> deep\n> shallow\nplain", "deep shallow plain"},
		{"slack link with label", "see <https://example.com/x|the doc> please", "see the doc please"},
		{"slack bare link", "see <https://example.com/x>", "see https://example.com/x"},
		{"slack user and channel", "<@U123|ann> in <#C1|general>", "@ann in #general"},
		{"slack here", "<!here> standup", "@here standup"},
		{"markdown link", "[docs](https://example.com) are up", "docs are up"},
		{"newlines collapse", "one\n\n two\r\nthree", "one two three"},
		{"emoji kept", "❤️ 👍🏽 done", "❤️ 👍🏽 done"},
		{"adjacent italics", "_a_ _b_", "a b"},
		{"lone star stays", "5* off", "5* off"},
		{"cyrillic snake_case survives", "снег_зима и д*в", "снег_зима и д*в"},
		{"cyrillic italics", "_снег_ и *зима*", "снег и зима"},
		{"cjk and accents", "日本語_テスト café_au_lait", "日本語_テスト café_au_lait"},
		{"url underscores survive", "see https://x.org/_draft_ now", "see https://x.org/_draft_ now"},
		{"url stars survive", "**read** https://x.org/a*b*c", "read https://x.org/a*b*c"},
		{"url keeps trailing text clean", "_see_ (https://x.org/a_b_c).", "see (https://x.org/a_b_c)."},
		{"two urls", "https://a.io/_x_ and https://b.io/_y_", "https://a.io/_x_ and https://b.io/_y_"},
		{"empty", "", ""},
	} {
		t.Run(tc.name, func(t *testing.T) { require.Equal(t, tc.want, plainPreview(tc.in)) })
	}
}

func msgContent(msgtype, body string, extra map[string]any) string {
	m := map[string]any{"msgtype": msgtype, "body": body}
	for k, v := range extra {
		m[k] = v
	}
	b, _ := json.Marshal(m)
	return string(b)
}

func TestPreviewOfStripsFormatting(t *testing.T) {
	body, kind, _ := previewOf("m.room.message", msgContent("m.text", "**Hi** there", nil))
	require.Equal(t, "Hi there", body)
	require.Equal(t, "text", kind)
}

func TestPreviewOfMediaCaptions(t *testing.T) {
	for _, tc := range []struct {
		name, msgtype, body string
		extra               map[string]any
		wantKind, wantBody  string
	}{
		{"image with a url body", "m.image", "https://www.facebook.com/messenger_media/?attachment_id=1", nil, "image", ""},
		{"image named by its file", "m.image", "IMG_2041.jpg", nil, "image", ""},
		{"image body equals filename field", "m.image", "photo", map[string]any{"filename": "photo"}, "image", ""},
		{"image with a caption", "m.image", "Sunset at the lake", map[string]any{"filename": "IMG_2041.jpg"}, "image", "Sunset at the lake"},
		{"video named by its file", "m.video", "clip.mp4", nil, "video", ""},
		{"voice note named by its file", "m.audio", "voice.ogg", nil, "audio", ""},
		{"file keeps its name", "m.file", "report.pdf", nil, "file", "report.pdf"},
		{"file with a url body", "m.file", "https://example.com/r.pdf", nil, "file", ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			body, kind, _ := previewOf("m.room.message", msgContent(tc.msgtype, tc.body, tc.extra))
			require.Equal(t, tc.wantKind, kind)
			require.Equal(t, tc.wantBody, body)
		})
	}
}

func TestReactionPreviewStripsQuotedFormatting(t *testing.T) {
	target := msgContent("m.text", "⏳ **Tournament run - Mon 16 Nov 2026** — running", nil)
	require.Equal(t, "❤️ to “⏳ Tournament run - Mon 16 Nov 2026 — running”",
		reactionPreview(`{"m.relates_to":{"key":"❤️"}}`, "m.room.message", target))
	target = msgContent("m.text", "> **Chandini**\n> New channel is live: #inference-g4-prod", nil)
	require.Equal(t, "👍 to “Chandini New channel is live: #inference-g4-prod”",
		reactionPreview(`{"m.relates_to":{"key":"👍"}}`, "m.room.message", target))
}
