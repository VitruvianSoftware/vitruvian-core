// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"github.com/mdp/qrterminal/v3"
	"go.mau.fi/util/curl"
	"golang.org/x/term"
	"maunium.net/go/mautrix/bridgev2"
)

// prompter asks the person at the keyboard for what a login step needs.
type prompter interface {
	// Line reads a visible answer.
	Line(label string) (string, error)
	// Secret reads an answer that must never be shown: a password, token or cookie value.
	Secret(label string) (string, error)
	// Confirm asks a yes/no question. Anything but yes is no.
	Confirm(question string) (bool, error)
}

// maxInputTries is how many times a field is asked for before the login is given up.
const maxInputTries = 3

// useTheApp is the way out for a sign-in step this CLI can't do.
const useTheApp = "use the Courier app for this sign-in (milestone 3)"

// walkLogin walks a login to completion: it draws QR codes, shows emoji and codes, asks for typed input and
// pasted cookies, and waits for the phone in between. On every path except a completed login it cancels the
// process, so no half-open pairing is left behind. Secret values (passwords, tokens, cookies) are read with
// Secret and are never written to out.
func walkLogin(ctx context.Context, proc bridgev2.LoginProcess, p prompter, out io.Writer) error {
	completed := false
	defer func() {
		if !completed {
			proc.Cancel()
		}
	}()
	step, err := proc.Start(ctx)
	for err == nil {
		if step == nil {
			return errors.New("the login returned no next step")
		}
		switch step.Type {
		case bridgev2.LoginStepTypeComplete:
			completed = true
			return nil
		case bridgev2.LoginStepTypeDisplayAndWait:
			showDisplay(out, step)
			waiter, ok := proc.(bridgev2.LoginProcessDisplayAndWait)
			if !ok {
				return errors.New("this login can't wait for the phone, so it can't be finished from here")
			}
			step, err = waiter.Wait(ctx)
		case bridgev2.LoginStepTypeUserInput:
			submitter, ok := proc.(bridgev2.LoginProcessUserInput)
			if !ok {
				return errors.New("this login asks for typed input but can't take it")
			}
			var input map[string]string
			if input, err = askFields(step, p, out); err != nil {
				return err
			}
			step, err = submitter.SubmitUserInput(ctx, input)
		case bridgev2.LoginStepTypeCookies:
			submitter, ok := proc.(bridgev2.LoginProcessCookies)
			if !ok {
				return errors.New("this login asks for cookies but can't take them")
			}
			var cookies map[string]string
			if cookies, err = askCookies(step, p, out); err != nil {
				return err
			}
			step, err = submitter.SubmitCookies(ctx, cookies)
		case bridgev2.LoginStepTypeWebAuthn:
			return fmt.Errorf("login step %q (id %q) needs a passkey, which this test CLI can't do — %s",
				step.Type, step.StepID, useTheApp)
		default:
			return fmt.Errorf("this test CLI can't do login step %q (id %q) — %s", step.Type, step.StepID, useTheApp)
		}
	}
	return err
}

// showDisplay prints what a display_and_wait step wants shown.
func showDisplay(out io.Writer, step *bridgev2.LoginStep) {
	if step.Instructions != "" {
		fmt.Fprintln(out, step.Instructions)
	}
	d := step.DisplayAndWaitParams
	if d == nil {
		return
	}
	switch d.Type {
	case bridgev2.LoginDisplayTypeQR:
		if step.Instructions == "" {
			fmt.Fprintln(out, "Scan this with the app on your phone:")
		}
		qrterminal.GenerateHalfBlock(d.Data, qrterminal.L, out)
	case bridgev2.LoginDisplayTypeEmoji, bridgev2.LoginDisplayTypeCode:
		fmt.Fprintf(out, "\n        %s\n\nTap/enter this on your phone. Waiting for it...\n", d.Data)
	default:
		fmt.Fprintln(out, "Waiting...")
	}
}

// secretField reports whether a typed field must be read without echo.
func secretField(t bridgev2.LoginInputFieldType) bool {
	return t == bridgev2.LoginInputFieldTypePassword || t == bridgev2.LoginInputFieldTypeToken
}

// askFields prompts for each field of a user_input step, in order.
func askFields(step *bridgev2.LoginStep, p prompter, out io.Writer) (map[string]string, error) {
	if step.Instructions != "" {
		fmt.Fprintln(out, step.Instructions)
	}
	if step.UserInputParams == nil {
		return nil, fmt.Errorf("login step %q (id %q) lists no fields to ask for", step.Type, step.StepID)
	}
	input := map[string]string{}
	for _, field := range step.UserInputParams.Fields {
		secret := secretField(field.Type)
		label := inputLabel(field)
		var value string
		for try := 1; ; try++ {
			var raw string
			var err error
			if secret {
				raw, err = p.Secret(label)
			} else {
				raw, err = p.Line(label)
			}
			if err != nil {
				return nil, err
			}
			// A secret is kept exactly as typed (spaces can be part of a password); only the line ending goes.
			if secret {
				raw = strings.TrimRight(raw, "\r\n")
			} else {
				raw = strings.TrimSpace(raw)
			}
			var verr error
			if value, verr = checkInput(field, raw); verr == nil {
				break
			}
			if try == maxInputTries {
				return nil, fmt.Errorf("%s: no valid value after %d tries", field.Name, maxInputTries)
			}
			// Never echo what was typed into a secret field, even to say why it was refused.
			if secret {
				fmt.Fprintln(out, "That wasn't accepted — try again.")
			} else {
				fmt.Fprintf(out, "That wasn't accepted (%v) — try again.\n", verr)
			}
		}
		input[field.ID] = value
	}
	return input, nil
}

// inputLabel is what a field is called when asked for: its name, then its description, then any fixed choices.
func inputLabel(f bridgev2.LoginInputDataField) string {
	label := f.Name
	if label == "" {
		label = f.ID
	}
	if f.Description != "" {
		label += " (" + f.Description + ")"
	}
	if f.Type == bridgev2.LoginInputFieldTypeSelect && len(f.Options) > 0 {
		label += " [" + strings.Join(f.Options, "/") + "]"
	}
	return label
}

// checkInput applies a field's rules to a typed value and returns the cleaned value to submit. The errors never
// contain the value.
func checkInput(f bridgev2.LoginInputDataField, value string) (string, error) {
	if value == "" {
		value = f.DefaultValue
	}
	if value == "" {
		return "", errors.New("a value is needed")
	}
	if f.Type == bridgev2.LoginInputFieldTypeSelect && len(f.Options) > 0 && !slices.Contains(f.Options, value) {
		return "", fmt.Errorf("choose one of: %s", strings.Join(f.Options, ", "))
	}
	// The same cleaning and checks the bridge's own login commands apply: phone numbers and emails are cleaned,
	// and any other field is matched against its Pattern. A Pattern that doesn't compile fails every try, as it
	// does in the bridge's commands.
	f.FillDefaultValidate()
	return f.Validate(value)
}

// maxCookieFile caps how much of a cookie file is read. A browser's "copy as cURL" is a few kilobytes.
const maxCookieFile = 1 << 20

// askCookies gets the values a cookies step needs. The person signs in in their browser, then either names a file
// holding a cURL command or a JSON object copied from the browser's developer tools, or leaves that blank and
// enters each value by hand, without echo. A file is asked for rather than a paste because macOS cuts a typed or
// pasted terminal line off at 1024 bytes (MAX_CANON), and a copied cURL command is longer than that.
//
// The bridge's own instructions ("Enter a JSON object ... or a cURL command") are not printed: they describe the
// bridge's chat command, which takes the whole paste in one message, not this CLI.
//
// Missing required values cancel the login: without them this CLI has no other way in. Nothing read from the
// file, and no value typed, is ever written to out or put in an error.
func askCookies(step *bridgev2.LoginStep, p prompter, out io.Writer) (map[string]string, error) {
	c := step.CookiesParams
	if c == nil {
		return nil, fmt.Errorf("login step %q (id %q) lists no cookies to ask for", step.Type, step.StepID)
	}
	fields := sortCookieFields(c.Fields)
	fmt.Fprintf(out, "Sign in at this address in your browser:\n  %s\n", c.URL)
	fmt.Fprintln(out, "Then, in the browser's developer tools, copy a request to that site as cURL (Network tab, right-click, "+
		"Copy as cURL), or write the values below as a JSON object keyed by these names, save it to a file, and enter "+
		"the file's path. Or leave the path blank to enter the values one at a time. These are the values needed:")
	for _, f := range fields {
		req := "optional"
		if f.Required {
			req = "required"
		}
		fmt.Fprintf(out, "  - %s (%s): %s\n", f.ID, req, sourceHints(f.Sources))
	}
	path, err := p.Line("File with the cURL command or JSON (blank to enter the values one at a time)")
	if err != nil {
		return nil, err
	}
	if path = cleanPath(path); path != "" {
		return cookiesFromFile(path, fields)
	}
	fmt.Fprintln(out, "Copy each value from the developer tools' Application or Storage tab. They are not shown as you paste them:")
	cookies := map[string]string{}
	for _, f := range fields {
		label := f.ID
		if !f.Required {
			label += " (optional — press Enter to skip)"
		}
		for try := 1; ; try++ {
			raw, err := p.Secret(label)
			if err != nil {
				return nil, err
			}
			// Kept exactly as pasted apart from the line ending.
			raw = strings.TrimRight(raw, "\r\n")
			if raw == "" {
				if f.Required {
					return nil, fmt.Errorf("no value for the required %s — %s", f.ID, useTheApp)
				}
				break
			}
			v := maybeURLDecodeCookie(raw, f)
			if cookieMatches(f, v) {
				cookies[f.ID] = v
				break
			}
			if try == maxInputTries {
				return nil, fmt.Errorf("%s: no valid value after %d tries", f.ID, maxInputTries)
			}
			// Never echo what was pasted: it is a credential.
			fmt.Fprintln(out, "That wasn't accepted — try again.")
		}
	}
	return cookies, nil
}

// sortCookieFields returns the fields required first, then by ID, so the prompts come in the same order every
// run (gmessages builds its list from a Go map). The step's own slice is left alone: a connector may share it.
func sortCookieFields(fields []bridgev2.LoginCookieField) []bridgev2.LoginCookieField {
	sorted := slices.Clone(fields)
	slices.SortStableFunc(sorted, func(a, b bridgev2.LoginCookieField) int {
		if a.Required != b.Required {
			if a.Required {
				return -1
			}
			return 1
		}
		return strings.Compare(a.ID, b.ID)
	})
	return sorted
}

// cleanPath turns what was typed for a path into the path: surrounding space and quotes go, "~/" is the home
// directory, and "\ " is a space (a file dragged into Terminal arrives that way).
func cleanPath(s string) string {
	s = strings.TrimSpace(s)
	if len(s) >= 2 && (s[0] == '\'' || s[0] == '"') && s[len(s)-1] == s[0] {
		s = s[1 : len(s)-1]
	} else {
		s = strings.ReplaceAll(s, `\ `, " ")
	}
	if rest, ok := strings.CutPrefix(s, "~/"); ok {
		if home, err := os.UserHomeDir(); err == nil {
			s = filepath.Join(home, rest)
		}
	}
	return s
}

// cookiesFromFile reads a file holding a cURL command or a JSON object and maps it onto the fields, the way
// bridgev2's own cookie command does (bridgev2/commands/login.go, cookieLoginCommandState.submit): a cURL command
// is parsed with go.mau.fi/util/curl and each field takes the first of its sources the request has; a JSON object
// is keyed by field ID. Errors name files and field IDs, never anything read from the file.
func cookiesFromFile(path string, fields []bridgev2.LoginCookieField) (map[string]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("can't read the cookie file: %w", err)
	}
	defer f.Close()
	raw, err := io.ReadAll(io.LimitReader(f, maxCookieFile+1))
	if err != nil {
		return nil, fmt.Errorf("can't read the cookie file %s: %w", path, err)
	}
	if len(raw) > maxCookieFile {
		return nil, fmt.Errorf("the cookie file %s is over %d bytes; it should hold one cURL command or JSON object", path, maxCookieFile)
	}
	content := string(raw)
	var cookies map[string]string
	if strings.HasPrefix(strings.TrimSpace(content), "curl") {
		cookies, err = cookiesFromCURL(content, fields)
	} else {
		cookies, err = cookiesFromJSON(content, fields)
	}
	if err != nil {
		return nil, err
	}
	var missing []string
	for _, f := range fields {
		if _, ok := cookies[f.ID]; !ok && f.Required {
			missing = append(missing, f.ID)
		}
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("the file has no value for the required %s — sign in again and copy a request that has them, or %s",
			strings.Join(missing, ", "), useTheApp)
	}
	for _, f := range fields {
		if v, ok := cookies[f.ID]; ok && !cookieMatches(f, v) {
			return nil, fmt.Errorf("the value for %s in the file isn't in the form the network expects — copy it again", f.ID)
		}
	}
	return cookies, nil
}

// cookiesFromCURL takes each field's value from the first of its sources that a cURL command has: a cookie
// (URL-decoded, as bridgev2 does), a request header or a request body field. Local storage and the bridge's
// special sources are not in a request, so a required field that has only those needs a JSON file instead.
func cookiesFromCURL(content string, fields []bridgev2.LoginCookieField) (map[string]string, error) {
	parsed, err := parseCURL(content)
	if err != nil {
		return nil, err
	}
	reqCookies := map[string]string{}
	for _, c := range parsed.Cookies() {
		reqCookies[c.Name] = c.Value
	}
	cookies := map[string]string{}
	var missing, unsupported []string
	for _, f := range fields {
		var value string
		var supported bool
		for _, src := range f.Sources {
			switch src.Type {
			case bridgev2.LoginCookieTypeCookie:
				supported = true
				if v, ok := reqCookies[src.Name]; ok {
					// Decoded here rather than for every cookie in the request, as bridgev2 does: a badly
					// encoded cookie the login doesn't need shouldn't fail it.
					if value, err = url.PathUnescape(v); err != nil {
						return nil, fmt.Errorf("the cookie %s in the file isn't validly URL-encoded — copy the request again", src.Name)
					}
				}
			case bridgev2.LoginCookieTypeRequestHeader:
				supported = true
				value = parsed.Header.Get(src.Name)
			case bridgev2.LoginCookieTypeRequestBody:
				supported = true
				switch {
				case parsed.MultipartForm != nil:
					if values := parsed.MultipartForm.Value[src.Name]; len(values) > 0 {
						value = values[0]
					}
				case parsed.ParsedJSON != nil:
					if v, ok := parsed.ParsedJSON[src.Name]; ok {
						value = fmt.Sprintf("%v", v)
					}
				}
			}
			if value != "" {
				cookies[f.ID] = value
				break
			}
		}
		if value == "" && f.Required {
			if supported {
				missing = append(missing, f.ID)
			} else {
				unsupported = append(unsupported, f.ID)
			}
		}
	}
	if len(unsupported) > 0 {
		return nil, fmt.Errorf("a cURL command can't hold %s (the browser keeps it, it isn't sent in a request) — save "+
			"the values as a JSON object instead, keyed by name, like {\"%s\": \"...\"}", strings.Join(unsupported, ", "), unsupported[0])
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("the cURL command in the file has no value for the required %s — copy a request to the "+
			"sign-in site after signing in, or %s", strings.Join(missing, ", "), useTheApp)
	}
	return cookies, nil
}

// parseCURL runs go.mau.fi/util/curl's parser without letting its errors or panics through: the errors can quote
// the command (a URL, a header), and a truncated command (a "-H" with nothing after it) makes it index past the
// end of its arguments.
func parseCURL(content string) (parsed *curl.Parsed, err error) {
	defer func() {
		if recover() != nil {
			parsed, err = nil, errNotCURL
		}
	}()
	if parsed, err = curl.Parse(content); err != nil {
		return nil, errNotCURL
	}
	return parsed, nil
}

var errNotCURL = errors.New("the file starts with curl but couldn't be read as a cURL command — copy the request again with Copy as cURL")

// cookiesFromJSON reads a JSON object of text values keyed by field ID, and URL-decodes the cookie fields, as
// bridgev2 does.
func cookiesFromJSON(content string, fields []bridgev2.LoginCookieField) (map[string]string, error) {
	cookies := map[string]string{}
	if err := json.Unmarshal([]byte(content), &cookies); err != nil {
		// The JSON error can quote what it choked on, so it isn't passed on.
		return nil, errors.New("the file is neither a cURL command (starting with curl) nor a JSON object of text values")
	}
	for _, f := range fields {
		v, ok := cookies[f.ID]
		switch {
		case !ok:
		case v == "":
			delete(cookies, f.ID) // an empty value is no value: a required one is reported missing
		default:
			cookies[f.ID] = maybeURLDecodeCookie(v, f)
		}
	}
	return cookies, nil
}

// maybeURLDecodeCookie URL-decodes a value copied from the browser's developer tools, which shows cookie values
// percent-encoded, when the field is a cookie. The bridge's own cookie command does exactly this
// (bridgev2/commands/login.go) and connectors expect the decoded form.
func maybeURLDecodeCookie(val string, f bridgev2.LoginCookieField) string {
	isCookie := slices.ContainsFunc(f.Sources, func(src bridgev2.LoginCookieFieldSource) bool {
		return src.Type == bridgev2.LoginCookieTypeCookie
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
func cookieMatches(f bridgev2.LoginCookieField, val string) bool {
	if f.Pattern == "" {
		return true
	}
	re, err := regexp.Compile(f.Pattern)
	return err != nil || re.MatchString(val)
}

// sourceHints says where in the browser a value can be found.
func sourceHints(sources []bridgev2.LoginCookieFieldSource) string {
	hints := make([]string, 0, len(sources))
	for _, s := range sources {
		switch s.Type {
		case bridgev2.LoginCookieTypeCookie:
			h := fmt.Sprintf("cookie %q", s.Name)
			if s.CookieDomain != "" {
				h += " on " + s.CookieDomain
			}
			hints = append(hints, h)
		case bridgev2.LoginCookieTypeLocalStorage:
			hints = append(hints, fmt.Sprintf("local storage key %q", s.Name))
		case bridgev2.LoginCookieTypeRequestHeader:
			hints = append(hints, fmt.Sprintf("request header %q", s.Name))
		case bridgev2.LoginCookieTypeRequestBody:
			hints = append(hints, fmt.Sprintf("request body field %q", s.Name))
		default:
			hints = append(hints, fmt.Sprintf("%s %q", s.Type, s.Name))
		}
	}
	if len(hints) == 0 {
		return "(no hint from the network)"
	}
	return strings.Join(hints, " or ")
}

// terminalPrompter is the prompter for a person at a terminal.
//
// Line and Secret read the same input, and neither reads ahead: Line takes one byte at a time up to the end of
// the line, and Secret on a terminal reads the terminal itself (term.ReadPassword, also a byte at a time). A
// buffered reader in front of Line would keep typed-ahead input that the next Secret, reading the terminal
// directly, would never see.
type terminalPrompter struct {
	ctx context.Context // Ctrl-C ends a prompt that is waiting for typing
	in  io.Reader       // unbuffered: see above
	out io.Writer
	fd  int // the terminal to read hidden input from, or -1 when input isn't a terminal
}

var _ prompter = (*terminalPrompter)(nil)

// newTerminalPrompter reads from in. Secrets are only hidden when in is a terminal; piped input has nothing
// to echo.
func newTerminalPrompter(ctx context.Context, in *os.File, out io.Writer) *terminalPrompter {
	fd := int(in.Fd())
	if !term.IsTerminal(fd) {
		fd = -1
	}
	return &terminalPrompter{ctx: ctx, in: in, out: out, fd: fd}
}

type answer struct {
	text string
	err  error
}

// await waits for read to finish, or for Ctrl-C. A read that is abandoned stays blocked until the process exits;
// once Ctrl-C has been pressed no new read is started, so two never race for the same input.
func (t *terminalPrompter) await(read func() answer) (string, error) {
	if err := t.ctx.Err(); err != nil {
		return "", err
	}
	done := make(chan answer, 1)
	go func() { done <- read() }()
	select {
	case a := <-done:
		return a.text, a.err
	case <-t.ctx.Done():
		return "", t.ctx.Err()
	}
}

func (t *terminalPrompter) Line(label string) (string, error) {
	fmt.Fprintf(t.out, "%s: ", label)
	return t.await(t.readLine)
}

// readLine reads up to and including the next newline, one byte at a time, so nothing after it is consumed.
func (t *terminalPrompter) readLine() answer {
	var line []byte
	b := make([]byte, 1)
	for {
		n, err := t.in.Read(b)
		if n == 1 {
			if b[0] == '\n' {
				return answer{text: strings.TrimRight(string(line), "\r")}
			}
			line = append(line, b[0])
		}
		if err != nil {
			if errors.Is(err, io.EOF) && len(line) > 0 {
				return answer{text: strings.TrimRight(string(line), "\r")}
			}
			return answer{err: fmt.Errorf("no answer (input closed): %w", err)}
		}
	}
}

func (t *terminalPrompter) Secret(label string) (string, error) {
	fmt.Fprintf(t.out, "%s: ", label)
	if t.fd < 0 {
		return t.await(t.readLine)
	}
	saved, err := term.GetState(t.fd)
	if err != nil {
		return "", err
	}
	text, err := t.await(func() answer {
		b, err := term.ReadPassword(t.fd)
		return answer{text: string(b), err: err}
	})
	if err != nil {
		// Ctrl-C leaves ReadPassword blocked with echo off; turn echo back on before the process exits.
		_ = term.Restore(t.fd, saved)
	}
	fmt.Fprintln(t.out) // the newline the person typed was not echoed
	return text, err
}

func (t *terminalPrompter) Confirm(question string) (bool, error) {
	a, err := t.Line(question + " [y/N]")
	if err != nil {
		return false, err
	}
	switch strings.ToLower(strings.TrimSpace(a)) {
	case "y", "yes":
		return true, nil
	}
	return false, nil
}
