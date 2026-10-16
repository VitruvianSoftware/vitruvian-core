// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package login

import (
	"fmt"
	"net/url"
	"regexp"
	"slices"
	"strings"

	"maunium.net/go/mautrix/bridgev2"
)

// MaybeURLDecodeCookie URL-decodes a value copied from the browser's developer tools, which shows cookie values
// percent-encoded, when the field is a cookie. The bridge's own cookie command does exactly this
// (bridgev2/commands/login.go) and connectors expect the decoded form. Path, not query, unescaping: a literal
// '+' is kept. A value that isn't valid percent-encoding is kept as given.
func MaybeURLDecodeCookie(val string, f CookieField) string {
	isCookie := slices.ContainsFunc(f.Sources, func(src CookieSource) bool {
		return src.Type == SourceCookie
	})
	if !isCookie {
		return val
	}
	decoded, err := url.PathUnescape(val)
	if err != nil {
		return val
	}
	return decoded
}

// cookieMatches checks a decoded value against the field's Pattern, if it has one. A pattern that doesn't
// compile can't be checked here, so the value goes to the connector, which checks what it gets.
func cookieMatches(f CookieField, val string) bool {
	if f.Pattern == "" {
		return true
	}
	re, err := regexp.Compile(f.Pattern)
	return err != nil || re.MatchString(val)
}

// CheckCookie applies a cookie field's rules to a value as the person gave it (still percent-encoded if it was
// copied from the developer tools) and returns the decoded value that Submit will send on. The error never
// contains the value.
func CheckCookie(f CookieField, raw string) (string, error) {
	v := MaybeURLDecodeCookie(raw, f)
	if !cookieMatches(f, v) {
		return "", fmt.Errorf("the value for %s isn't in the form the network expects", f.ID)
	}
	return v, nil
}

// checkCookies decodes and checks the values for a cookies step. A blank value is no value: a required field
// that has none is refused, an optional one is left out. Keys that aren't fields are dropped.
func checkCookies(fields []bridgev2.LoginCookieField, values map[string]string) (map[string]string, error) {
	out := map[string]string{}
	var missing []string
	for _, bf := range fields {
		f := toCookieField(bf)
		raw := values[f.ID]
		if raw == "" {
			if f.Required {
				missing = append(missing, f.ID)
			}
			continue
		}
		v, err := CheckCookie(f, raw)
		if err != nil {
			return nil, badValue(err)
		}
		out[f.ID] = v
	}
	if len(missing) > 0 {
		return nil, badValue(fmt.Errorf("no value for the required %s", strings.Join(missing, ", ")))
	}
	return out, nil
}

// badValue marks err as a value the person can fix and try again.
func badValue(err error) error { return fmt.Errorf("%w: %w", ErrBadValue, err) }
