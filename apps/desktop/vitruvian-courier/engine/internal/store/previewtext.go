// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"html"
	"regexp"
	"strings"
)

// A chat row's preview is one plain line. A bridge hands over the message as its network wrote it: Markdown from
// Matrix and Beeper clients, mrkdwn and HTML entities from Slack. plainPreview takes the formatting marks out so
// every client shows the words, not the asterisks.

var (
	// <@U123|name>, <@U123>, <#C123|name>, <!here>, <https://x|label>, <https://x>, <mailto:a@b|label>.
	slackTokenRE = regexp.MustCompile(`<([@#!]|https?://|mailto:)([^<>|\s]*)(?:\|([^<>]*))?>`)
	mdLinkRE     = regexp.MustCompile(`\[([^\]\n]+)\]\((?:https?://|mailto:)[^)\s]*\)`)
	// Double marks need no word boundary: **bold**, __bold__, ~~strike~~.
	boldStarRE  = regexp.MustCompile(`\*\*(\S(?:.*?\S)?)\*\*`)
	strikeRE    = regexp.MustCompile(`~~(\S(?:.*?\S)?)~~`)
	boldUnderRE = regexp.MustCompile(`(^|[^\w_])__(\S(?:.*?\S)?)__($|[^\w_])`)
	// Single marks only wrap a word or phrase that starts and ends at a word edge, so snake_case, 2 * 3 and
	// file_name_v2 are left alone.
	italicStarRE  = regexp.MustCompile(`(^|[^\w*])\*(\S(?:[^*\n]*?\S)?)\*($|[^\w*])`)
	italicUnderRE = regexp.MustCompile(`(^|[^\w_])_(\S(?:[^_\n]*?\S)?)_($|[^\w_])`)
	strikeOneRE   = regexp.MustCompile(`(^|[^\w~])~(\S(?:[^~\n]*?\S)?)~($|[^\w~])`)
	fenceLineRE   = regexp.MustCompile("^\\s*```[\\w+-]*\\s*$")
	quoteMarkRE   = regexp.MustCompile(`^\s*(?:>\s?)+`)
)

// plainPreview is body as one line of plain text: Slack tokens turned into their label, HTML entities decoded,
// quote markers, code fences and backticks removed, bold, italic and strike marks removed, and every run of white
// space (newlines too) one space. Emoji and underscores inside words stay.
func plainPreview(body string) string {
	if body == "" {
		return ""
	}
	body = slackTokenRE.ReplaceAllStringFunc(body, func(tok string) string {
		m := slackTokenRE.FindStringSubmatch(tok)
		kind, target, label := m[1], m[2], m[3]
		switch kind {
		case "@":
			return "@" + firstNonEmpty(label, target)
		case "#":
			return "#" + firstNonEmpty(label, target)
		case "!":
			// <!here>, <!channel>, <!subteam^S1|@team>, <!date^…|fallback>
			if label != "" {
				return label
			}
			return "@" + strings.SplitN(target, "^", 2)[0]
		}
		return firstNonEmpty(label, kind+target)
	})
	body = html.UnescapeString(body)
	lines := strings.Split(strings.ReplaceAll(body, "\r\n", "\n"), "\n")
	kept := lines[:0]
	for _, l := range lines {
		if fenceLineRE.MatchString(l) {
			continue
		}
		kept = append(kept, quoteMarkRE.ReplaceAllString(l, ""))
	}
	s := strings.Join(strings.Fields(strings.Join(kept, " ")), " ")
	s = mdLinkRE.ReplaceAllString(s, "$1")
	s = strings.ReplaceAll(s, "`", "")
	s = boldStarRE.ReplaceAllString(s, "$1")
	s = strikeRE.ReplaceAllString(s, "$1")
	// A boundary character is shared by neighbours ("_a_ _b_"), so a second pass takes the ones the first skipped.
	for range 2 {
		s = boldUnderRE.ReplaceAllString(s, "$1$2$3")
		s = italicStarRE.ReplaceAllString(s, "$1$2$3")
		s = italicUnderRE.ReplaceAllString(s, "$1$2$3")
		s = strikeOneRE.ReplaceAllString(s, "$1$2$3")
	}
	return strings.TrimSpace(s)
}

func firstNonEmpty(a, b string) string {
	if a != "" {
		return a
	}
	return b
}

// isBareURL reports whether s is nothing but a web address.
func isBareURL(s string) bool {
	s = strings.TrimSpace(s)
	if s == "" || strings.ContainsAny(s, " \t\r\n") {
		return false
	}
	l := strings.ToLower(s)
	return strings.HasPrefix(l, "http://") || strings.HasPrefix(l, "https://") || strings.HasPrefix(l, "www.")
}

// looksLikeFileName reports whether s is a single token with a short extension ("IMG_2041.jpg", "report.pdf"): what
// a bridge puts in a media message's body when the person wrote no caption.
func looksLikeFileName(s string) bool {
	s = strings.TrimSpace(s)
	if s == "" || strings.ContainsAny(s, " \t\r\n/") {
		return false
	}
	i := strings.LastIndexByte(s, '.')
	ext := len(s) - i - 1
	return i > 0 && ext >= 1 && ext <= 5
}

// isRealCaption reports whether a media message's body is something the person wrote: not empty, not a bare URL,
// and not the file's own name (the body or filename field).
func isRealCaption(body, filename string) bool {
	body = strings.TrimSpace(body)
	if body == "" || isBareURL(body) || body == strings.TrimSpace(filename) {
		return false
	}
	return !looksLikeFileName(body)
}
