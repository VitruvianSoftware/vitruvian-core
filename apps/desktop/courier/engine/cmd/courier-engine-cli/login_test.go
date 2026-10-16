// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
)

// scripted is a prompter that answers from queues and remembers every question it was asked.
type scripted struct {
	lines, secrets []string
	confirms       []bool
	asked          []string // "line: <label>", "secret: <label>", "confirm: <question>"
}

func (s *scripted) Line(label string) (string, error) {
	s.asked = append(s.asked, "line: "+label)
	if len(s.lines) == 0 {
		return "", fmt.Errorf("scripted: no line answer left for %q", label)
	}
	v := s.lines[0]
	s.lines = s.lines[1:]
	return v, nil
}

func (s *scripted) Secret(label string) (string, error) {
	s.asked = append(s.asked, "secret: "+label)
	if len(s.secrets) == 0 {
		return "", fmt.Errorf("scripted: no secret answer left for %q", label)
	}
	v := s.secrets[0]
	s.secrets = s.secrets[1:]
	return v, nil
}

func (s *scripted) Confirm(question string) (bool, error) {
	s.asked = append(s.asked, "confirm: "+question)
	if len(s.confirms) == 0 {
		return false, fmt.Errorf("scripted: no confirm answer left for %q", question)
	}
	v := s.confirms[0]
	s.confirms = s.confirms[1:]
	return v, nil
}

// askedWith lists the questions of one kind ("line", "secret" or "confirm").
func (s *scripted) askedWith(kind string) []string {
	var out []string
	for _, a := range s.asked {
		if rest, ok := strings.CutPrefix(a, kind+": "); ok {
			out = append(out, rest)
		}
	}
	return out
}

// fakeProc is a scripted login process. It only starts and cancels; fullProc adds the step methods.
// Every call to Wait / SubmitUserInput / SubmitCookies returns the next canned step.
type fakeProc struct {
	start     *bridgev2.LoginStep
	startErr  error
	steps     []*bridgev2.LoginStep
	stepErr   error // returned instead of a step, once steps run out
	submitted []map[string]string
	waits     int
	cancelled int
}

func (f *fakeProc) Start(context.Context) (*bridgev2.LoginStep, error) { return f.start, f.startErr }
func (f *fakeProc) Cancel()                                            { f.cancelled++ }

func (f *fakeProc) next() (*bridgev2.LoginStep, error) {
	if len(f.steps) == 0 {
		if f.stepErr != nil {
			return nil, f.stepErr
		}
		return nil, errors.New("fakeProc: no step left")
	}
	s := f.steps[0]
	f.steps = f.steps[1:]
	return s, nil
}

// fullProc can wait, take user input and take cookies, as a real connector's process may.
type fullProc struct{ *fakeProc }

func (f fullProc) Wait(context.Context) (*bridgev2.LoginStep, error) {
	f.waits++
	return f.next()
}

func (f fullProc) SubmitUserInput(_ context.Context, in map[string]string) (*bridgev2.LoginStep, error) {
	f.submitted = append(f.submitted, in)
	return f.next()
}

func (f fullProc) SubmitCookies(_ context.Context, in map[string]string) (*bridgev2.LoginStep, error) {
	f.submitted = append(f.submitted, in)
	return f.next()
}

var (
	_ bridgev2.LoginProcessDisplayAndWait = fullProc{}
	_ bridgev2.LoginProcessUserInput      = fullProc{}
	_ bridgev2.LoginProcessCookies        = fullProc{}
)

func complete() *bridgev2.LoginStep { return &bridgev2.LoginStep{Type: bridgev2.LoginStepTypeComplete} }

func qrStep(data string) *bridgev2.LoginStep {
	return &bridgev2.LoginStep{
		Type: bridgev2.LoginStepTypeDisplayAndWait, StepID: "qr",
		DisplayAndWaitParams: &bridgev2.LoginDisplayAndWaitParams{Type: bridgev2.LoginDisplayTypeQR, Data: data},
	}
}

func inputStep(fields ...bridgev2.LoginInputDataField) *bridgev2.LoginStep {
	return &bridgev2.LoginStep{
		Type: bridgev2.LoginStepTypeUserInput, StepID: "input",
		UserInputParams: &bridgev2.LoginUserInputParams{Fields: fields},
	}
}

func cookiesStep(url string, fields ...bridgev2.LoginCookieField) *bridgev2.LoginStep {
	return &bridgev2.LoginStep{
		Type: bridgev2.LoginStepTypeCookies, StepID: "cookies",
		CookiesParams: &bridgev2.LoginCookiesParams{URL: url, Fields: fields},
	}
}

func cookieField(id string, required bool, domain string) bridgev2.LoginCookieField {
	return bridgev2.LoginCookieField{
		ID: id, Required: required,
		Sources: []bridgev2.LoginCookieFieldSource{{Type: bridgev2.LoginCookieTypeCookie, Name: id, CookieDomain: domain}},
	}
}

func walk(t *testing.T, proc bridgev2.LoginProcess, p prompter) (string, error) {
	t.Helper()
	var out bytes.Buffer
	err := walkLogin(context.Background(), proc, p, &out)
	return out.String(), err
}

func TestQRStepIsDrawnThenWaits(t *testing.T) {
	f := &fakeProc{start: qrStep("code-1"), steps: []*bridgev2.LoginStep{qrStep("code-2"), complete()}}
	out, err := walk(t, fullProc{f}, &scripted{})
	require.NoError(t, err)
	require.Zero(t, f.cancelled, "a finished login must not be cancelled")
	require.NotEmpty(t, out, "the QR code must be drawn")
	require.NotContains(t, out, "code-1", "a QR is drawn as blocks, not printed as its raw data")
}

func TestUserInputStepPromptsEachFieldAndSubmits(t *testing.T) {
	f := &fakeProc{
		start: inputStep(
			bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypePhoneNumber, ID: "phone", Name: "Phone number", Description: "with country code"},
			bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldType2FACode, ID: "code", Name: "Login code", Description: "sent to your other device"},
		),
		steps: []*bridgev2.LoginStep{complete()},
	}
	p := &scripted{lines: []string{"+100000", "123456"}}
	_, err := walk(t, fullProc{f}, p)
	require.NoError(t, err)
	require.Zero(t, f.cancelled)
	require.Equal(t, []map[string]string{{"phone": "+100000", "code": "123456"}}, f.submitted)
	asked := p.askedWith("line")
	require.Len(t, asked, 2, "both fields are plain-text prompts")
	require.Contains(t, asked[0], "Phone number")
	require.Contains(t, asked[0], "with country code")
	require.Contains(t, asked[1], "Login code")
	require.Empty(t, p.askedWith("secret"))
}

func TestSecretFieldsAreNotEchoed(t *testing.T) {
	const pw, tok = "pw-sentinel-0001", "tok-sentinel-0002"
	f := &fakeProc{
		start: inputStep(
			bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypePassword, ID: "password", Name: "Two-step password"},
			bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypeToken, ID: "token", Name: "Token"},
		),
		steps: []*bridgev2.LoginStep{complete()},
	}
	p := &scripted{secrets: []string{pw, tok}}
	out, err := walk(t, fullProc{f}, p)
	require.NoError(t, err)
	require.Equal(t, []string{"Two-step password", "Token"}, trimLabels(p.askedWith("secret")), "password and token fields are read as secrets")
	require.Empty(t, p.askedWith("line"), "a secret must never go through the echoing prompt")
	require.Equal(t, []map[string]string{{"password": pw, "token": tok}}, f.submitted, "the bridge still gets the real values")
	require.NotContains(t, out, pw)
	require.NotContains(t, out, tok)
}

func TestSecretValueNeverAppearsInValidationMessages(t *testing.T) {
	const bad = "bad-secret-sentinel"
	f := &fakeProc{start: inputStep(bridgev2.LoginInputDataField{
		Type: bridgev2.LoginInputFieldTypeToken, ID: "token", Name: "Token", Pattern: `^xox[a-z]-`,
	})}
	p := &scripted{secrets: []string{bad, bad, bad}}
	out, err := walk(t, fullProc{f}, p)
	require.Error(t, err)
	require.NotContains(t, out, bad, "a rejected secret must not be printed back")
	require.NotContains(t, err.Error(), bad)
}

// trimLabels keeps the first word-group of each label: the field's name, before any description.
func trimLabels(labels []string) []string {
	out := make([]string, len(labels))
	for i, l := range labels {
		out[i], _, _ = strings.Cut(l, " (")
	}
	return out
}

func TestPatternMismatchRepromptsThenGivesUp(t *testing.T) {
	f := &fakeProc{start: inputStep(bridgev2.LoginInputDataField{
		Type: bridgev2.LoginInputFieldType2FACode, ID: "code", Name: "Code", Pattern: `^[0-9]{6}$`,
	})}
	p := &scripted{lines: []string{"abc", "12", "x"}}
	_, err := walk(t, fullProc{f}, p)
	require.Error(t, err)
	require.Len(t, p.askedWith("line"), 3, "three tries, then give up")
	require.Empty(t, f.submitted, "nothing invalid may be submitted")
	require.Equal(t, 1, f.cancelled)
}

func TestPatternMismatchThenValidValueSubmits(t *testing.T) {
	f := &fakeProc{
		start: inputStep(bridgev2.LoginInputDataField{
			Type: bridgev2.LoginInputFieldType2FACode, ID: "code", Name: "Code", Pattern: `^[0-9]{6}$`,
		}),
		steps: []*bridgev2.LoginStep{complete()},
	}
	p := &scripted{lines: []string{"abc", "654321"}}
	out, err := walk(t, fullProc{f}, p)
	require.NoError(t, err)
	require.Equal(t, []map[string]string{{"code": "654321"}}, f.submitted)
	require.Contains(t, out, "try again", "the user is told why they are asked again")
	require.Zero(t, f.cancelled)
}

func TestPhoneNumbersAreCleanedLikeTheBridgeCommandsDo(t *testing.T) {
	f := &fakeProc{
		start: inputStep(bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypePhoneNumber, ID: "phone", Name: "Phone"}),
		steps: []*bridgev2.LoginStep{complete()},
	}
	p := &scripted{lines: []string{"+1 (000) 000-0000"}}
	_, err := walk(t, fullProc{f}, p)
	require.NoError(t, err)
	require.Equal(t, []map[string]string{{"phone": "+10000000000"}}, f.submitted)
}

func TestSelectFieldOnlyTakesItsOptions(t *testing.T) {
	f := &fakeProc{
		start: inputStep(bridgev2.LoginInputDataField{
			Type: bridgev2.LoginInputFieldTypeSelect, ID: "team", Name: "Workspace", Options: []string{"alpha", "beta"},
		}),
		steps: []*bridgev2.LoginStep{complete()},
	}
	p := &scripted{lines: []string{"gamma", "beta"}}
	_, err := walk(t, fullProc{f}, p)
	require.NoError(t, err)
	require.Equal(t, []map[string]string{{"team": "beta"}}, f.submitted)
}

func TestCookiesStepPrintsURLAndSubmitsPastedValues(t *testing.T) {
	const sid, osid = "sid-sentinel-0003", "osid-sentinel-0004"
	f := &fakeProc{
		start: cookiesStep(
			"https://accounts.example.test/signin",
			cookieField("SID", true, ".example.test"),
			cookieField("OSID", true, "app.example.test"),
			cookieField("EXTRA", false, ".example.test"),
		),
		steps: []*bridgev2.LoginStep{complete()},
	}
	// Blank file path: the values are asked for one at a time, required first, then by name.
	p := &scripted{lines: []string{""}, secrets: []string{osid, sid, ""}}
	out, err := walk(t, fullProc{f}, p)
	require.NoError(t, err)
	require.Zero(t, f.cancelled)
	require.Contains(t, out, "https://accounts.example.test/signin")
	for _, hint := range []string{"SID", "OSID", "EXTRA", ".example.test", "app.example.test"} {
		require.Contains(t, out, hint, "each cookie is named with its domain so the user knows where to copy it from")
	}
	require.Len(t, p.askedWith("secret"), 3, "every cookie value is read as a secret")
	require.Len(t, p.askedWith("line"), 1, "only the file path is asked for visibly")
	require.Equal(t, []map[string]string{{"SID": sid, "OSID": osid}}, f.submitted, "a skipped optional cookie is left out")
	require.NotContains(t, out, sid)
	require.NotContains(t, out, osid)
}

func TestCookiesStepRequiredBlankCancelsWithAdvice(t *testing.T) {
	f := &fakeProc{start: cookiesStep("https://accounts.example.test/signin", cookieField("SID", true, ".example.test"))}
	_, err := walk(t, fullProc{f}, &scripted{lines: []string{""}, secrets: []string{""}})
	require.ErrorContains(t, err, "use the Courier app for this sign-in (milestone 3)")
	require.Empty(t, f.submitted)
	require.Equal(t, 1, f.cancelled)
}

func TestPastedCookiesAreURLDecodedLikeTheBridgeDoes(t *testing.T) {
	// Browser developer tools show cookie values percent-encoded; the connector wants the decoded form.
	const pasted, decoded = "xoxd-sentinel%2Bab%2Fcd%3D%3D", "xoxd-sentinel+ab/cd=="
	token := cookieField("d", true, ".example.test")
	token.Pattern = `^xoxd-[a-zA-Z0-9/+=]+$` // only the decoded form matches
	stored := bridgev2.LoginCookieField{
		ID: "ls", Required: true,
		Sources: []bridgev2.LoginCookieFieldSource{{Type: bridgev2.LoginCookieTypeLocalStorage, Name: "ls"}},
	}
	f := &fakeProc{start: cookiesStep("https://accounts.example.test", token, stored), steps: []*bridgev2.LoginStep{complete()}}
	out, err := walk(t, fullProc{f}, &scripted{lines: []string{""}, secrets: []string{pasted, "keep%2Bas-is"}})
	require.NoError(t, err)
	require.Equal(t, []map[string]string{{"d": decoded, "ls": "keep%2Bas-is"}}, f.submitted,
		"cookie fields are decoded; other sources are submitted as pasted")
	require.NotContains(t, out, "sentinel")
}

func TestCookiePatternMismatchRepromptsThenGivesUp(t *testing.T) {
	const bad1, bad2, bad3, good = "bad-one-sentinel", "bad-two-sentinel", "bad-three-sentinel", "xoxd-good"
	field := cookieField("d", true, ".example.test")
	field.Pattern = `^xoxd-`

	f := &fakeProc{start: cookiesStep("https://accounts.example.test", field), steps: []*bridgev2.LoginStep{complete()}}
	p := &scripted{lines: []string{""}, secrets: []string{bad1, bad2, good}}
	out, err := walk(t, fullProc{f}, p)
	require.NoError(t, err)
	require.Len(t, p.askedWith("secret"), 3)
	require.Equal(t, []map[string]string{{"d": good}}, f.submitted)
	require.Contains(t, out, "try again")
	require.NotContains(t, out, "sentinel", "a rejected cookie is never printed back")

	f = &fakeProc{start: cookiesStep("https://accounts.example.test", field)}
	p = &scripted{lines: []string{""}, secrets: []string{bad1, bad2, bad3}}
	out, err = walk(t, fullProc{f}, p)
	require.Error(t, err)
	require.NotContains(t, err.Error(), "sentinel")
	require.NotContains(t, out, "sentinel")
	require.Empty(t, f.submitted, "nothing invalid may be submitted")
	require.Equal(t, 1, f.cancelled)
}

func TestOptionalBlankCookieSkipsItsPattern(t *testing.T) {
	field := cookieField("EXTRA", false, ".example.test")
	field.Pattern = `^xoxd-`
	f := &fakeProc{start: cookiesStep("https://accounts.example.test", field), steps: []*bridgev2.LoginStep{complete()}}
	_, err := walk(t, fullProc{f}, &scripted{lines: []string{""}, secrets: []string{""}})
	require.NoError(t, err)
	require.Equal(t, []map[string]string{{}}, f.submitted)
}

func TestSecretsKeepTheirSpacesAndLoseOnlyTheLineEnding(t *testing.T) {
	f := &fakeProc{
		start: inputStep(bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypePassword, ID: "password", Name: "Password"}),
		steps: []*bridgev2.LoginStep{complete()},
	}
	_, err := walk(t, fullProc{f}, &scripted{secrets: []string{"  two words  \r\n"}})
	require.NoError(t, err)
	require.Equal(t, []map[string]string{{"password": "  two words  "}}, f.submitted)

	f = &fakeProc{
		start: cookiesStep("https://accounts.example.test", cookieField("SID", true, ".example.test")),
		steps: []*bridgev2.LoginStep{complete()},
	}
	_, err = walk(t, fullProc{f}, &scripted{lines: []string{""}, secrets: []string{" padded \n"}})
	require.NoError(t, err)
	require.Equal(t, []map[string]string{{"SID": " padded "}}, f.submitted)
}

func TestPlainFieldsAreTrimmed(t *testing.T) {
	f := &fakeProc{
		start: inputStep(bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypeUsername, ID: "u", Name: "User"}),
		steps: []*bridgev2.LoginStep{complete()},
	}
	_, err := walk(t, fullProc{f}, &scripted{lines: []string{"  someone \n"}})
	require.NoError(t, err)
	require.Equal(t, []map[string]string{{"u": "someone"}}, f.submitted)
}

func TestBadPatternFailsEveryTryAsInTheBridge(t *testing.T) {
	f := &fakeProc{start: inputStep(bridgev2.LoginInputDataField{
		Type: bridgev2.LoginInputFieldType2FACode, ID: "code", Name: "Code", Pattern: `([`,
	})}
	p := &scripted{lines: []string{"1", "2", "3"}}
	_, err := walk(t, fullProc{f}, p)
	require.Error(t, err)
	require.Len(t, p.askedWith("line"), 3)
	require.Equal(t, 1, f.cancelled)
}

func TestEmojiDisplayIsShownThenWaits(t *testing.T) {
	f := &fakeProc{
		start: &bridgev2.LoginStep{
			Type: bridgev2.LoginStepTypeDisplayAndWait, StepID: "emoji",
			DisplayAndWaitParams: &bridgev2.LoginDisplayAndWaitParams{Type: bridgev2.LoginDisplayTypeEmoji, Data: "🦊"},
		},
		steps: []*bridgev2.LoginStep{complete()},
	}
	out, err := walk(t, fullProc{f}, &scripted{})
	require.NoError(t, err)
	require.Contains(t, out, "🦊")
	require.Contains(t, out, "Tap/enter this on your phone")
	require.Equal(t, 1, f.waits, "after showing the emoji the CLI waits for the phone")
	require.Zero(t, f.cancelled)
}

func TestCodeDisplayIsShownThenWaits(t *testing.T) {
	f := &fakeProc{
		start: &bridgev2.LoginStep{
			Type: bridgev2.LoginStepTypeDisplayAndWait, StepID: "code",
			DisplayAndWaitParams: &bridgev2.LoginDisplayAndWaitParams{Type: bridgev2.LoginDisplayTypeCode, Data: "ABCD-EFGH"},
		},
		steps: []*bridgev2.LoginStep{complete()},
	}
	out, err := walk(t, fullProc{f}, &scripted{})
	require.NoError(t, err)
	require.Contains(t, out, "ABCD-EFGH")
	require.Contains(t, out, "Tap/enter this on your phone")
}

func TestUnsupportedStepCancelsWithAdvice(t *testing.T) {
	f := &fakeProc{start: qrStep("code"), steps: []*bridgev2.LoginStep{{Type: bridgev2.LoginStepTypeWebAuthn, StepID: "passkey"}}}
	_, err := walk(t, fullProc{f}, &scripted{})
	require.Error(t, err)
	require.Contains(t, err.Error(), "passkey")
	require.Contains(t, err.Error(), "use the Courier app for this sign-in (milestone 3)")
	require.Equal(t, 1, f.cancelled)
}

func TestUnsupportedFirstStepCancels(t *testing.T) {
	f := &fakeProc{start: &bridgev2.LoginStep{Type: bridgev2.LoginStepTypeWebAuthn, StepID: "passkey"}}
	_, err := walk(t, f, &scripted{})
	require.ErrorContains(t, err, "passkey")
	require.Equal(t, 1, f.cancelled)
}

func TestUnknownStepCancelsAndNamesIt(t *testing.T) {
	f := &fakeProc{start: &bridgev2.LoginStep{Type: bridgev2.LoginStepTypeClientHTTP, StepID: "fi.mau.example.http"}}
	_, err := walk(t, f, &scripted{})
	require.Error(t, err)
	require.Contains(t, err.Error(), "client_http")
	require.Contains(t, err.Error(), "fi.mau.example.http")
	require.Contains(t, err.Error(), "use the Courier app for this sign-in (milestone 3)")
	require.Equal(t, 1, f.cancelled)
}

func TestStartErrorCancels(t *testing.T) {
	f := &fakeProc{startErr: errors.New("boom")}
	_, err := walk(t, f, &scripted{})
	require.ErrorContains(t, err, "boom")
	require.Equal(t, 1, f.cancelled)
}

func TestNilStepCancels(t *testing.T) {
	f := &fakeProc{}
	_, err := walk(t, f, &scripted{})
	require.Error(t, err, "a process that returns no step and no error must not loop or panic")
	require.Equal(t, 1, f.cancelled)
}

func TestWaitErrorCancels(t *testing.T) {
	f := &fakeProc{start: qrStep("code"), stepErr: context.Canceled}
	_, err := walk(t, fullProc{f}, &scripted{})
	require.Error(t, err)
	require.Equal(t, 1, f.cancelled)
}

func TestSubmitErrorCancels(t *testing.T) {
	f := &fakeProc{
		start:   inputStep(bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypeUsername, ID: "u", Name: "User"}),
		stepErr: errors.New("rejected"),
	}
	_, err := walk(t, fullProc{f}, &scripted{lines: []string{"someone"}})
	require.ErrorContains(t, err, "rejected")
	require.Equal(t, 1, f.cancelled)
}

func TestPrompterErrorCancels(t *testing.T) {
	f := &fakeProc{start: inputStep(bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypeUsername, ID: "u", Name: "User"})}
	_, err := walk(t, fullProc{f}, &scripted{}) // no answers: the prompt fails, as on Ctrl-C or closed input
	require.Error(t, err)
	require.Equal(t, 1, f.cancelled)
}

func TestStepsTheProcessCannotTakeCancel(t *testing.T) {
	for name, start := range map[string]*bridgev2.LoginStep{
		"wait":    qrStep("code"),
		"input":   inputStep(bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypeUsername, ID: "u", Name: "User"}),
		"cookies": cookiesStep("https://accounts.example.test", cookieField("SID", true, ".example.test")),
	} {
		f := &fakeProc{start: start}
		_, err := walk(t, f, &scripted{})
		require.Error(t, err, name)
		require.Equal(t, 1, f.cancelled, name)
	}
}

func TestTerminalPrompterReadsLinesAndConfirms(t *testing.T) {
	var out bytes.Buffer
	tp := &terminalPrompter{ctx: context.Background(), in: strings.NewReader("hello there\r\ny\nno\n\n"), out: &out, fd: -1}
	v, err := tp.Line("Name")
	require.NoError(t, err)
	require.Equal(t, "hello there", v)
	require.Contains(t, out.String(), "Name")
	for _, want := range []bool{true, false, false} {
		got, err := tp.Confirm("Sure?")
		require.NoError(t, err)
		require.Equal(t, want, got)
	}
	_, err = tp.Line("More")
	require.Error(t, err, "closed input is an error, not an empty answer")
}

func TestTerminalPrompterSecretOnAPipeIsNotEchoed(t *testing.T) {
	const secret = "pipe-secret-sentinel"
	var out bytes.Buffer
	tp := &terminalPrompter{ctx: context.Background(), in: strings.NewReader(secret + "\n"), out: &out, fd: -1}
	v, err := tp.Secret("Token")
	require.NoError(t, err)
	require.Equal(t, secret, v)
	require.NotContains(t, out.String(), secret)
}

func TestTerminalPrompterStopsOnCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	pr := newBlockingReader()
	defer pr.release()
	tp := &terminalPrompter{ctx: ctx, in: pr, out: &bytes.Buffer{}, fd: -1}
	cancel()
	_, err := tp.Line("Name")
	require.ErrorIs(t, err, context.Canceled, "Ctrl-C must interrupt a prompt that is waiting for typing")
}

// blockingReader blocks every Read until released, like a terminal nobody is typing into.
type blockingReader struct{ done chan struct{} }

func newBlockingReader() *blockingReader { return &blockingReader{done: make(chan struct{})} }
func (b *blockingReader) Read([]byte) (int, error) {
	<-b.done
	return 0, errors.New("released")
}
func (b *blockingReader) release() { close(b.done) }

// slackLikeFields are shaped like mautrix-slack's cookies step: a token from the browser's storage or a request
// body field, and a cookie.
func slackLikeFields() []bridgev2.LoginCookieField {
	return []bridgev2.LoginCookieField{{
		ID: "auth_token", Required: true, Pattern: `^xoxc-.+$`,
		Sources: []bridgev2.LoginCookieFieldSource{
			{Type: bridgev2.LoginCookieTypeSpecial, Name: "fi.mau.example.auth_token"},
			{Type: bridgev2.LoginCookieTypeRequestBody, Name: "token"},
		},
	}, {
		ID: "cookie_token", Required: true, Pattern: `^xoxd-[a-zA-Z0-9/+=]+$`,
		Sources: []bridgev2.LoginCookieFieldSource{{Type: bridgev2.LoginCookieTypeCookie, Name: "d", CookieDomain: "example.test"}},
	}, {
		ID:      "client_header",
		Sources: []bridgev2.LoginCookieFieldSource{{Type: bridgev2.LoginCookieTypeRequestHeader, Name: "X-Example-Client"}},
	}}
}

// writeFile writes a test file and returns its path.
func writeFile(t *testing.T, name, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	require.NoError(t, os.WriteFile(path, []byte(content), 0o600))
	return path
}

// cookieWalk runs a cookies step whose file prompt is answered with path.
func cookieWalk(t *testing.T, path string, fields ...bridgev2.LoginCookieField) (*fakeProc, *scripted, string, error) {
	t.Helper()
	f := &fakeProc{start: cookiesStep("https://app.example.test/signin", fields...), steps: []*bridgev2.LoginStep{complete()}}
	p := &scripted{lines: []string{path}}
	out, err := walk(t, fullProc{f}, p)
	return f, p, out, err
}

func TestCookiesFromACURLFileWithAMultipartBody(t *testing.T) {
	// Laid out as a browser's "Copy as cURL" is: one option per line, a -b cookie list, an ANSI-C quoted body.
	const curlCmd = `curl 'https://app.example.test/api/client.boot?_x_id=sentinel-query' \
  -H 'accept: */*' \
  -H 'X-Example-Client: sentinel-client-1' \
  -b 'b=sentinel-other; d=xoxd-sentinel%2Bab%2Fcd%3D%3D; x=sentinel-x' \
  -H 'content-type: multipart/form-data; boundary=----Boundary' \
  --data-raw $'------Boundary\r\nContent-Disposition: form-data; name="token"\r\n\r\nxoxc-sentinel-token\r\n------Boundary--\r\n'
`
	f, p, out, err := cookieWalk(t, writeFile(t, "request.curl", curlCmd), slackLikeFields()...)
	require.NoError(t, err)
	require.Equal(t, []map[string]string{{
		"auth_token":    "xoxc-sentinel-token",
		"cookie_token":  "xoxd-sentinel+ab/cd==", // URL-decoded, as bridgev2 does
		"client_header": "sentinel-client-1",
	}}, f.submitted)
	require.Empty(t, p.askedWith("secret"), "a file answers every field: nothing is asked one at a time")
	require.NotContains(t, out, "sentinel", "nothing from the file is ever printed")
	require.NotContains(t, out, "Enter a JSON object", "the bridge's own instructions describe its chat command, not this CLI")
	require.Contains(t, out, "Copy as cURL")
}

func TestCookiesFromACURLFileWithACookieHeader(t *testing.T) {
	const curlCmd = "curl 'https://messages.example.test/web/config' -H 'cookie: SID=sid-sentinel; OSID=osid%3Dsentinel; NID=nid-sentinel'\n"
	f, _, out, err := cookieWalk(t, writeFile(t, "google.curl", curlCmd),
		cookieField("SID", true, ".example.test"), cookieField("OSID", true, "messages.example.test"),
		cookieField("EXTRA", false, ".example.test"))
	require.NoError(t, err)
	require.Equal(t, []map[string]string{{"SID": "sid-sentinel", "OSID": "osid=sentinel"}}, f.submitted,
		"cookies the step doesn't list are left out, and an optional one that isn't there is skipped")
	require.NotContains(t, out, "sentinel")
}

func TestCookiesFromAJSONFile(t *testing.T) {
	const doc = `{"auth_token": "xoxc-sentinel-json", "cookie_token": "xoxd-sentinel%2Fjson%3D%3D"}`
	f, _, out, err := cookieWalk(t, writeFile(t, "cookies.json", "\n"+doc+"\n"), slackLikeFields()...)
	require.NoError(t, err)
	require.Equal(t, []map[string]string{{"auth_token": "xoxc-sentinel-json", "cookie_token": "xoxd-sentinel/json=="}}, f.submitted,
		"cookie fields are URL-decoded; the token is not a cookie, so it is submitted as written")
	require.NotContains(t, out, "sentinel")
}

func TestCookieFileMissingARequiredValueCancelsNamingTheField(t *testing.T) {
	for name, c := range map[string]struct{ file, content string }{
		"curl": {"request.curl", "curl 'https://app.example.test/api/x' -b 'd=xoxd-sentinel-only'\n"},
		"json": {"cookies.json", `{"cookie_token": "xoxd-sentinelonly"}`},
	} {
		t.Run(name, func(t *testing.T) {
			f, _, out, err := cookieWalk(t, writeFile(t, c.file, c.content), slackLikeFields()...)
			require.ErrorContains(t, err, "auth_token", "the missing field is named by its ID")
			require.NotContains(t, err.Error(), "cookie_token", "a field that was there isn't reported missing")
			require.NotContains(t, err.Error(), "sentinel")
			require.NotContains(t, out, "sentinel")
			require.Empty(t, f.submitted)
			require.Equal(t, 1, f.cancelled)
		})
	}
}

func TestCookieFileThatCantBeReadNeverQuotesIt(t *testing.T) {
	for name, content := range map[string]string{
		"not json":           "sentinel-garbage {",
		"json of non-text":   `{"auth_token": 12345, "cookie_token": "xoxd-sentinel"}`,
		"truncated curl":     "curl 'https://app.example.test/sentinel-path' -H",
		"curl header no sep": "curl 'https://app.example.test/x' -H 'sentinel-no-colon'",
		"curl unclosed":      "curl 'https://app.example.test/sentinel-open",
		"value fails regex":  `{"auth_token": "not-xoxc-sentinel", "cookie_token": "xoxd-ok"}`,
	} {
		t.Run(name, func(t *testing.T) {
			var f *fakeProc
			var out string
			var err error
			require.NotPanics(t, func() { f, _, out, err = cookieWalk(t, writeFile(t, "in.txt", content), slackLikeFields()...) })
			require.Error(t, err)
			require.NotContains(t, err.Error(), "sentinel", "an error must not quote the file")
			require.NotContains(t, out, "sentinel")
			require.Empty(t, f.submitted)
			require.Equal(t, 1, f.cancelled)
		})
	}
}

func TestCURLCantHoldALocalStorageValue(t *testing.T) {
	stored := bridgev2.LoginCookieField{
		ID: "ls_token", Required: true,
		Sources: []bridgev2.LoginCookieFieldSource{{Type: bridgev2.LoginCookieTypeLocalStorage, Name: "ls_token"}},
	}
	_, _, _, err := cookieWalk(t, writeFile(t, "request.curl", "curl 'https://app.example.test/x' -b 'a=b'\n"), stored)
	require.ErrorContains(t, err, "ls_token")
	require.ErrorContains(t, err, "JSON", "the user is told the format that can hold it")
}

func TestMissingCookieFileCancelsNamingThePath(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nope.curl")
	f, _, _, err := cookieWalk(t, path, slackLikeFields()...)
	require.ErrorContains(t, err, "nope.curl")
	require.Equal(t, 1, f.cancelled)
}

func TestCookieFilePathIsCleaned(t *testing.T) {
	path := writeFile(t, "with space.json", `{"cookie_token": "xoxd-a", "auth_token": "xoxc-b"}`)
	for name, typed := range map[string]string{
		"quoted":          "'" + path + "'  ",
		"double quoted":   `"` + path + `"`,
		"dragged in":      strings.ReplaceAll(path, " ", `\ `),
		"surrounding gap": "  " + path + "\n",
	} {
		t.Run(name, func(t *testing.T) {
			f, _, _, err := cookieWalk(t, typed, slackLikeFields()...)
			require.NoError(t, err)
			require.Equal(t, []map[string]string{{"cookie_token": "xoxd-a", "auth_token": "xoxc-b"}}, f.submitted)
		})
	}
	home, err := os.UserHomeDir()
	require.NoError(t, err)
	require.Equal(t, filepath.Join(home, "x", "y.json"), cleanPath("~/x/y.json"))
}

func TestCookieFieldsAreAskedRequiredFirstThenByID(t *testing.T) {
	fields := []bridgev2.LoginCookieField{
		cookieField("EXTRA", false, ".example.test"),
		cookieField("SID", true, ".example.test"),
		cookieField("AAA", false, ".example.test"),
		cookieField("APISID", true, ".example.test"),
	}
	given := slices.Clone(fields)
	f := &fakeProc{start: cookiesStep("https://app.example.test", fields...), steps: []*bridgev2.LoginStep{complete()}}
	p := &scripted{lines: []string{""}, secrets: []string{"v1", "v2", "", ""}}
	out, err := walk(t, fullProc{f}, p)
	require.NoError(t, err)
	require.Equal(t, []string{"APISID", "SID", "AAA", "EXTRA"}, trimLabels(p.askedWith("secret")))
	require.Equal(t, []map[string]string{{"APISID": "v1", "SID": "v2"}}, f.submitted)
	listed := []int{strings.Index(out, "- APISID"), strings.Index(out, "- SID"), strings.Index(out, "- AAA"), strings.Index(out, "- EXTRA")}
	require.True(t, slices.IsSorted(listed) && listed[0] >= 0, "the list is printed in the same order: %v", listed)
	require.Equal(t, given, fields, "the step's own field list is not reordered: a connector may share it")
}

func TestMaybeURLDecodeCookie(t *testing.T) {
	cookie := cookieField("d", true, ".example.test")
	for in, want := range map[string]string{
		"xoxd-a%2Bb%2F%3D": "xoxd-a+b/=",
		"xoxd-a+b":         "xoxd-a+b",     // a literal '+' is kept: path, not query, unescaping
		"xoxd-%zz-raw":     "xoxd-%zz-raw", // not valid percent-encoding: kept as pasted
		"plain":            "plain",
	} {
		require.Equal(t, want, maybeURLDecodeCookie(in, cookie), in)
	}
	header := bridgev2.LoginCookieField{ID: "h", Sources: []bridgev2.LoginCookieFieldSource{{Type: bridgev2.LoginCookieTypeRequestHeader, Name: "h"}}}
	require.Equal(t, "a%2Bb", maybeURLDecodeCookie("a%2Bb", header), "only cookie fields are decoded")
}

func TestPastedCookieWithLiteralPlusAndBadEscapeIsKept(t *testing.T) {
	plus := cookieField("d", true, ".example.test")
	raw := cookieField("r", true, ".example.test")
	f := &fakeProc{start: cookiesStep("https://app.example.test", plus, raw), steps: []*bridgev2.LoginStep{complete()}}
	_, err := walk(t, fullProc{f}, &scripted{lines: []string{""}, secrets: []string{"a+b", "c%zzd"}})
	require.NoError(t, err)
	require.Equal(t, []map[string]string{{"d": "a+b", "r": "c%zzd"}}, f.submitted)
}

func TestTerminalPrompterLineThenSecretShareOneInput(t *testing.T) {
	const secret = "shared-secret-sentinel"
	var out bytes.Buffer
	tp := &terminalPrompter{ctx: context.Background(), in: strings.NewReader("/tmp/none\n" + secret + "\nlast\n"), out: &out, fd: -1}
	v, err := tp.Line("Path")
	require.NoError(t, err)
	require.Equal(t, "/tmp/none", v)
	v, err = tp.Secret("Value")
	require.NoError(t, err)
	require.Equal(t, secret, v, "the secret comes from the same input, not lost to a buffer")
	v, err = tp.Line("Again")
	require.NoError(t, err)
	require.Equal(t, "last", v)
	require.NotContains(t, out.String(), secret)
}

func TestTerminalPrompterLineDoesNotReadAhead(t *testing.T) {
	// On a terminal, Secret reads the terminal itself, not through Line's reader. So Line must leave everything
	// after its own line unread, or a Secret that follows would lose it.
	in := strings.NewReader("first\nsecond\n")
	tp := &terminalPrompter{ctx: context.Background(), in: in, out: &bytes.Buffer{}, fd: -1}
	v, err := tp.Line("First")
	require.NoError(t, err)
	require.Equal(t, "first", v)
	rest, err := io.ReadAll(in)
	require.NoError(t, err)
	require.Equal(t, "second\n", string(rest))
}

func TestTerminalPrompterAfterCancelStartsNoRead(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	in := strings.NewReader("never\n")
	tp := &terminalPrompter{ctx: ctx, in: in, out: &bytes.Buffer{}, fd: -1}
	_, err := tp.Line("Name")
	require.ErrorIs(t, err, context.Canceled)
	require.Equal(t, int64(len("never\n")), int64(in.Len()), "no read is started once Ctrl-C was pressed")
}
