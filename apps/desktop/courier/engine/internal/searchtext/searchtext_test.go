// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package searchtext

import (
	"bufio"
	"context"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
	"unicode"
	"unicode/utf16"
	"unicode/utf8"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mau.fi/util/dbutil"

	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
)

// The tokenizer every search table uses (global constraints, "How the index matches").
const tokenizer = `unicode61 remove_diacritics 2 categories 'L* N* Co M*'`

func TestParseWordsPhrasesAndPrefix(t *testing.T) {
	for _, tc := range []struct {
		q    string
		want []Term
	}{
		{"see you", []Term{{Text: "see"}, {Text: "you", Prefix: true}}},
		{"see you ", []Term{{Text: "see"}, {Text: "you"}}},
		{`"see you" soon`, []Term{{Text: "see you", Phrase: true}, {Text: "soon", Prefix: true}}},
		{`"see you`, []Term{{Text: "see you", Phrase: true}}},
		{"e-mail", []Term{{Text: "e mail", Phrase: true}}},
		{"a", []Term{{Text: "a"}}},
		// A word that ends at a quote mark was finished, so it is not a prefix.
		{`see"`, []Term{{Text: "see"}}},
		{"Dinner", []Term{{Text: "dinner", Prefix: true}}},
	} {
		assert.Equal(t, tc.want, Parse(tc.q), "%q", tc.q)
	}
}

func TestParseNameIsAPrefixFromTheFirstLetter(t *testing.T) {
	for _, tc := range []struct {
		q    string
		want []Term
	}{
		{"a", []Term{{Text: "a", Prefix: true}}},
		{"A", []Term{{Text: "a", Prefix: true}}},
		{"a ", []Term{{Text: "a"}}},
		{`"a"`, []Term{{Text: "a", Phrase: true}}},
		{`"a`, []Term{{Text: "a", Phrase: true}}},
		{"book c", []Term{{Text: "book"}, {Text: "c", Prefix: true}}},
		{"e-m", []Term{{Text: "e m", Phrase: true}}},
		{"🥺", nil},
	} {
		assert.Equal(t, tc.want, ParseName(tc.q), "%q", tc.q)
	}
	// Messages keep the 2-letter rule.
	assert.Equal(t, []Term{{Text: "a"}}, Parse("a"))
	assert.Equal(t, `{name}: ("a"*)`, MatchAll("name", ParseName("a")))
}

func TestFTSSyntaxIsPlainText(t *testing.T) {
	for _, tc := range []struct{ q, want string }{
		{"AND", `{body}: ("and"*)`},
		{"OR", `{body}: ("or"*)`},
		{"NOT", `{body}: ("not"*)`},
		// Brackets end a word as a space does; the last word has one letter, so no prefix.
		{"NEAR(a b)", `{body}: ("near" AND "a" AND "b")`},
		{"a*", `{body}: ("a")`},
		{"col:x", `{body}: ("col x")`},
		{"^start", `{body}: ("start"*)`},
		{"(x)", `{body}: ("x")`},
		{"meet AND gre", `{body}: ("meet" AND "and" AND "gre"*)`},
	} {
		got := MatchAll("body", Parse(tc.q))
		assert.Equal(t, tc.want, got, "%q", tc.q)
		assertSafeExpr(t, tc.q, got)
	}
	assert.Equal(t, `{scope}: ("meet" OR "and" OR "gre"*)`, MatchAny("scope", Parse("meet AND gre")))
}

func TestQuoteMarksNeverUnbalanceTheExpression(t *testing.T) {
	assert.Equal(t, `{body}: ("he" AND "said" AND "hi")`, MatchAll("body", Parse(`he said "hi`)))
	for _, q := range []string{`""`, `"`, `a"b"c`, `"""`, `x"*`} {
		for _, expr := range []string{MatchAll("body", Parse(q)), MatchAny("body", Parse(q))} {
			assert.Zero(t, strings.Count(expr, `"`)%2, "%q gave %q", q, expr)
		}
	}
	assert.Nil(t, Parse(`""`))
	assert.Nil(t, Parse(`"`))
	assert.Equal(t, `{body}: ("a" AND "b" AND "c")`, MatchAll("body", Parse(`a"b"c`)))
	// A term built by hand with a quote mark in it still gives a balanced expression.
	assert.Equal(t, `{body}: ("say hi")`, MatchAll("body", []Term{{Text: `say "hi"`}}))
}

func TestMatchIsEmptyWithoutTerms(t *testing.T) {
	assert.Equal(t, "", MatchAll("body", nil))
	assert.Equal(t, "", MatchAny("body", nil))
	// Nothing searchable in a hand-built term either.
	assert.Equal(t, "", MatchAll("body", []Term{{Text: "🎉"}, {Text: ""}}))
}

func TestFoldsAccentsCaseAndWidth(t *testing.T) {
	assert.Equal(t, []string{"jose", "cafe", "hello"}, Words(Normalize("José CAFÉ Ｈｅｌｌｏ")))
	// A decomposed accent folds the same way as a precomposed one.
	assert.Equal(t, []string{"jose"}, Words(Normalize("José")))
}

func TestScriptsWithoutSpacesMatchInsideWords(t *testing.T) {
	assert.Equal(t, "東 京 タ ワ ー", Normalize("東京タワー"))
	assert.Equal(t, "see 東 京 now", Normalize("see 東京 now"))
	assert.Equal(t, "a 東 b", Normalize("a東b"))
	assert.Equal(t, []Term{{Text: "東 京", Phrase: true}}, Parse("東京"))
	cat := Parse("猫")
	require.Len(t, cat, 1)
	assert.Equal(t, 2, Letters(cat))
	assert.Equal(t, 1, Letters(Parse("a")))
	assert.Equal(t, 6, Letters(Parse("ab 東京")))
}

func TestCombiningMarksStayInWords(t *testing.T) {
	words := Words("नमस्ते दोस्त")
	require.Len(t, words, 2)
	// The marks are kept: the index keeps them too, so a query without them would not find the word.
	assert.Equal(t, []string{"नमस्ते", "दोस्त"}, words)
}

func TestEmojiAndPunctuationOnlyIsNothing(t *testing.T) {
	// ❤️ carries a variation selector and #️⃣ a keycap, both marks that would otherwise read as a word.
	for _, q := range []string{"🎉🎉", "?!…", "", "   ", "\xff", "❤️", "👍🏽", "#️⃣", "🏳️‍🌈"} {
		assert.Nil(t, Parse(q), "%q", q)
	}
}

func TestLongQueriesAreCut(t *testing.T) {
	long := Parse(strings.Repeat("a", 600))
	require.Len(t, long, 1)
	assert.Equal(t, MaxQueryRunes, utf8.RuneCountInString(long[0].Text))

	var words []string
	for i := 1; i <= 20; i++ {
		words = append(words, "w"+strconv.Itoa(i))
	}
	terms := Parse(strings.Join(words, " "))
	require.Len(t, terms, MaxTerms)
	assert.Equal(t, "w16", terms[MaxTerms-1].Text)
	// The 16th word was not the last one typed, so it is not a prefix.
	assert.False(t, terms[MaxTerms-1].Prefix)
}

// utf16Of returns s[start:start+length] counted in UTF-16 code units.
func utf16Of(s string, r Range) string {
	u := utf16.Encode([]rune(s))
	if r.Start < 0 || r.Length < 0 || r.Start+r.Length > len(u) {
		return "<out of range>"
	}
	return string(utf16.Decode(u[r.Start : r.Start+r.Length]))
}

func TestSnippetCentresOnTheFirstMatch(t *testing.T) {
	text := strings.Repeat("x ", 150) + "dinner" + strings.Repeat(" y", 47)
	require.Equal(t, 300, strings.Index(text, "dinner"))
	require.Equal(t, 400, utf8.RuneCountInString(text))

	snippet, ranges := Snippet(text, Parse("dinner "), 160)
	assert.True(t, strings.HasPrefix(snippet, "…"), snippet)
	assert.True(t, strings.HasSuffix(snippet, "…"), snippet)
	assert.LessOrEqual(t, utf8.RuneCountInString(snippet), 160)
	assert.Contains(t, snippet, "dinner")
	require.Len(t, ranges, 1)
	assert.Equal(t, "dinner", utf16Of(snippet, ranges[0]))
	assert.Equal(t, 6, ranges[0].Length)

	// An emoji is two UTF-16 units, so the range starts one unit later than the rune count says.
	snippet, ranges = Snippet("🎉 see you at dinner", Parse("dinner"), 160)
	assert.Equal(t, "🎉 see you at dinner", snippet)
	require.Len(t, ranges, 1)
	assert.Equal(t, Range{Start: 14, Length: 6}, ranges[0])
	assert.Equal(t, "dinner", utf16Of(snippet, ranges[0]))

	// The person typed "jose"; the text says "José".
	snippet, ranges = Snippet("Ask José about it", Parse("jose "), 160)
	require.Len(t, ranges, 1)
	assert.Equal(t, "José", utf16Of(snippet, ranges[0]))

	// A decomposed accent is a unit of its own: e and U+0301 are 2 of the 5 units of "José".
	snippet, ranges = Snippet("Ask Jose\u0301 about it", Parse("jose "), 160)
	assert.Equal(t, []Range{{Start: 4, Length: 5}}, ranges)
	assert.Equal(t, "Jose\u0301", utf16Of(snippet, ranges[0]))

	// 𠮷 (U+20BB7) is outside the BMP, so it is 2 units and everything after it moves by one more.
	snippet, ranges = Snippet("go to 𠮷野家 today", Parse("𠮷野 today"), 160)
	assert.Equal(t, []Range{{Start: 6, Length: 3}, {Start: 11, Length: 5}}, ranges)
	assert.Equal(t, "𠮷野", utf16Of(snippet, ranges[0]))
	assert.Equal(t, "today", utf16Of(snippet, ranges[1]))
}

func TestSnippetHighlightsEveryMatchedWordAndPhrase(t *testing.T) {
	text := "Dinners at 東京タワー? My e-mail said dinner."
	snippet, ranges := Snippet(text, Parse(`京タ e-mail dinner`), 160)
	assert.Equal(t, text, snippet)
	var got []string
	for _, r := range ranges {
		got = append(got, utf16Of(snippet, r))
	}
	// "dinner" is a prefix (the last word, still being typed), so "Dinners" lights up too.
	assert.Equal(t, []string{"Dinners", "京タ", "e-mail", "dinner"}, got)
}

func TestSnippetWithoutAMatchIsTheStart(t *testing.T) {
	text := strings.Repeat("word ", 100)
	snippet, ranges := Snippet(text, Parse("absent"), 40)
	assert.Empty(t, ranges)
	assert.True(t, strings.HasPrefix(snippet, "word"), snippet)
	assert.True(t, strings.HasSuffix(snippet, "…"), snippet)
	assert.LessOrEqual(t, utf8.RuneCountInString(snippet), 40)

	// However small the limit, the snippet keeps to it (3 at least: a character and both cuts).
	for limit := 1; limit <= 12; limit++ {
		snippet, _ := Snippet(text, Parse("word"), limit)
		assert.LessOrEqual(t, utf8.RuneCountInString(snippet), max(limit, 3), "limit %d: %q", limit, snippet)
	}

	snippet, ranges = Snippet("short text", nil, 40)
	assert.Equal(t, "short text", snippet)
	assert.Empty(t, ranges)
}

// The fold Words applies must be the one the index applies, or a query built from Words would miss the text
// it should find. This asks the real tokenizer.
func TestWordsMirrorTheTokenizer(t *testing.T) {
	db := openFTS(t)
	ctx := context.Background()
	_, err := db.Exec(ctx, `CREATE VIRTUAL TABLE v USING fts5vocab(t, 'instance')`)
	require.NoError(t, err)

	var samples []string
	add := func(lo, hi rune, prefix, suffix string) {
		for r := lo; r <= hi; r++ {
			// Skip code points with no character assigned: SQLite's tables count those as letters.
			if !unicode.In(r, unicode.L, unicode.M, unicode.N, unicode.P, unicode.S, unicode.Z,
				unicode.Cc, unicode.Cf, unicode.Co) {
				continue
			}
			samples = append(samples, prefix+string(r)+suffix)
		}
	}
	add(0x21, 0x7e, "", "")
	add(0xa0, 0x1df, "", "")  // Latin-1 and Latin Extended-A/B ...
	add(0x1e2, 0x24f, "", "") // ... except U+01E0/U+01E1, which carry two marks the tokenizer keeps.
	add(0x300, 0x36f, "x", "y")
	add(0x386, 0x3ce, "", "")
	add(0x400, 0x4ff, "", "")
	add(0x900, 0x97f, "", "")
	add(0xe01, 0xe5b, "", "")
	add(0x1e00, 0x1eff, "", "")
	add(0xff01, 0xff5e, "", "")
	samples = append(
		samples,
		"José CAFÉ Ｈｅｌｌｏ", "José", "नमस्ते दोस्त", "สวัสดีครับ", "東京タワー", "Привет мир", "Ελληνικά ΣΟΦΟΣ",
		"e-mail o'clock 3.14", "👍🏽 ok", "a‍b", " ́ ", "x", "ﬁne ①② ㍿", "İstanbul", "Straße ẞ",
	)

	for _, s := range samples {
		n := Normalize(s)
		_, err := db.Exec(ctx, "DELETE FROM t")
		require.NoError(t, err)
		_, err = db.Exec(ctx, "INSERT INTO t(rowid, body) VALUES (1, ?)", n)
		require.NoError(t, err)
		rows, err := db.Query(ctx, "SELECT term FROM v WHERE term IS NOT NULL ORDER BY offset")
		require.NoError(t, err)
		var index []string
		for rows.Next() {
			var w string
			require.NoError(t, rows.Scan(&w))
			index = append(index, w)
		}
		require.NoError(t, rows.Err())
		require.NoError(t, rows.Close())
		assert.Equal(t, index, Words(n), "%q (%U)", s, []rune(s))
	}
}

// Through the real index: what a person types finds the text they mean (Review Focus 3).
func TestQueriesFindTheirTextInTheIndex(t *testing.T) {
	db := openFTS(t)
	ctx := context.Background()
	for _, tc := range []struct {
		text, q string
		found   bool
	}{
		{"Ask José", "jose", true},
		{"un café noir", "CAFE ", true},
		{"hello there", "Ｈｅｌｌｏ", true},
		{"東京タワーに行く", "東京", true},
		{"東京タワーに行く", "京タ", true},
		{"東京タワーに行く", "京都", false},
		{"नमस्ते दोस्त", "नमस्ते", true},
		{"नमस्ते दोस्त", "नम", true}, // a prefix of a word with marks
		{"สวัสดีครับ", "วัส", true},
		{"send me an e-mail", "e-mail", true},
		{"see you soon", `"see you"`, true},
		{"you see", `"see you"`, false},
		{"dinner tonight", "din", true},
		{"dinners tonight", "dinner ", false},
		{"o'clock", "o'clock", true},
		// SQLite's tables are older than this emoji and would count it as a letter of "thanks🥺".
		{"thanks🥺 so much", "thanks ", true},
		{"great 👍🏽 work", `"great work"`, true},
		{"I ❤️ it", "i it", true},
		// U+1FAE9 is newer than Go's Unicode tables, and SQLite counts code points it doesn't know as letters.
		{"thanks\U0001FAE9 so much", "thanks ", true},
	} {
		_, err := db.Exec(ctx, "DELETE FROM t")
		require.NoError(t, err)
		_, err = db.Exec(ctx, "INSERT INTO t(rowid, body, scope) VALUES (1, ?, '')", Normalize(tc.text))
		require.NoError(t, err)
		expr := MatchAll("body", Parse(tc.q))
		require.NotEmpty(t, expr, tc.q)
		var n int
		require.NoError(t, db.QueryRow(ctx, "SELECT count(*) FROM t WHERE t MATCH ?", expr).Scan(&n), expr)
		assert.Equal(t, tc.found, n == 1, "%q in %q (%s)", tc.q, tc.text, expr)
	}
}

// Review Focus 2: whatever a person types, the expression is plain quoted words, and the real FTS5 accepts it.
func TestAnyTextIsASafeQuery(t *testing.T) {
	corpus := readCorpus(t)
	require.Greater(t, len(corpus), 100)
	db := openFTS(t)
	for _, q := range corpus {
		checkQuery(t, db, q)
	}
}

func readCorpus(t testing.TB) []string {
	t.Helper()
	f, err := os.Open(filepath.Join("testdata", "queries.txt"))
	require.NoError(t, err)
	defer f.Close()
	var out []string
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64*1024), 1<<20)
	for sc.Scan() {
		q, err := strconv.Unquote(sc.Text())
		require.NoError(t, err, "testdata/queries.txt: %s", sc.Text())
		out = append(out, q)
	}
	require.NoError(t, sc.Err())
	return out
}

func openFTS(t testing.TB) *dbutil.Database {
	t.Helper()
	db, err := sqlite.Open(filepath.Join(t.TempDir(), "search.db"))
	require.NoError(t, err)
	t.Cleanup(func() { db.Close() })
	_, err = db.Exec(context.Background(), `CREATE VIRTUAL TABLE t USING fts5(body, scope, tokenize="`+tokenizer+`")`)
	require.NoError(t, err)
	_, err = db.Exec(context.Background(), `INSERT INTO t(rowid, body, scope) VALUES (1, 'see you at dinner', 'inbox')`)
	require.NoError(t, err)
	return db
}

// checkQuery parses q, checks the expressions it makes by inspection, runs them on the real FTS5, and checks
// that a snippet of q is well formed.
func checkQuery(t *testing.T, db *dbutil.Database, q string) {
	t.Helper()
	terms := Parse(q)
	assert.LessOrEqual(t, len(terms), MaxTerms, "%q", q)
	for i, term := range terms {
		assert.NotEmpty(t, term.Text, "%q", q)
		assert.False(t, term.Prefix && term.Phrase, "%q: a phrase is never a prefix", q)
		assert.False(t, term.Prefix && i != len(terms)-1, "%q: only the last term is a prefix", q)
		assert.True(t, utf8.ValidString(term.Text), "%q", q)
	}
	exprs := []string{MatchAll("body", terms), MatchAny("scope", terms)}
	// A hand-built term from the same text is safe too.
	exprs = append(exprs, MatchAll("body", []Term{{Text: q, Prefix: true}}))
	for _, expr := range exprs {
		assertSafeExpr(t, q, expr)
		if expr == "" {
			continue
		}
		var n int
		err := db.QueryRow(context.Background(), "SELECT count(*) FROM t WHERE t MATCH ?", expr).Scan(&n)
		assert.NoError(t, err, "%q gave %q", q, expr)
	}

	snippet, ranges := Snippet(q, terms, 80)
	assert.True(t, utf8.ValidString(snippet), "%q", q)
	assert.LessOrEqual(t, utf8.RuneCountInString(snippet), 80, "%q", q)
	units := len(utf16.Encode([]rune(snippet)))
	end := 0
	for _, r := range ranges {
		assert.Positive(t, r.Length, "%q", q)
		assert.GreaterOrEqual(t, r.Start, end, "%q: ranges are in order and do not overlap", q)
		end = r.Start + r.Length
		assert.LessOrEqual(t, end, units, "%q", q)
	}
}

var (
	quoted   = regexp.MustCompile(`"(?:[^"]|"")*"`)
	skeleton = regexp.MustCompile(`^\{(?:body|scope)\}: \(Q\*?(?: (?:AND|OR) Q\*?)*\)$`)
)

// assertSafeExpr is Review Focus 2 by inspection: "" or an expression with an even number of quote marks, no `*`
// except right after a closing quote, no `:` except after {body} or {scope}, and nothing outside quotes but the
// column filter, brackets and the operator.
func assertSafeExpr(t *testing.T, q, expr string) {
	t.Helper()
	if expr == "" {
		return
	}
	assert.Zero(t, strings.Count(expr, `"`)%2, "%q gave %q", q, expr)
	outside := quoted.ReplaceAllString(expr, "Q")
	assert.Regexp(t, skeleton, outside, "%q gave %q", q, expr)
	for i, c := range outside {
		if c == '*' {
			assert.True(t, i > 0 && outside[i-1] == 'Q', "%q gave %q: bare *", q, expr)
		}
		if c == ':' {
			assert.True(t, strings.HasSuffix(outside[:i], "{body}") || strings.HasSuffix(outside[:i], "{scope}"),
				"%q gave %q: bare :", q, expr)
		}
	}
}
