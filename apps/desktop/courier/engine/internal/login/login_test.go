// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package login

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"

	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// world is an engine running the fake network as "fake", with a driver over it. The network has one login
// flow, fakenet.ScriptFlow, which plays the steps a test gives it.
type world struct {
	d      *Driver
	s      *store.Store
	n      *fakenet.Network
	eng    *engine.Engine
	script *fakenet.ScriptedLogin
}

func fakeFlows(name string) ([]string, bool) {
	if name == "fake" {
		return []string{fakenet.ScriptFlow}, true
	}
	return nil, false
}

func newWorld(t *testing.T, linked bool, steps ...*bridgev2.LoginStep) world {
	t.Helper()
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	n := fakenet.New()
	eng, errs := engine.Start(ctx, dir, s, &media.Store{Dir: filepath.Join(dir, "media")},
		[]engine.Spec{{Name: "fake", Connector: func() (bridgev2.NetworkConnector, error) { return n, nil }}}, zerolog.Nop())
	require.Empty(t, errs)
	t.Cleanup(eng.Stop)
	if linked {
		h, ok := eng.Host("fake")
		require.True(t, ok)
		_, err = n.Login(ctx, h.Bridge)
		require.NoError(t, err)
	}
	w := world{d: NewDriver(eng, s, fakeFlows), s: s, n: n, eng: eng}
	w.script = &fakenet.ScriptedLogin{Steps: steps}
	n.Script = w.script
	return w
}

// start begins a login on the fake network's script flow.
func (w world) start(t *testing.T) Step {
	t.Helper()
	step, err := w.d.Start(context.Background(), "fake", fakenet.ScriptFlow, StartOptions{})
	require.NoError(t, err)
	return step
}

func complete() *bridgev2.LoginStep {
	return &bridgev2.LoginStep{
		Type: bridgev2.LoginStepTypeComplete, StepID: "fi.mau.fake.complete",
		CompleteParams: &bridgev2.LoginCompleteParams{
			UserLoginID: "fake-login",
			UserLogin:   &bridgev2.UserLogin{UserLogin: &database.UserLogin{ID: "fake-login", RemoteName: "Test Account"}},
		},
	}
}

func displayStep(id string, kind bridgev2.LoginDisplayType, data string) *bridgev2.LoginStep {
	return &bridgev2.LoginStep{
		Type: bridgev2.LoginStepTypeDisplayAndWait, StepID: id, Instructions: "Look at your phone.",
		DisplayAndWaitParams: &bridgev2.LoginDisplayAndWaitParams{Type: kind, Data: data},
	}
}

func inputStep(fields ...bridgev2.LoginInputDataField) *bridgev2.LoginStep {
	return &bridgev2.LoginStep{
		Type: bridgev2.LoginStepTypeUserInput, StepID: "fi.mau.fake.input", Instructions: "Tell us who you are.",
		UserInputParams: &bridgev2.LoginUserInputParams{Fields: fields},
	}
}

func cookiesStep(fields ...bridgev2.LoginCookieField) *bridgev2.LoginStep {
	return &bridgev2.LoginStep{
		Type: bridgev2.LoginStepTypeCookies, StepID: "fi.mau.fake.cookies",
		CookiesParams: &bridgev2.LoginCookiesParams{
			URL: "https://accounts.example.test/signin", UserAgent: "Example/1.0",
			WaitForURLPattern: `^https://app\.example\.test/`, ExtractJS: "(async () => ({}))()", Fields: fields,
		},
	}
}

func cookieField(id string, required bool, pattern string) bridgev2.LoginCookieField {
	return bridgev2.LoginCookieField{
		ID: id, Required: required, Pattern: pattern,
		Sources: []bridgev2.LoginCookieFieldSource{{Type: bridgev2.LoginCookieTypeCookie, Name: id, CookieDomain: ".example.test"}},
	}
}

func jsonOf(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	require.NoError(t, err)
	return string(b)
}

func TestStepsMapToWireShape(t *testing.T) {
	ctx := context.Background()
	w := newWorld(
		t, false,
		displayStep("fi.mau.fake.qr", bridgev2.LoginDisplayTypeQR, "qr-data-1"),
		displayStep("fi.mau.fake.emoji", bridgev2.LoginDisplayTypeEmoji, "🦊"),
		displayStep("fi.mau.fake.code", bridgev2.LoginDisplayTypeCode, "ABCD-EFGH"),
		inputStep(
			bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypeUsername, ID: "user", Name: "User", Description: "Your handle"},
			bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypeSelect, ID: "mode", Name: "Mode", Options: []string{"a", "b"}, DefaultValue: "a"},
			bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldType2FACode, ID: "code", Name: "Code", Pattern: `^[0-9]{6}$`},
		),
		cookiesStep(cookieField("sid", true, `^s-`)),
		complete(),
	)
	qr := w.start(t)
	id := qr.LoginID
	require.NotEmpty(t, id)
	require.JSONEq(t, fmt.Sprintf(`{"login_id":%q,"step_id":"fi.mau.fake.qr","type":"display_and_wait",
		"instructions":"Look at your phone.","display":{"kind":"qr","data":"qr-data-1"}}`, id), jsonOf(t, qr))

	emoji, err := w.d.Wait(ctx, id)
	require.NoError(t, err)
	require.JSONEq(t, fmt.Sprintf(`{"login_id":%q,"step_id":"fi.mau.fake.emoji","type":"display_and_wait",
		"instructions":"Look at your phone.","display":{"kind":"emoji","data":"🦊"}}`, id), jsonOf(t, emoji))

	code, err := w.d.Wait(ctx, id)
	require.NoError(t, err)
	require.JSONEq(t, fmt.Sprintf(`{"login_id":%q,"step_id":"fi.mau.fake.code","type":"display_and_wait",
		"instructions":"Look at your phone.","display":{"kind":"code","data":"ABCD-EFGH"}}`, id), jsonOf(t, code))

	fields, err := w.d.Wait(ctx, id)
	require.NoError(t, err)
	require.JSONEq(t, fmt.Sprintf(`{"login_id":%q,"step_id":"fi.mau.fake.input","type":"user_input",
		"instructions":"Tell us who you are.","fields":[
		{"id":"user","name":"User","description":"Your handle","type":"username"},
		{"id":"mode","name":"Mode","description":"","type":"select","options":["a","b"],"default_value":"a"},
		{"id":"code","name":"Code","description":"","type":"2fa_code","pattern":"^[0-9]{6}$"}]}`, id), jsonOf(t, fields))

	cookies, err := w.d.Submit(ctx, id, map[string]string{"user": "someone", "mode": "a", "code": "123456"})
	require.NoError(t, err)
	require.JSONEq(t, fmt.Sprintf(`{"login_id":%q,"step_id":"fi.mau.fake.cookies","type":"cookies","cookies":{
		"url":"https://accounts.example.test/signin","user_agent":"Example/1.0",
		"wait_for_url":"^https://app\\.example\\.test/","extract_js":"(async () => ({}))()",
		"fields":[{"id":"sid","required":true,"pattern":"^s-","sources":[{"type":"cookie","name":"sid","cookie_domain":".example.test"}]}]}}`, id),
		jsonOf(t, cookies))

	done, err := w.d.Submit(ctx, id, map[string]string{"sid": "s-1"})
	require.NoError(t, err)
	// The account it became is on the wire (protocol 5); other_account is left out, as it is false.
	require.JSONEq(t, fmt.Sprintf(`{"login_id":%q,"step_id":"fi.mau.fake.complete","type":"complete","remote_name":"Test Account",
		"account_id":"fake-login"}`, id), jsonOf(t, done))
	require.Zero(t, w.script.Cancelled(), "a completed login is not cancelled")

	_, err = w.d.Wait(ctx, id)
	require.ErrorIs(t, err, ErrUnknownLogin, "a completed login is over")
}

func TestSubmitValidatesPatternWithoutEchoing(t *testing.T) {
	ctx := context.Background()
	const bad = "bad-value-sentinel"
	w := newWorld(
		t, false,
		inputStep(
			bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypeToken, ID: "token", Name: "Token", Pattern: `^xox[a-z]-`},
			bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypePhoneNumber, ID: "phone", Name: "Phone"},
		),
		complete(),
	)
	id := w.start(t).LoginID

	for name, values := range map[string]map[string]string{
		"pattern mismatch": {"token": bad, "phone": "+15550100"},
		"bad phone":        {"token": "xoxa-ok", "phone": bad},
		"missing":          {"phone": "+15550100"},
	} {
		_, err := w.d.Submit(ctx, id, values)
		require.ErrorIs(t, err, ErrBadValue, name)
		require.NotContains(t, err.Error(), bad, name+": a value is never echoed")
		require.NotContains(t, err.Error(), "+15550100", name)
	}
	require.Empty(t, w.script.Submitted(), "nothing invalid reaches the connector")
	require.Zero(t, w.script.Cancelled(), "a bad value leaves the login open so the person can try again")

	// The error names the field, so the app can mark it.
	_, err := w.d.Submit(ctx, id, map[string]string{"token": bad, "phone": "+15550100"})
	require.ErrorContains(t, err, "Token")

	step, err := w.d.Submit(ctx, id, map[string]string{"token": "xoxa-ok", "phone": "+1 (555) 0100"})
	require.NoError(t, err)
	require.Equal(t, StepComplete, step.Type)
	require.Equal(t, []map[string]string{{"token": "xoxa-ok", "phone": "+15550100"}}, w.script.Submitted(),
		"a phone number is cleaned the way the bridge's own login does")
}

func TestPlainFieldsAreTrimmedAndSecretsAreNot(t *testing.T) {
	ctx := context.Background()
	w := newWorld(
		t, false,
		inputStep(
			bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypeUsername, ID: "user", Name: "User"},
			bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypePassword, ID: "pw", Name: "Password"},
			bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypeUsername, ID: "nick", Name: "Nick", DefaultValue: "me"},
			bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypeSelect, ID: "mode", Name: "Mode", Options: []string{"a", "b"}},
		),
		complete(),
	)
	id := w.start(t).LoginID
	_, err := w.d.Submit(ctx, id, map[string]string{"user": "x", "pw": "p", "mode": "c"})
	require.ErrorIs(t, err, ErrBadValue, "a select takes only its options")
	_, err = w.d.Submit(ctx, id, map[string]string{"user": "  someone \n", "pw": "  two words  ", "mode": "b", "other": "ignored"})
	require.NoError(t, err)
	require.Equal(t, []map[string]string{{"user": "someone", "pw": "  two words  ", "nick": "me", "mode": "b"}}, w.script.Submitted(),
		"plain fields are trimmed, a secret is kept exactly, a blank field takes its default and unknown keys are dropped")
}

func TestCookieValuesAreURLDecodedLikeBridgev2(t *testing.T) {
	// Browser developer tools show cookie values percent-encoded; the connector wants the decoded form.
	const pasted, decoded = "xoxd-sentinel%2Bab%2Fcd%3D%3D", "xoxd-sentinel+ab/cd=="
	cookie := cookieField("d", true, `^xoxd-[a-zA-Z0-9/+=]+$`) // only the decoded form matches
	stored := bridgev2.LoginCookieField{
		ID: "ls", Required: true,
		Sources: []bridgev2.LoginCookieFieldSource{{Type: bridgev2.LoginCookieTypeLocalStorage, Name: "ls"}},
	}
	plus := cookieField("plus", true, "")
	raw := cookieField("raw", true, "")
	optional := cookieField("extra", false, `^xoxd-`)

	w := newWorld(t, false, cookiesStep(cookie, stored, plus, raw, optional), complete())
	id := w.start(t).LoginID
	_, err := w.d.Submit(context.Background(), id, map[string]string{
		"d": pasted, "ls": "keep%2Bas-is", "plus": "a+b", "raw": "c%zzd", "extra": "",
	})
	require.NoError(t, err)
	require.Equal(t, []map[string]string{{
		"d": decoded, "ls": "keep%2Bas-is", "plus": "a+b", "raw": "c%zzd",
	}}, w.script.Submitted(), "cookie fields are decoded; other sources are submitted as pasted; a blank optional is left out")
}

func TestMaybeURLDecodeCookie(t *testing.T) {
	cookie := CookieField{Sources: []CookieSource{{Type: SourceCookie, Name: "d"}}}
	for in, want := range map[string]string{
		"xoxd-a%2Bb%2F%3D": "xoxd-a+b/=",
		"xoxd-a+b":         "xoxd-a+b",     // a literal '+' is kept: path, not query, unescaping
		"xoxd-%zz-raw":     "xoxd-%zz-raw", // not valid percent-encoding: kept as pasted
		"plain":            "plain",
	} {
		require.Equal(t, want, MaybeURLDecodeCookie(in, cookie), in)
	}
	header := CookieField{Sources: []CookieSource{{Type: SourceRequestHeader, Name: "h"}}}
	require.Equal(t, "a%2Bb", MaybeURLDecodeCookie("a%2Bb", header), "only cookie fields are decoded")
}

func TestCookieSubmitChecksPatternRequiredAndNeverEchoes(t *testing.T) {
	ctx := context.Background()
	const bad = "cookie-sentinel"
	w := newWorld(t, false, cookiesStep(cookieField("sid", true, `^s-`), cookieField("opt", false, "")), complete())
	id := w.start(t).LoginID

	_, err := w.d.Submit(ctx, id, map[string]string{"sid": bad})
	require.ErrorIs(t, err, ErrBadValue)
	require.NotContains(t, err.Error(), bad)
	require.ErrorContains(t, err, "sid")

	_, err = w.d.Submit(ctx, id, map[string]string{"opt": "x"})
	require.ErrorIs(t, err, ErrBadValue)
	require.ErrorContains(t, err, "sid", "a missing required value is named by its ID")
	require.Empty(t, w.script.Submitted())
	require.Zero(t, w.script.Cancelled())

	_, err = w.d.Submit(ctx, id, map[string]string{"sid": "s-ok"})
	require.NoError(t, err)
	require.Equal(t, []map[string]string{{"sid": "s-ok"}}, w.script.Submitted())
}

func TestCancelOnEveryNonCompleteExit(t *testing.T) {
	ctx := context.Background()

	t.Run("cancel", func(t *testing.T) {
		w := newWorld(t, false, displayStep("qr", bridgev2.LoginDisplayTypeQR, "x"))
		id := w.start(t).LoginID
		w.d.Cancel(id)
		require.Equal(t, 1, w.script.Cancelled())
		w.d.Cancel(id) // harmless the second time, and for a login that never existed
		w.d.Cancel("no-such-login")
		require.Equal(t, 1, w.script.Cancelled(), "a login is cancelled once")
		_, err := w.d.Wait(ctx, id)
		require.ErrorIs(t, err, ErrUnknownLogin)
	})

	t.Run("cancel while a wait is blocked, without waiting for its lock", func(t *testing.T) {
		w := newWorld(t, false, displayStep("qr", bridgev2.LoginDisplayTypeQR, "x"), complete())
		w.script.Hold = make(chan struct{})
		id := w.start(t).LoginID
		waited := make(chan error, 1)
		go func() { _, err := w.d.Wait(ctx, id); waited <- err }()
		time.Sleep(50 * time.Millisecond) // let the Wait block inside the connector

		cancelled := make(chan struct{})
		go func() { w.d.Cancel(id); close(cancelled) }()
		select {
		case <-cancelled:
		case <-time.After(5 * time.Second):
			t.Fatal("Cancel waited behind a blocked Wait")
		}
		select {
		case err := <-waited:
			require.Error(t, err, "the blocked Wait comes back")
		case <-time.After(5 * time.Second):
			t.Fatal("the blocked Wait never returned after Cancel")
		}
		require.Equal(t, 1, w.script.Cancelled(), "exactly one cancel, even though Wait also saw the cancellation")
	})

	t.Run("ctx cancel during a wait", func(t *testing.T) {
		w := newWorld(t, false, displayStep("qr", bridgev2.LoginDisplayTypeQR, "x"), complete())
		w.script.Hold = make(chan struct{})
		id := w.start(t).LoginID
		wctx, cancel := context.WithCancel(ctx)
		waited := make(chan error, 1)
		go func() { _, err := w.d.Wait(wctx, id); waited <- err }()
		time.Sleep(50 * time.Millisecond)
		cancel()
		require.ErrorIs(t, <-waited, context.Canceled)
		require.Equal(t, 1, w.script.Cancelled())
		_, err := w.d.Wait(ctx, id)
		require.ErrorIs(t, err, ErrUnknownLogin, "the session is gone")
	})

	t.Run("ctx already cancelled at a submit", func(t *testing.T) {
		w := newWorld(t, false, inputStep(bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypeUsername, ID: "u", Name: "U"}),
			displayStep("qr", bridgev2.LoginDisplayTypeQR, "x"))
		id := w.start(t).LoginID
		cctx, cancel := context.WithCancel(ctx)
		cancel()
		_, err := w.d.Submit(cctx, id, map[string]string{"u": "x"})
		require.ErrorIs(t, err, context.Canceled)
		require.Equal(t, 1, w.script.Cancelled())
	})

	t.Run("the connector fails", func(t *testing.T) {
		w := newWorld(t, false, displayStep("qr", bridgev2.LoginDisplayTypeQR, "x")) // no step left for the Wait
		id := w.start(t).LoginID
		_, err := w.d.Wait(ctx, id)
		require.Error(t, err)
		require.Equal(t, 1, w.script.Cancelled())
		_, err = w.d.Wait(ctx, id)
		require.ErrorIs(t, err, ErrUnknownLogin)
	})

	t.Run("a step this app cannot do", func(t *testing.T) {
		w := newWorld(t, false, displayStep("qr", bridgev2.LoginDisplayTypeQR, "x"),
			&bridgev2.LoginStep{Type: bridgev2.LoginStepTypeWebAuthn, StepID: "fi.mau.fake.passkey"})
		id := w.start(t).LoginID
		step, err := w.d.Wait(ctx, id)
		require.NoError(t, err)
		require.Equal(t, StepUnsupported, step.Type)
		require.Equal(t, 1, w.script.Cancelled())
	})

	t.Run("idle", func(t *testing.T) {
		w := newWorld(t, false, displayStep("qr", bridgev2.LoginDisplayTypeQR, "x"))
		w.d.IdleTimeout = 50 * time.Millisecond
		id := w.start(t).LoginID
		require.Eventually(t, func() bool { return w.script.Cancelled() == 1 }, 5*time.Second, 10*time.Millisecond,
			"a session nobody touches is cancelled")
		_, err := w.d.Wait(ctx, id)
		require.ErrorIs(t, err, ErrUnknownLogin)
		time.Sleep(100 * time.Millisecond)
		require.Equal(t, 1, w.script.Cancelled())
	})

	t.Run("a call keeps the session alive", func(t *testing.T) {
		w := newWorld(t, false, displayStep("qr", bridgev2.LoginDisplayTypeQR, "x"), displayStep("qr2", bridgev2.LoginDisplayTypeQR, "y"), complete())
		w.d.IdleTimeout = 300 * time.Millisecond
		id := w.start(t).LoginID
		w.script.Hold = make(chan struct{})
		waited := make(chan error, 1)
		go func() { _, err := w.d.Wait(ctx, id); waited <- err }()
		time.Sleep(600 * time.Millisecond) // longer than the idle timeout, but a Wait is a call in progress
		require.Zero(t, w.script.Cancelled(), "a session that is waiting for the phone is not idle")
		close(w.script.Hold)
		require.NoError(t, <-waited)
	})
}

func TestIdleTimeoutDefaultsToTenMinutes(t *testing.T) {
	w := newWorld(t, false)
	require.Equal(t, 10*time.Minute, w.d.IdleTimeout)
}

// setState records state event as the bridge state of the login accountID on the fake network, as the connector
// does: under the login's remote_id.
func (w world) setState(t *testing.T, accountID, event string) {
	t.Helper()
	require.NoError(t, w.s.SetLoginState(context.Background(), "fake", accountID,
		json.RawMessage(fmt.Sprintf(`{"state_event":%q,"remote_id":%q}`, event, accountID))))
}

// The first login's rule (4.3) with neither option: a network whose account works is linked; only one Reconnect
// fixes may be signed in again, and that login is what the connector is handed to replace.
func TestAlreadyLinkedRefusedUnlessLoggedOut(t *testing.T) {
	ctx := context.Background()

	for _, event := range []string{"", "CONNECTED", "CONNECTING", "TRANSIENT_DISCONNECT", "BACKFILLING"} {
		t.Run("refused when "+event, func(t *testing.T) {
			w := newWorld(t, true, complete())
			if event != "" { // "" is no state at all
				w.setState(t, "fake-login", event)
			}
			_, err := w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{})
			require.ErrorIs(t, err, ErrAlreadyLinked)
			require.Nil(t, w.script.Override())
			require.Zero(t, w.script.Cancelled(), "no login process was even created")
			_, err = w.script.Wait(ctx)
			require.NoError(t, err, "the script's one step is still unused")
		})
	}

	for _, event := range []string{"LOGGED_OUT", "BAD_CREDENTIALS", "UNKNOWN_ERROR"} {
		t.Run("may re-link when "+event, func(t *testing.T) {
			w := newWorld(t, true, complete())
			w.setState(t, "fake-login", event)
			step, err := w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{})
			require.NoError(t, err)
			require.Equal(t, StepComplete, step.Type)
			require.NotNil(t, w.script.Override(), "the existing login is handed to the connector to be replaced")
			require.Equal(t, "fake-login", string(w.script.Override().ID))
		})
	}

	t.Run("the bridge's own state is no login's", func(t *testing.T) {
		w := newWorld(t, true, complete())
		w.setState(t, "fake-login", "CONNECTED")
		w.setState(t, "", "LOGGED_OUT")
		_, err := w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{})
		require.ErrorIs(t, err, ErrAlreadyLinked)
	})

	t.Run("a network with no login links freely whatever its state", func(t *testing.T) {
		w := newWorld(t, false, complete())
		w.setState(t, "", "CONNECTED")
		step, err := w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{})
		require.NoError(t, err)
		require.Equal(t, StepComplete, step.Type)
		require.Nil(t, w.script.Override())
	})
}

// completeAs is a complete step for the login id, named name.
func completeAs(id, name string) *bridgev2.LoginStep {
	return &bridgev2.LoginStep{
		Type: bridgev2.LoginStepTypeComplete, StepID: "fi.mau.fake.complete",
		CompleteParams: &bridgev2.LoginCompleteParams{
			UserLoginID: networkid.UserLoginID(id),
			UserLogin:   &bridgev2.UserLogin{UserLogin: &database.UserLogin{ID: networkid.UserLoginID(id), RemoteName: name}},
		},
	}
}

// secondLogin adds the login "second" ("Work") beside the world's first, "fake-login".
func (w world) secondLogin(t *testing.T) *bridgev2.UserLogin {
	t.Helper()
	h, ok := w.eng.Host("fake")
	require.True(t, ok)
	b, err := w.n.LoginAs(context.Background(), h.Bridge, "second", "Work")
	require.NoError(t, err)
	return b
}

// cached is the fake network's login id as the bridge has it now, nil when it has none.
func (w world) cached(t *testing.T, id string) *bridgev2.UserLogin {
	t.Helper()
	h, ok := w.eng.Host("fake")
	require.True(t, ok)
	return h.Bridge.GetCachedUserLoginByID(networkid.UserLoginID(id))
}

// stateOf is the stored bridge state of the login id on the fake network ("" when it has none).
func (w world) stateOf(t *testing.T, id string) string {
	t.Helper()
	states, err := w.s.LoginStates(context.Background(), "fake")
	require.NoError(t, err)
	for _, l := range states {
		if l.LoginID == id {
			var st struct {
				StateEvent string `json:"state_event"`
			}
			require.NoError(t, json.Unmarshal(l.State, &st))
			return st.StateEvent
		}
	}
	return ""
}

// Another signs in beside the accounts linked, though the first works: no login is handed over to be replaced, and
// the first is left as it was. Without it the first login's rule stands; with both options the call can't be meant.
func TestAnotherSignsInBesideTheFirst(t *testing.T) {
	ctx := context.Background()
	w := newWorld(t, true, completeAs("second", "Work"))
	w.script.Creates = true
	w.setState(t, "fake-login", "CONNECTED")

	_, err := w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{})
	require.ErrorIs(t, err, ErrAlreadyLinked, "with neither option a working account is linked")
	_, err = w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{Another: true, AccountID: "fake-login"})
	require.ErrorIs(t, err, ErrBadValue, "beside the accounts and in place of one at once")
	require.Nil(t, w.cached(t, "second"), "neither refusal signed anything in")

	step, err := w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{Another: true})
	require.NoError(t, err)
	require.Equal(t, StepComplete, step.Type)
	require.Nil(t, w.script.Override(), "nothing is replaced")
	require.NotNil(t, w.cached(t, "second"), "the new account")
	require.NotNil(t, w.cached(t, "fake-login"), "the first account is still there")
	require.Equal(t, "CONNECTED", w.stateOf(t, "fake-login"))
	require.Equal(t, "second", step.AccountID)
	require.False(t, step.OtherAccount, "a sign-in beside the accounts asked for none of them")

	t.Run("on a network with no login it is the first sign-in", func(t *testing.T) {
		w := newWorld(t, false, complete())
		step, err := w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{Another: true})
		require.NoError(t, err)
		require.Equal(t, StepComplete, step.Type)
	})
}

// A login is signed in again by its ID only in a state Reconnect fixes, its own: another login's state says nothing
// about it. One that works is ErrAlreadyLinked; an ID that is no login of the network's is ErrBadValue.
func TestRelinkNeedsAStateReconnectFixes(t *testing.T) {
	ctx := context.Background()
	for _, event := range []string{"", "CONNECTED", "CONNECTING", "TRANSIENT_DISCONNECT", "BACKFILLING"} {
		t.Run("refused when "+event, func(t *testing.T) {
			w := newWorld(t, true, complete())
			w.secondLogin(t)
			w.setState(t, "fake-login", "LOGGED_OUT") // the other one would be allowed
			if event != "" {
				w.setState(t, "second", event)
			}
			_, err := w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{AccountID: "second"})
			require.ErrorIs(t, err, ErrAlreadyLinked)
			require.Nil(t, w.script.Override())
			require.Zero(t, w.script.Cancelled(), "no login process was even created")
		})
	}
	for _, event := range []string{"LOGGED_OUT", "BAD_CREDENTIALS", "UNKNOWN_ERROR"} {
		t.Run("may re-link when "+event, func(t *testing.T) {
			w := newWorld(t, true, complete())
			w.secondLogin(t)
			w.setState(t, "fake-login", "CONNECTED")
			w.setState(t, "second", event)
			step, err := w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{AccountID: "second"})
			require.NoError(t, err)
			require.Equal(t, StepComplete, step.Type)
			require.NotNil(t, w.script.Override())
			require.Equal(t, "second", string(w.script.Override().ID), "the login named is the one handed over")
		})
	}
	t.Run("an ID that is no login of the network's", func(t *testing.T) {
		w := newWorld(t, true, complete())
		w.setState(t, "fake-login", "LOGGED_OUT")
		w.setState(t, "gone", "LOGGED_OUT") // a state row outlives its login
		for _, id := range []string{"gone", "nonesuch"} {
			_, err := w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{AccountID: id})
			require.ErrorIs(t, err, ErrBadValue, id)
		}
		require.Nil(t, w.script.Override())
	})
}

// Review Focus 5 (Ruling 11): signing one login in again leaves every other login alone, and never deletes the one
// asked for. Signed in again as the same account, it is that login, updated (bridgev2 reuses a login with the same
// ID: the bridge's own DeleteOnConflict path). Signed in as another account (the other one linked, or a new one), the
// login asked for stays as it was, with its state and chats, and the account signed in is beside it; the step says
// which account it became, and that it wasn't the one asked for.
func TestRelinkOneLoginLeavesTheOther(t *testing.T) {
	ctx := context.Background()
	for name, c := range map[string]struct {
		completeAs string
		other      bool
	}{
		"as the same account":           {completeAs: "fake-login"},
		"as the other account linked":   {completeAs: "second", other: true},
		"as an account not linked here": {completeAs: "fresh", other: true},
	} {
		t.Run(name, func(t *testing.T) {
			w := newWorld(t, true, completeAs(c.completeAs, "Home"))
			w.script.Creates = true
			a := w.cached(t, "fake-login")
			b := w.secondLogin(t)
			w.n.Incoming(a, "chatA", "alice", "a1", "for A")
			w.n.Incoming(b, "chatB", "bob", "b1", "for B")
			roomA, roomB := w.roomWith(t, "for A"), w.roomWith(t, "for B")
			w.setState(t, "fake-login", "BAD_CREDENTIALS")
			w.setState(t, "second", "CONNECTED")

			step, err := w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{AccountID: "fake-login"})
			require.NoError(t, err)
			require.Equal(t, StepComplete, step.Type)
			require.Equal(t, "fake-login", string(w.script.Override().ID))
			require.Equal(t, c.completeAs, step.AccountID, "the account the sign-in became")
			require.Equal(t, c.other, step.OtherAccount, "whether that wasn't the one asked for")

			require.Same(t, a, w.cached(t, "fake-login"), "the login asked for is never deleted")
			require.Same(t, b, w.cached(t, "second"), "the other login is the same login")
			require.True(t, b.Client.IsLoggedIn())
			require.NotNil(t, w.cached(t, c.completeAs))
			if c.completeAs != "fake-login" {
				require.Equal(t, "BAD_CREDENTIALS", w.stateOf(t, "fake-login"), "its state stays: its banner and Reconnect too")
			} else {
				require.Equal(t, "Home", a.RemoteName, "signed in again, the login is updated")
			}
			require.Equal(t, "CONNECTED", w.stateOf(t, "second"), "the other login's state is untouched")
			for room, login := range map[string]string{roomA: "fake-login", roomB: "second"} {
				r, ok, err := w.s.GetRoom(ctx, room)
				require.NoError(t, err)
				require.True(t, ok)
				require.Equal(t, login, r.LoginID, "each chat keeps its login")
			}
		})
	}
}

// roomWith waits for the bridge to store a chat holding a message with body in it (fakenet.RoomWith), and returns
// the chat.
func (w world) roomWith(t *testing.T, body string) string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second) // a deadlock guard, not a measure
	defer cancel()
	r, err := fakenet.RoomWith(ctx, w.s, body)
	require.NoError(t, err, "the bridge never stored the chat")
	return r.ID
}

func TestWebAuthnIsUnsupportedStep(t *testing.T) {
	ctx := context.Background()

	t.Run("first step", func(t *testing.T) {
		w := newWorld(t, false, &bridgev2.LoginStep{Type: bridgev2.LoginStepTypeWebAuthn, StepID: "fi.mau.fake.passkey"})
		step, err := w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{})
		require.NoError(t, err, "an unsupported step is an answer, not an error")
		require.Equal(t, StepUnsupported, step.Type)
		require.Equal(t, "fi.mau.fake.passkey", step.StepID)
		require.Contains(t, step.Instructions, "webauthn")
		require.Contains(t, step.Instructions, "fi.mau.fake.passkey")
		require.Contains(t, step.Instructions, "passkey")
		require.Contains(t, step.Instructions, "different sign-in method")
		require.Nil(t, step.Display)
		require.Empty(t, step.Fields)
		require.Equal(t, 1, w.script.Cancelled())
		_, err = w.d.Submit(ctx, step.LoginID, nil)
		require.ErrorIs(t, err, ErrUnknownLogin, "the session is removed")
	})

	t.Run("an unknown step type after a submit", func(t *testing.T) {
		w := newWorld(t, false,
			inputStep(bridgev2.LoginInputDataField{Type: bridgev2.LoginInputFieldTypeUsername, ID: "u", Name: "U"}),
			&bridgev2.LoginStep{Type: bridgev2.LoginStepTypeClientHTTP, StepID: "fi.mau.fake.http"})
		id := w.start(t).LoginID
		step, err := w.d.Submit(ctx, id, map[string]string{"u": "x"})
		require.NoError(t, err)
		require.Equal(t, StepUnsupported, step.Type)
		require.Contains(t, step.Instructions, "client_http")
		require.Contains(t, step.Instructions, "fi.mau.fake.http")
		require.Equal(t, id, step.LoginID)
		require.Equal(t, 1, w.script.Cancelled())
	})
}

func TestStartRefusesWhatTheNetworkDoesNotOffer(t *testing.T) {
	ctx := context.Background()
	w := newWorld(t, false, complete())

	_, err := w.d.Start(ctx, "fake", "qr", StartOptions{})
	require.ErrorIs(t, err, ErrBadValue)
	require.ErrorContains(t, err, `"qr"`, "the message names the flow")

	_, err = w.d.Start(ctx, "nosuch", "qr", StartOptions{})
	require.ErrorIs(t, err, ErrBadValue)
	require.ErrorContains(t, err, "nosuch")

	step, err := w.d.Start(ctx, "fake", "", StartOptions{})
	require.NoError(t, err, "no flow means the network's first")
	require.Equal(t, StepComplete, step.Type)

	// A network the table lists but that isn't running (Telegram without its credentials).
	d := NewDriver(w.eng, w.s, func(name string) ([]string, bool) { return []string{"qr"}, true })
	_, err = d.Start(ctx, "telegram", "qr", StartOptions{})
	require.ErrorIs(t, err, ErrNotRunning)
	require.ErrorContains(t, err, "telegram")
}

func TestACallThatDoesNotFitTheStepIsRefusedAndLeavesTheLoginOpen(t *testing.T) {
	ctx := context.Background()
	w := newWorld(t, false, displayStep("qr", bridgev2.LoginDisplayTypeQR, "x"), complete())
	id := w.start(t).LoginID

	_, err := w.d.Submit(ctx, id, map[string]string{"a": "b"})
	require.ErrorIs(t, err, ErrBadValue, "this step is waiting for the phone, not for a value")
	require.Zero(t, w.script.Cancelled())
	step, err := w.d.Wait(ctx, id)
	require.NoError(t, err)
	require.Equal(t, StepComplete, step.Type)

	_, err = w.d.Submit(ctx, "no-such-login", nil)
	require.ErrorIs(t, err, ErrUnknownLogin)
}

func TestSessionsAreIndependent(t *testing.T) {
	w := newWorld(t, false, displayStep("qr", bridgev2.LoginDisplayTypeQR, "x"))
	a := w.start(t).LoginID
	// One sign-in per network at a time, so the second is on another network.
	other := &fakenet.ScriptedLogin{Steps: []*bridgev2.LoginStep{displayStep("qr", bridgev2.LoginDisplayTypeQR, "y")}}
	step, err := w.d.StartProcess(context.Background(), "other", other)
	require.NoError(t, err)
	b := step.LoginID
	require.NotEqual(t, a, b)
	w.d.Cancel(a)
	require.Equal(t, 1, w.script.Cancelled())
	require.Zero(t, other.Cancelled(), "cancelling one login leaves the other alone")
	w.d.Cancel(b)
	require.Equal(t, 1, other.Cancelled())
}

func TestCallsOnOneSessionRunOneAtATime(t *testing.T) {
	ctx := context.Background()
	w := newWorld(t, false, displayStep("qr", bridgev2.LoginDisplayTypeQR, "x"), displayStep("qr2", bridgev2.LoginDisplayTypeQR, "y"), complete())
	w.script.Hold = make(chan struct{})
	id := w.start(t).LoginID

	var mu sync.Mutex
	var kinds []string
	var wg sync.WaitGroup
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			step, err := w.d.Wait(ctx, id)
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				kinds = append(kinds, "err: "+err.Error())
				return
			}
			kinds = append(kinds, step.StepID)
		}()
	}
	time.Sleep(50 * time.Millisecond)
	close(w.script.Hold)
	wg.Wait()
	require.ElementsMatch(t, []string{"qr2", "fi.mau.fake.complete"}, kinds, "each Wait got its own step; none was lost or doubled")
}

// A second sign-in on a network that has one in progress is refused, so a double-click can't pair two devices.
// The one in progress is left alone, and once it is over, by any way out, the network can be signed in to again.
func TestOneSignInPerNetworkAtATime(t *testing.T) {
	ctx := context.Background()
	qr := func() []*bridgev2.LoginStep {
		return []*bridgev2.LoginStep{displayStep("qr", bridgev2.LoginDisplayTypeQR, "x")}
	}

	t.Run("refused while one is live, free again after Cancel", func(t *testing.T) {
		w := newWorld(t, false, qr()...)
		first := w.start(t).LoginID
		second := &fakenet.ScriptedLogin{Steps: qr()}
		w.n.Script = second
		_, err := w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{})
		require.ErrorIs(t, err, ErrLoginInProgress)
		require.Zero(t, w.script.Cancelled(), "the sign-in in progress is not touched")
		_, err = w.d.Wait(ctx, first)
		require.NotErrorIs(t, err, ErrUnknownLogin, "the first sign-in is still there")

		w.d.Cancel(first)
		_, err = w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{})
		require.NoError(t, err, "cancelling frees the network")
	})

	t.Run("free again after it completes", func(t *testing.T) {
		w := newWorld(t, false, displayStep("qr", bridgev2.LoginDisplayTypeQR, "x"), complete())
		id := w.start(t).LoginID
		step, err := w.d.Wait(ctx, id)
		require.NoError(t, err)
		require.Equal(t, StepComplete, step.Type)
		w.n.Script = &fakenet.ScriptedLogin{Steps: qr()}
		_, err = w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{})
		require.NoError(t, err)
	})

	t.Run("free again after it fails", func(t *testing.T) {
		w := newWorld(t, false, qr()...) // no step left for the Wait: the connector fails
		id := w.start(t).LoginID
		_, err := w.d.Wait(ctx, id)
		require.Error(t, err)
		w.n.Script = &fakenet.ScriptedLogin{Steps: qr()}
		_, err = w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{})
		require.NoError(t, err)
	})

	t.Run("free again after it times out", func(t *testing.T) {
		w := newWorld(t, false, qr()...)
		w.d.IdleTimeout = 50 * time.Millisecond
		w.start(t)
		require.Eventually(t, func() bool { return w.script.Cancelled() == 1 }, 5*time.Second, 10*time.Millisecond)
		w.n.Script = &fakenet.ScriptedLogin{Steps: qr()}
		_, err := w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{})
		require.NoError(t, err)
	})

	t.Run("of many at once, one starts", func(t *testing.T) {
		w := newWorld(t, false, qr()...)
		var wg sync.WaitGroup
		var mu sync.Mutex
		started, refused := 0, 0
		for range 8 {
			wg.Add(1)
			go func() {
				defer wg.Done()
				_, err := w.d.Start(ctx, "fake", fakenet.ScriptFlow, StartOptions{})
				mu.Lock()
				defer mu.Unlock()
				switch {
				case err == nil:
					started++
				case errors.Is(err, ErrLoginInProgress):
					refused++
				default:
					t.Errorf("unexpected error: %v", err)
				}
			}()
		}
		wg.Wait()
		require.Equal(t, 1, started)
		require.Equal(t, 7, refused)
	})

	t.Run("a sign-in on another network does not count", func(t *testing.T) {
		w := newWorld(t, false, qr()...)
		_, err := w.d.StartProcess(ctx, "other", &fakenet.ScriptedLogin{Steps: qr()})
		require.NoError(t, err)
		w.start(t)
	})
}
