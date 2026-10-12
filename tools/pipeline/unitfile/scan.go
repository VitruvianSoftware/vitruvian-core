// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package unitfile

import (
	"fmt"
	"strconv"
	"strings"
)

// A small scanner for the part of Starlark a BUILD file uses: enough to find
// where a call starts and ends and to read literal values out of it. It is
// not a Starlark parser -- nothing is evaluated, and anything that is not a
// literal comes back as "not a literal" for the caller to refuse.
//
// It is hand-written because the planner is built on the critical path of
// every pull request with a plain `go build` (#2465), so it stays
// standard-library only.

type tokenKind int

const (
	tokIdent tokenKind = iota
	tokString
	tokNumber
	tokPunct
)

type token struct {
	kind tokenKind
	// text is the identifier, the digits, the punctuation, or -- for a
	// string -- its value with the quotes gone and the escapes resolved.
	text string
	line int
}

func (t token) is(punct string) bool { return t.kind == tokPunct && t.text == punct }

func isIdentStart(c byte) bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

func isDigit(c byte) bool { return c >= '0' && c <= '9' }

// tokenize splits src into tokens. Comments and whitespace are dropped, so
// nothing inside a comment can be mistaken for code; a string is one token,
// so nothing inside a string can either. On an error it also returns the
// tokens read up to it, so the caller can say which call it was in.
func tokenize(src string) ([]token, error) {
	var toks []token
	line := 1
	for i := 0; i < len(src); {
		c := src[i]
		switch {
		case c == '\n':
			line++
			i++
		case c == ' ' || c == '\t' || c == '\r':
			i++
		case c == '\\' && i+1 < len(src) && src[i+1] == '\n':
			line++
			i += 2
		case c == '#':
			for i < len(src) && src[i] != '\n' {
				i++
			}
		case c == '"' || c == '\'':
			val, n, lines, err := scanString(src[i:], false)
			if err != nil {
				return toks, fmt.Errorf("line %d: %w", line, err)
			}
			toks = append(toks, token{tokString, val, line})
			line += lines
			i += n
		case isIdentStart(c):
			j := i
			for j < len(src) && (isIdentStart(src[j]) || isDigit(src[j])) {
				j++
			}
			word := src[i:j]
			// r"..." and b"..." are strings with a prefix, not a name
			// followed by a string.
			if j < len(src) && (src[j] == '"' || src[j] == '\'') && isStringPrefix(word) {
				val, n, lines, err := scanString(src[j:], strings.ContainsAny(word, "rR"))
				if err != nil {
					return nil, fmt.Errorf("line %d: %w", line, err)
				}
				toks = append(toks, token{tokString, val, line})
				line += lines
				i = j + n
				continue
			}
			toks = append(toks, token{tokIdent, word, line})
			i = j
		case isDigit(c):
			j := i
			for j < len(src) && (isDigit(src[j]) || isIdentStart(src[j]) || src[j] == '.') {
				j++
			}
			toks = append(toks, token{tokNumber, src[i:j], line})
			i = j
		default:
			// "==", "!=", "<=", ">=", "+=" and friends are one token, so
			// that a lone "=" always means a keyword argument.
			if i+1 < len(src) && src[i+1] == '=' && strings.IndexByte("=!<>+-*/%|&^", c) >= 0 {
				toks = append(toks, token{tokPunct, src[i : i+2], line})
				i += 2
				continue
			}
			toks = append(toks, token{tokPunct, string(c), line})
			i++
		}
	}
	return toks, nil
}

func isStringPrefix(word string) bool {
	switch strings.ToLower(word) {
	case "r", "b", "rb", "br":
		return true
	}
	return false
}

// scanString reads the string literal at the start of s: single or double
// quoted, or triple quoted. It returns the value, the bytes consumed and the
// newlines crossed.
func scanString(s string, raw bool) (val string, n, lines int, err error) {
	quote := s[0]
	triple := len(s) >= 3 && s[1] == quote && s[2] == quote
	i := 1
	if triple {
		i = 3
	}
	var b strings.Builder
	for i < len(s) {
		c := s[i]
		switch {
		case c == '\\' && i+1 < len(s):
			next := s[i+1]
			if next == '\n' {
				lines++
			}
			if raw {
				// A raw string keeps the backslash; it still stops the
				// quote after it from ending the string.
				b.WriteByte(c)
				b.WriteByte(next)
				i += 2
				continue
			}
			i += 2
			switch next {
			case 'n':
				b.WriteByte('\n')
			case 't':
				b.WriteByte('\t')
			case 'r':
				b.WriteByte('\r')
			case '\\', '\'', '"':
				b.WriteByte(next)
			case '\n':
				// line continuation inside a string
			default:
				// Anything rarer is kept as written.
				b.WriteByte('\\')
				b.WriteByte(next)
			}
		case c == quote && !triple:
			return b.String(), i + 1, lines, nil
		case c == quote && triple && strings.HasPrefix(s[i:], s[:3]):
			return b.String(), i + 3, lines, nil
		case c == '\n' && !triple:
			return "", 0, 0, fmt.Errorf("a string starting %s is not closed before the end of the line", clip(s))
		default:
			if c == '\n' {
				lines++
			}
			b.WriteByte(c)
			i++
		}
	}
	return "", 0, 0, fmt.Errorf("a string starting %s is never closed", clip(s))
}

func clip(s string) string {
	if nl := strings.IndexByte(s, '\n'); nl >= 0 {
		s = s[:nl]
	}
	if len(s) > 30 {
		s = s[:30] + "..."
	}
	return s
}

var closerOf = map[string]string{"(": ")", "[": "]", "{": "}"}

func isCloser(t token) bool { return t.is(")") || t.is("]") || t.is("}") }

// matchBracket returns the index of the bracket that closes toks[open],
// counting all three kinds, and refuses a mismatch such as "[ ... )".
func matchBracket(toks []token, open int) (int, error) {
	var stack []token
	for i := open; i < len(toks); i++ {
		t := toks[i]
		if t.kind != tokPunct {
			continue
		}
		if _, ok := closerOf[t.text]; ok {
			stack = append(stack, t)
			continue
		}
		if !isCloser(t) {
			continue
		}
		if len(stack) == 0 {
			return 0, fmt.Errorf("line %d: %q closes nothing", t.line, t.text)
		}
		top := stack[len(stack)-1]
		if closerOf[top.text] != t.text {
			return 0, fmt.Errorf("line %d: %q closes the %q opened on line %d", t.line, t.text, top.text, top.line)
		}
		stack = stack[:len(stack)-1]
		if len(stack) == 0 {
			return i, nil
		}
	}
	return 0, fmt.Errorf("the %q opened on line %d is never closed", toks[open].text, toks[open].line)
}

// splitTopLevel cuts toks at each separator that is not inside brackets.
// A trailing separator does not make an empty last piece. The brackets in
// toks are already known to balance.
func splitTopLevel(toks []token, sep string) [][]token {
	var parts [][]token
	depth, start := 0, 0
	for i, t := range toks {
		if t.kind != tokPunct {
			continue
		}
		switch {
		case closerOf[t.text] != "":
			depth++
		case isCloser(t):
			depth--
		case depth == 0 && t.text == sep:
			parts = append(parts, toks[start:i])
			start = i + 1
		}
	}
	if start < len(toks) {
		parts = append(parts, toks[start:])
	}
	return parts
}

type valueKind int

const (
	// notLiteral is anything the scanner will not read: a name, a call such
	// as glob() or select(), a concatenation, a comprehension.
	notLiteral valueKind = iota
	stringValue
	intValue
	boolValue
	listValue
	dictValue
)

type value struct {
	kind  valueKind
	str   string
	num   int
	truth bool
	list  []value
	// dict keeps the pairs in the order written.
	dict [][2]value
}

// readValue reads the literal that toks spell out, or says it is not one.
func readValue(toks []token) value {
	if len(toks) == 0 {
		return value{}
	}
	if len(toks) == 1 {
		t := toks[0]
		switch {
		case t.kind == tokString:
			return value{kind: stringValue, str: t.text}
		case t.kind == tokNumber:
			if n, err := strconv.Atoi(t.text); err == nil {
				return value{kind: intValue, num: n}
			}
		case t.kind == tokIdent && (t.text == "True" || t.text == "False"):
			return value{kind: boolValue, truth: t.text == "True"}
		}
		return value{}
	}

	first, last := toks[0], toks[len(toks)-1]
	if !first.is("[") && !first.is("{") {
		return value{}
	}
	// "[a] + [b]" starts and ends with the right brackets too, so the first
	// bracket has to be the one the last closes.
	if end, err := matchBracket(toks, 0); err != nil || end != len(toks)-1 {
		return value{}
	}
	inner := toks[1 : len(toks)-1]
	switch {
	case first.is("[") && last.is("]"):
		v := value{kind: listValue}
		for _, part := range splitTopLevel(inner, ",") {
			v.list = append(v.list, readValue(part))
		}
		return v
	case first.is("{") && last.is("}"):
		v := value{kind: dictValue}
		for _, part := range splitTopLevel(inner, ",") {
			kv := splitTopLevel(part, ":")
			if len(kv) != 2 {
				return value{}
			}
			v.dict = append(v.dict, [2]value{readValue(kv[0]), readValue(kv[1])})
		}
		return v
	}
	return value{}
}

// call is one call to a function, with its keyword arguments as written.
type call struct {
	line int
	args map[string]value
}

// findCalls returns every call to fn in src. A `def fn(` and a method call
// `x.fn(` are not calls to fn; neither is the name in a string or a comment.
func findCalls(src, fn string) ([]call, error) {
	toks, err := tokenize(src)
	if err != nil {
		// If the text stopped making sense inside a call to fn, name it.
		for i := len(toks) - 2; i >= 0; i-- {
			if toks[i].kind != tokIdent || toks[i].text != fn || !toks[i+1].is("(") {
				continue
			}
			if _, open := matchBracket(toks, i+1); open != nil {
				if name := nameIn(toks[i+2:]); name != "" {
					return nil, fmt.Errorf("%s(name = %q), which starts on line %d: %w", fn, name, toks[i].line, err)
				}
				return nil, fmt.Errorf("%s(...), which starts on line %d: %w", fn, toks[i].line, err)
			}
			break
		}
		return nil, err
	}
	var calls []call
	for i := 0; i+1 < len(toks); i++ {
		if toks[i].kind != tokIdent || toks[i].text != fn || !toks[i+1].is("(") {
			continue
		}
		if i > 0 && (toks[i-1].is(".") || (toks[i-1].kind == tokIdent && toks[i-1].text == "def")) {
			continue
		}
		c := call{line: toks[i].line, args: map[string]value{}}
		end, err := matchBracket(toks, i+1)
		if err != nil {
			// The name, if it can be made out, is worth more in the
			// message than the line number alone.
			if name := nameIn(toks[i+2:]); name != "" {
				return nil, fmt.Errorf("line %d: %s(name = %q): %w", c.line, fn, name, err)
			}
			return nil, fmt.Errorf("line %d: %s(...): %w", c.line, fn, err)
		}
		for _, arg := range splitTopLevel(toks[i+2:end], ",") {
			if len(arg) < 3 || arg[0].kind != tokIdent || !arg[1].is("=") {
				return nil, fmt.Errorf("line %d: %s(...): every argument must be written name = value; found one that is not (positional, * or **)", arg[0].line, fn)
			}
			c.args[arg[0].text] = readValue(arg[2:])
		}
		calls = append(calls, c)
		i = end
	}
	return calls, nil
}

// nameIn finds `name = "..."` in the tokens of a call whose end is unknown.
func nameIn(toks []token) string {
	for i := 0; i+2 < len(toks) && i < 200; i++ {
		if toks[i].kind == tokIdent && toks[i].text == "name" && toks[i+1].is("=") && toks[i+2].kind == tokString {
			return toks[i+2].text
		}
	}
	return ""
}
