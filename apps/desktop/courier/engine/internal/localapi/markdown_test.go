// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localapi

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
)

func TestMarkdownBecomesFormattingRanges(t *testing.T) {
	for _, c := range []struct {
		in   string
		text string
		ents []richtext.Entity
	}{
		{"plain text", "plain text", nil},
		{"**bold** and *it*", "bold and it", []richtext.Entity{{Kind: richtext.Bold, Offset: 0, Length: 4}, {Kind: richtext.Italic, Offset: 9, Length: 2}}},
		{"__b__ _i_ ~~s~~ `c`", "b i s c", []richtext.Entity{
			{Kind: richtext.Bold, Offset: 0, Length: 1},
			{Kind: richtext.Italic, Offset: 2, Length: 1},
			{Kind: richtext.Strike, Offset: 4, Length: 1},
			{Kind: richtext.Code, Offset: 6, Length: 1},
		}},
		{"see [the docs](https://example.com/a)", "see the docs", []richtext.Entity{{Kind: richtext.Link, Offset: 4, Length: 8, URL: "https://example.com/a"}}},
		{"a ```\nb``` c", "a ```\nb``` c", nil},
		{"x\n```go\nfmt.Println()\n```\ny", "x\nfmt.Println()\ny", []richtext.Entity{{Kind: richtext.Pre, Offset: 2, Length: 13}}},
		{"snake_case_name and 2*3*4", "snake_case_name and 2*3*4", nil},
		{"**unclosed and *also", "**unclosed and *also", nil},
		{`\*not italic\*`, `*not italic*`, nil},
		{"[bad](javascript:alert(1))", "[bad](javascript:alert(1))", nil},
		{"😀 **é**", "😀 é", []richtext.Entity{{Kind: richtext.Bold, Offset: 3, Length: 1}}},
		{"** padded **", "** padded **", nil},
	} {
		text, ents := fromMarkdown(c.in)
		require.Equal(t, c.text, text, c.in)
		require.Equal(t, c.ents, ents, c.in)
		require.NoError(t, richtext.Check(text, ents), c.in)
	}
}
