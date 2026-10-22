// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package richtext

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type sharedCase struct {
	Name     string   `json:"name"`
	Text     string   `json:"text"`
	Entities []Entity `json:"entities"`
	Keep     []Kind   `json:"keep"`
	HTML     string   `json:"html"`
	Body     string   `json:"body"`
}

// casesPath finds apps/desktop/courier/protocol/richtext/cases.json: in the test's runfiles under Bazel, and by
// its place in the source tree otherwise.
func casesPath(t testing.TB) string {
	t.Helper()
	const rel = "apps/desktop/courier/protocol/richtext/cases.json"
	var tried []string
	if srcdir := os.Getenv("TEST_SRCDIR"); srcdir != "" {
		ws := os.Getenv("TEST_WORKSPACE")
		if ws == "" {
			ws = "_main"
		}
		tried = append(tried, filepath.Join(srcdir, ws, rel), filepath.Join(srcdir, rel))
	}
	tried = append(tried, filepath.Join("..", "..", "..", "protocol", "richtext", "cases.json"))
	for _, p := range tried {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	t.Fatalf("cases.json not found; tried %v", tried)
	return ""
}

func readCases(t testing.TB) []sharedCase {
	t.Helper()
	raw, err := os.ReadFile(casesPath(t))
	require.NoError(t, err)
	var file struct {
		Cases []sharedCase `json:"cases"`
	}
	dec := json.NewDecoder(strings.NewReader(string(raw)))
	dec.DisallowUnknownFields()
	var loose struct {
		About string            `json:"about"`
		Cases []json.RawMessage `json:"cases"`
	}
	require.NoError(t, dec.Decode(&loose))
	for _, c := range loose.Cases {
		var sc sharedCase
		d := json.NewDecoder(strings.NewReader(string(c)))
		d.DisallowUnknownFields()
		require.NoError(t, d.Decode(&sc), "%s", c)
		file.Cases = append(file.Cases, sc)
	}
	require.NotEmpty(t, file.Cases)
	return file.Cases
}

func keepOnly(kinds ...Kind) func(Kind) bool {
	return func(k Kind) bool { return slices.Contains(kinds, k) }
}

func keepAll(Kind) bool  { return true }
func keepNone(Kind) bool { return false }

func TestSharedCases(t *testing.T) {
	cases := readCases(t)
	assert.GreaterOrEqual(t, len(cases), 25)
	seen := map[Kind]bool{}
	for _, c := range cases {
		t.Run(c.Name, func(t *testing.T) {
			require.NoError(t, Check(c.Text, c.Entities), "every shared case is well formed")
			got := Render(c.Text, c.Entities, keepOnly(c.Keep...))
			assert.Equal(t, c.HTML, got.HTML)
			assert.Equal(t, c.Body, got.Body)
			for _, e := range c.Entities {
				seen[e.Kind] = true
			}
		})
	}
	for _, k := range Kinds {
		assert.True(t, seen[k], "the shared cases use %s", k)
	}
}

// Review Focus 4: typed characters are never formatting.
func TestTypedTextIsNeverFormatting(t *testing.T) {
	for _, s := range []string{
		"2*3*4", "snake_case_name", "<b>hi</b>", "#1 priority", `C:\path\to`, "https://x.test/a_b_c", "**",
		"🎉 שלום", "`code`", "~~gone~~", "> not a quote", "- not a list", "1. not a list", "||spoiler||",
	} {
		t.Run(s, func(t *testing.T) {
			require.NoError(t, Check(s, nil))
			for _, keep := range []func(Kind) bool{keepAll, keepNone} {
				got := Render(s, nil, keep)
				assert.Equal(t, "", got.HTML)
				assert.Equal(t, s, got.Body)
				assert.Empty(t, got.UserIDs)
				assert.False(t, got.Room)
			}
		})
	}
}

func plainNetworkMessage() (string, []Entity) {
	text := "Hi @Ana, see docs\none\ntwo\nquoted"
	return text, []Entity{
		{Kind: Mention, Offset: 3, Length: 4, UserID: "@ana:x.test"},
		{Kind: Bold, Offset: 0, Length: 2},
		{Kind: Link, Offset: 13, Length: 4, URL: "https://x.test"},
		{Kind: Bullets, Offset: 18, Length: 7},
		{Kind: Quote, Offset: 26, Length: 6},
	}
}

// Review Focus 4: a bold, linked, mentioned, listed message to a network that keeps nothing reads well as text.
func TestPlainNetworksGetReadableText(t *testing.T) {
	text, ents := plainNetworkMessage()
	require.NoError(t, Check(text, ents))
	got := Render(text, ents, keepNone)
	assert.Equal(t, "Hi @Ana, see docs (https://x.test)\n• one\n• two\n> quoted", got.Body)
	assert.Equal(t, "", got.HTML)
	assert.Empty(t, got.UserIDs, "a mention the chat doesn't keep is only text")

	all := Render(text, ents, keepAll)
	assert.Equal(t, got.Body, all.Body, "the body doesn't depend on what the chat keeps")
	assert.Equal(t, `<strong>Hi</strong> <a href="https://matrix.to/#/@ana:x.test">@Ana</a>, see <a href="https://x.test">docs</a>`+
		`<ul><li>one</li><li>two</li></ul><blockquote>quoted</blockquote>`, all.HTML)
	assert.Equal(t, []string{"@ana:x.test"}, all.UserIDs)
}

// An empty line inside a list takes no marker and no item; the numbering carries on after it.
func TestListsSkipEmptyLines(t *testing.T) {
	text := "a\n\nb\n\n\nc"
	for _, tc := range []struct {
		kind                  Kind
		body, html, plainHTML string
	}{
		{
			Bullets, "• a\n\n• b\n\n\n• c",
			"<ul><li>a</li></ul><br><br><ul><li>b</li></ul><br><br><br><ul><li>c</li></ul>",
			"• <strong>a</strong><br><br>• b<br><br><br>• c",
		},
		{
			Numbered, "1. a\n\n2. b\n\n\n3. c",
			`<ol><li>a</li></ol><br><br><ol start="2"><li>b</li></ol><br><br><br><ol start="3"><li>c</li></ol>`,
			"1. <strong>a</strong><br><br>2. b<br><br><br>3. c",
		},
	} {
		ents := []Entity{{Kind: tc.kind, Offset: 0, Length: len(text)}}
		require.NoError(t, Check(text, ents))
		got := Render(text, ents, keepAll)
		assert.Equal(t, tc.body, got.Body)
		assert.Equal(t, tc.html, got.HTML)
		assert.NotContains(t, got.HTML, "<li></li>")

		// Kept bold but not the list: the plain markers in the HTML skip the empty lines too.
		plain := Render(text, append(ents, Entity{Kind: Bold, Offset: 0, Length: 1}), keepOnly(Bold))
		assert.Equal(t, tc.body, plain.Body)
		assert.Equal(t, tc.plainHTML, plain.HTML)
	}
}

func TestMentionsListUsersOnce(t *testing.T) {
	text := "@Ana and @Bo and @Ana and @room"
	ents := []Entity{
		{Kind: Mention, Offset: 17, Length: 4, UserID: "@ana:x.test"},
		{Kind: Mention, Offset: 0, Length: 4, UserID: "@ana:x.test"},
		{Kind: Mention, Offset: 9, Length: 3, UserID: "@bo:x.test"},
		{Kind: Mention, Offset: 26, Length: 5, UserID: "@room"},
	}
	require.NoError(t, Check(text, ents))
	got := Render(text, ents, keepOnly(Mention))
	assert.Equal(t, []string{"@ana:x.test", "@bo:x.test"}, got.UserIDs, "in the order they appear, each once")
	assert.True(t, got.Room)
	assert.Contains(t, got.HTML, "and @room", "@room is plain text")

	none := Render(text, ents, keepOnly(Bold))
	assert.Empty(t, none.UserIDs)
	assert.False(t, none.Room)
	assert.Equal(t, "", none.HTML)
}

func TestCheckRefuses(t *testing.T) {
	const text = "ab🎉cd\nline two\nthree"
	for _, tc := range []struct {
		name string
		text string
		ents []Entity
	}{
		{"past the end", text, []Entity{{Kind: Bold, Offset: 20, Length: 5}}},
		{"negative offset", text, []Entity{{Kind: Bold, Offset: -1, Length: 2}}},
		{"negative length", text, []Entity{{Kind: Bold, Offset: 2, Length: -1}}},
		{"huge length", text, []Entity{{Kind: Bold, Offset: 2, Length: int(^uint(0) >> 1)}}},
		{"empty range", text, []Entity{{Kind: Bold, Offset: 1, Length: 0}}},
		{"starts inside a surrogate pair", text, []Entity{{Kind: Bold, Offset: 3, Length: 2}}},
		{"ends inside a surrogate pair", text, []Entity{{Kind: Bold, Offset: 0, Length: 3}}},
		{"unknown kind", text, []Entity{{Kind: "underline", Offset: 0, Length: 2}}},
		{"javascript link", text, []Entity{{Kind: Link, Offset: 0, Length: 2, URL: "javascript:alert(1)"}}},
		{"JavaScript link", text, []Entity{{Kind: Link, Offset: 0, Length: 2, URL: "JaVaScRiPt:alert(1)"}}},
		{"javascript with a tab in the scheme", text, []Entity{{Kind: Link, Offset: 0, Length: 2, URL: "java\tscript:alert(1)"}}},
		{"javascript with an escaped colon", text, []Entity{{Kind: Link, Offset: 0, Length: 2, URL: "javascript&#58;alert(1)"}}},
		{"data link", text, []Entity{{Kind: Link, Offset: 0, Length: 2, URL: "data:text/html,hi"}}},
		{"link without a scheme", text, []Entity{{Kind: Link, Offset: 0, Length: 2, URL: "x.test"}}},
		{"link without a host", text, []Entity{{Kind: Link, Offset: 0, Length: 2, URL: "https:///a"}}},
		{"link with a space", text, []Entity{{Kind: Link, Offset: 0, Length: 2, URL: "https://x.test/a b"}}},
		{"link with a quote breaking out", text, []Entity{{Kind: Link, Offset: 0, Length: 2, URL: "https://x.test/\" onclick=\"x"}}},
		{"empty link", text, []Entity{{Kind: Link, Offset: 0, Length: 2}}},
		{"link across lines", text, []Entity{{Kind: Link, Offset: 5, Length: 3, URL: "https://x.test"}}},
		{"mention without a user", text, []Entity{{Kind: Mention, Offset: 0, Length: 2}}},
		{"mention of something that isn't a user", text, []Entity{{Kind: Mention, Offset: 0, Length: 2, UserID: "ana"}}},
		{"mention across lines", text, []Entity{{Kind: Mention, Offset: 5, Length: 3, UserID: "@ana:x.test"}}},
		{"quote starting mid-line", text, []Entity{{Kind: Quote, Offset: 1, Length: 5}}},
		{"quote ending mid-line", text, []Entity{{Kind: Quote, Offset: 7, Length: 4}}},
		{"list starting mid-line", text, []Entity{{Kind: Bullets, Offset: 9, Length: 7}}},
		{"code block ending mid-line", text, []Entity{{Kind: Pre, Offset: 0, Length: 2}}},
		{"two blocks on one line", text, []Entity{{Kind: Quote, Offset: 7, Length: 8}, {Kind: Bullets, Offset: 7, Length: 8}}},
		{"overlapping blocks", text, []Entity{{Kind: Pre, Offset: 0, Length: 15}, {Kind: Numbered, Offset: 7, Length: 14}}},
		{"overlapping links", text, []Entity{
			{Kind: Link, Offset: 0, Length: 2, URL: "https://x.test"}, {Kind: Link, Offset: 1, Length: 3, URL: "https://x.test"},
		}},
		{"a mention overlapping a link", text, []Entity{
			{Kind: Link, Offset: 7, Length: 4, URL: "https://x.test"}, {Kind: Mention, Offset: 9, Length: 3, UserID: "@ana:x.test"},
		}},
		{"code overlapping a link", text, []Entity{
			{Kind: Link, Offset: 7, Length: 4, URL: "https://x.test"}, {Kind: Code, Offset: 9, Length: 4},
		}},
		{"too many", "x", slices.Repeat([]Entity{{Kind: Bold, Offset: 0, Length: 1}}, MaxEntities+1)},
	} {
		t.Run(tc.name, func(t *testing.T) {
			err := Check(tc.text, tc.ents)
			require.ErrorIs(t, err, ErrBadEntity)
			assert.NotContains(t, err.Error(), "line two", "an error never carries the message's text")
			assert.NotPanics(t, func() { Render(tc.text, tc.ents, keepAll) }, "Render copes with what Check refuses")
		})
	}
}

func TestCheckAccepts(t *testing.T) {
	const text = "ab🎉cd\nline two\nthree\n"
	for _, tc := range []struct {
		name string
		ents []Entity
	}{
		{"around a surrogate pair", []Entity{{Kind: Bold, Offset: 2, Length: 2}}},
		{"a block ending on its newline", []Entity{{Kind: Quote, Offset: 7, Length: 9}}},
		{"a block that is the whole text", []Entity{{Kind: Pre, Offset: 0, Length: 22}}},
		{"a block on the last line", []Entity{{Kind: Bullets, Offset: 16, Length: 6}}},
		{"blocks on neighbouring lines", []Entity{{Kind: Quote, Offset: 0, Length: 6}, {Kind: Bullets, Offset: 7, Length: 8}}},
		{"overlapping styles", []Entity{{Kind: Bold, Offset: 0, Length: 6}, {Kind: Italic, Offset: 1, Length: 10}}},
		{"styles across lines", []Entity{{Kind: Strike, Offset: 1, Length: 12}}},
		{"a mailto link", []Entity{{Kind: Link, Offset: 0, Length: 2, URL: "mailto:ana@x.test"}}},
		{"an HTTP link in capitals", []Entity{{Kind: Link, Offset: 0, Length: 2, URL: "HTTP://X.TEST"}}},
		{"@room", []Entity{{Kind: Mention, Offset: 0, Length: 2, UserID: "@room"}}},
		{"a link inside a code block (dropped)", []Entity{
			{Kind: Pre, Offset: 7, Length: 8}, {Kind: Link, Offset: 7, Length: 4, URL: "https://x.test"},
		}},
		{"exactly MaxEntities", slices.Repeat([]Entity{{Kind: Bold, Offset: 0, Length: 1}}, MaxEntities)},
	} {
		t.Run(tc.name, func(t *testing.T) {
			assert.NoError(t, Check(text, tc.ents))
		})
	}
}

// Ranges count UTF-16 code units, as the composer's NSRange does: an emoji is two.
func TestRangesCountUTF16(t *testing.T) {
	text := "🎉🎉 big news"
	ents := []Entity{{Kind: Bold, Offset: 5, Length: 3}}
	require.NoError(t, Check(text, ents))
	assert.Equal(t, "🎉🎉 <strong>big</strong> news", Render(text, ents, keepAll).HTML)

	// A flag is two code points of two units each; a keycap has a combining mark.
	text = "🇳🇿 1️⃣ ok"
	ents = []Entity{{Kind: Italic, Offset: 9, Length: 2}}
	require.NoError(t, Check(text, ents))
	assert.Equal(t, "🇳🇿 1️⃣ <em>ok</em>", Render(text, ents, keepAll).HTML)
}

func TestLinkSchemes(t *testing.T) {
	text := "go"
	for _, u := range []string{"https://x.test", "http://x.test/a?b=c&d=\"e\"", "mailto:ana@x.test"} {
		ents := []Entity{{Kind: Link, Offset: 0, Length: 2, URL: u}}
		require.NoError(t, Check(text, ents), u)
		got := Render(text, ents, keepAll)
		assert.Contains(t, got.HTML, `<a href="`, u)
		assert.NotContains(t, got.HTML, `"e"`, "quotes in an address are escaped")
	}
	// Render without Check never builds a link to an unsafe scheme: the text stays plain.
	for _, u := range []string{"javascript:alert(1)", "vbscript:x", "data:text/html,x", "file:///etc", "//x.test", " https://x.test"} {
		got := Render(text, []Entity{{Kind: Link, Offset: 0, Length: 2, URL: u}}, keepAll)
		assert.Equal(t, "", got.HTML, u)
		assert.Equal(t, "go", got.Body, u)
	}
}

func TestRenderDropsWhatCheckRefuses(t *testing.T) {
	text := "ab🎉cd"
	got := Render(text, []Entity{
		{Kind: Bold, Offset: 3, Length: 2},    // splits the emoji
		{Kind: Italic, Offset: 0, Length: 99}, // past the end
		{Kind: "underline", Offset: 0, Length: 1},
		{Kind: Mention, Offset: 0, Length: 1},
		{Kind: Strike, Offset: 0, Length: 2},
	}, keepAll)
	assert.Equal(t, "<del>ab</del>🎉cd", got.HTML)
	assert.Equal(t, text, got.Body)
}

func TestNulAndInvalidUTF8BecomeReplacementCharacters(t *testing.T) {
	got := Render("a\x00b\xffc", []Entity{{Kind: Bold, Offset: 0, Length: 1}}, keepAll)
	assert.Equal(t, "a\uFFFDb\uFFFDc", got.Body)
	assert.Equal(t, "<strong>a</strong>\uFFFDb\uFFFDc", got.HTML)
}

func TestCarriageReturnSurvivesTheHTML(t *testing.T) {
	got := Render("a\r\nb", []Entity{{Kind: Bold, Offset: 0, Length: 1}}, keepAll)
	assert.Equal(t, "a\r\nb", got.Body)
	assert.Equal(t, "<strong>a</strong>&#13;<br>b", got.HTML)
}

func TestEntityJSON(t *testing.T) {
	raw, err := json.Marshal(Entity{Kind: Link, Offset: 1, Length: 2, URL: "https://x.test"})
	require.NoError(t, err)
	assert.JSONEq(t, `{"type":"link","offset":1,"length":2,"url":"https://x.test"}`, string(raw))
}
