// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"regexp"
	"slices"
	"strings"

	"github.com/mdp/qrterminal/v3"
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
			var verr error
			if value, verr = checkInput(field, strings.TrimSpace(raw)); verr == nil {
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
	if f.Pattern != "" {
		// A pattern that doesn't compile can't be checked here; the bridge checks what it gets anyway.
		if re, err := regexp.Compile(f.Pattern); err == nil && !re.MatchString(value) {
			return "", errors.New("it doesn't match the expected format")
		}
	}
	// The same cleaning and checks the bridge's own login commands apply (phone numbers, emails).
	f.FillDefaultValidate()
	return f.Validate(value)
}

// askCookies lists the values a cookies step needs, where to get them, and reads each one without echo.
// Optional values may be left blank. A blank required value cancels the login: pasting browser cookies by hand
// is the best this CLI can do, and without them it has no other way in.
func askCookies(step *bridgev2.LoginStep, p prompter, out io.Writer) (map[string]string, error) {
	if step.Instructions != "" {
		fmt.Fprintln(out, step.Instructions)
	}
	c := step.CookiesParams
	if c == nil {
		return nil, fmt.Errorf("login step %q (id %q) lists no cookies to ask for", step.Type, step.StepID)
	}
	fmt.Fprintf(out, "Sign in at this address in your browser:\n  %s\n", c.URL)
	fmt.Fprintln(out, "Then copy each of these values (browser developer tools, Application or Storage tab). They are not shown as you paste them:")
	for _, f := range c.Fields {
		req := "optional"
		if f.Required {
			req = "required"
		}
		fmt.Fprintf(out, "  - %s (%s): %s\n", f.ID, req, sourceHints(f.Sources))
	}
	cookies := map[string]string{}
	for _, f := range c.Fields {
		label := f.ID
		if !f.Required {
			label += " (optional — press Enter to skip)"
		}
		v, err := p.Secret(label)
		if err != nil {
			return nil, err
		}
		v = strings.TrimSpace(v)
		if v == "" {
			if f.Required {
				return nil, fmt.Errorf("no value for the required %s — %s", f.ID, useTheApp)
			}
			continue
		}
		cookies[f.ID] = v
	}
	return cookies, nil
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
type terminalPrompter struct {
	ctx context.Context // Ctrl-C ends a prompt that is waiting for typing
	in  *bufio.Reader
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
	return &terminalPrompter{ctx: ctx, in: bufio.NewReader(in), out: out, fd: fd}
}

type answer struct {
	text string
	err  error
}

// await waits for read to finish, or for Ctrl-C. A read that is abandoned stays blocked until the process exits.
func (t *terminalPrompter) await(read func() answer) (string, error) {
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

func (t *terminalPrompter) readLine() answer {
	s, err := t.in.ReadString('\n')
	if err != nil && !(errors.Is(err, io.EOF) && s != "") {
		return answer{err: fmt.Errorf("no answer (input closed): %w", err)}
	}
	return answer{text: strings.TrimRight(s, "\r\n")}
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
