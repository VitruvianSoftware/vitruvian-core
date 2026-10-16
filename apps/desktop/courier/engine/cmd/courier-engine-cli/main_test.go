// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"

	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func TestParseArgs(t *testing.T) {
	a, err := parseArgs([]string{"--data", "/tmp/x", "send", "!r:courier.local", "hello", "there"})
	require.NoError(t, err)
	require.Equal(t, args{data: "/tmp/x", cmd: "send", room: "!r:courier.local", text: "hello there"}, a)
	_, err = parseArgs([]string{"send", "!r:courier.local"})
	require.Error(t, err, "send without text must be rejected")
	_, err = parseArgs([]string{"bogus"})
	require.Error(t, err)
}

func TestParseArgsRejectsBlankSend(t *testing.T) {
	_, err := parseArgs([]string{"send", "!r:courier.local", "   "})
	require.Error(t, err, "a whitespace-only message must not be sent")
}

func TestParseArgsRejectsBridgeCommands(t *testing.T) {
	for _, text := range []string{"!whatsapp logout", "  !WhatsApp   list-logins", "!whatsapp"} {
		_, err := parseArgs([]string{"send", "!r:courier.local", text})
		require.Error(t, err, "a body that is a bridge command must not be sent: %q", text)
	}
	// Ordinary text, even with a bang or the word later on, is fine.
	for _, text := range []string{"hey !whatsapp is cool", "!important", "whatsapp !logout"} {
		_, err := parseArgs([]string{"send", "!r:courier.local", text})
		require.NoError(t, err, text)
	}
}

func TestDefaultDataDir(t *testing.T) {
	t.Setenv("HOME", "/Users/someone")
	a, err := parseArgs([]string{"chats"})
	require.NoError(t, err)
	require.Equal(t, filepath.Join("/Users/someone", "Library", "Application Support", "Courier-m1"), a.data)

	_, err = defaultDataDir("", errors.New("no home"))
	require.Error(t, err, "no home directory must not fall back to a relative path")
	_, err = defaultDataDir("", nil)
	require.Error(t, err)
	_, err = parseArgs([]string{"--data", "", "chats"})
	require.Error(t, err, "an explicit empty --data is a mistake, not the default")
}

func newStoreWithPending(t *testing.T) (*store.Store, string) {
	t.Helper()
	s, err := store.Open(filepath.Join(t.TempDir(), "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	content, err := json.Marshal(map[string]string{"msgtype": "m.text", "body": "hi"})
	require.NoError(t, err)
	require.NoError(t, s.UpsertRoom(context.Background(), store.Room{ID: "!r:courier.local", Network: "whatsapp", Name: "Test"}))
	_, err = s.InsertEvent(context.Background(), store.Event{RoomID: "!r:courier.local", EventID: "$e1", Sender: "@me:courier.local",
		Type: "m.room.message", Content: content, TS: time.Now(), Status: "pending"})
	require.NoError(t, err)
	return s, "$e1"
}

func TestWaitStatusSent(t *testing.T) {
	s, id := newStoreWithPending(t)
	require.NoError(t, s.SetStatus(context.Background(), id, "sent", ""))
	require.NoError(t, waitStatus(context.Background(), s, id, time.Second))
}

func TestWaitStatusSentArrivesWhileWaiting(t *testing.T) {
	s, id := newStoreWithPending(t)
	go func() {
		time.Sleep(100 * time.Millisecond)
		_ = s.SetStatus(context.Background(), id, "sent", "")
	}()
	require.NoError(t, waitStatus(context.Background(), s, id, 5*time.Second))
}

func TestWaitStatusFailedCarriesReason(t *testing.T) {
	s, id := newStoreWithPending(t)
	require.NoError(t, s.SetStatus(context.Background(), id, "failed", "not connected to WhatsApp"))
	err := waitStatus(context.Background(), s, id, time.Second)
	require.Error(t, err)
	require.Contains(t, err.Error(), "not connected to WhatsApp")
	require.NotContains(t, err.Error(), "delivery unknown", "a definite failure is not an unknown delivery")
}

func TestWaitStatusTimeoutIsDeliveryUnknown(t *testing.T) {
	s, id := newStoreWithPending(t)
	err := waitStatus(context.Background(), s, id, 300*time.Millisecond)
	require.Error(t, err)
	require.Contains(t, err.Error(), "delivery unknown — check your phone before resending")
	require.Contains(t, err.Error(), "event "+id+" left pending")
	e, _, gerr := s.GetEvent(context.Background(), id)
	require.NoError(t, gerr)
	require.Equal(t, "pending", e.Status, "an unknown delivery must stay pending")
}

func TestWaitStatusCancelIsDeliveryUnknown(t *testing.T) {
	s, id := newStoreWithPending(t)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	err := waitStatus(ctx, s, id, 5*time.Second)
	require.Error(t, err)
	require.Contains(t, err.Error(), "delivery unknown — check your phone before resending")
	require.Contains(t, err.Error(), "event "+id+" left pending")
}

// fakeLogin is a scripted bridgev2 login process.
type fakeLogin struct {
	start     *bridgev2.LoginStep
	startErr  error
	waits     []*bridgev2.LoginStep
	waitErr   error
	cancelled int
}

func (f *fakeLogin) Start(context.Context) (*bridgev2.LoginStep, error) { return f.start, f.startErr }
func (f *fakeLogin) Cancel()                                            { f.cancelled++ }

type fakeWaiter struct{ *fakeLogin }

func (f fakeWaiter) Wait(context.Context) (*bridgev2.LoginStep, error) {
	if f.waitErr != nil {
		return nil, f.waitErr
	}
	next := f.waits[0]
	f.waits = f.waits[1:]
	return next, nil
}

func qrStep(data string) *bridgev2.LoginStep {
	return &bridgev2.LoginStep{Type: bridgev2.LoginStepTypeDisplayAndWait, StepID: "qr",
		DisplayAndWaitParams: &bridgev2.LoginDisplayAndWaitParams{Type: bridgev2.LoginDisplayTypeQR, Data: data}}
}

func TestRunLoginCompleteDoesNotCancel(t *testing.T) {
	f := &fakeLogin{start: qrStep("code-1"), waits: []*bridgev2.LoginStep{qrStep("code-2"), {Type: bridgev2.LoginStepTypeComplete}}}
	var out bytes.Buffer
	require.NoError(t, runLogin(context.Background(), fakeWaiter{f}, &out))
	require.Zero(t, f.cancelled, "a finished login must not be cancelled")
	require.NotEmpty(t, out.String(), "the QR code must be drawn")
}

func TestRunLoginPasskeyStepCancelsWithClearMessage(t *testing.T) {
	f := &fakeLogin{start: qrStep("code"), waits: []*bridgev2.LoginStep{{Type: bridgev2.LoginStepTypeWebAuthn, StepID: "passkey"}}}
	err := runLogin(context.Background(), fakeWaiter{f}, &bytes.Buffer{})
	require.Error(t, err)
	require.Contains(t, err.Error(), "WhatsApp asked for a passkey, which this test CLI can't do — link from a device without a passkey prompt, or try again")
	require.Equal(t, 1, f.cancelled)
}

func TestRunLoginPasskeyOnFirstStepCancels(t *testing.T) {
	f := &fakeLogin{start: &bridgev2.LoginStep{Type: bridgev2.LoginStepTypeWebAuthn, StepID: "passkey"}}
	err := runLogin(context.Background(), f, &bytes.Buffer{})
	require.ErrorContains(t, err, "passkey")
	require.Equal(t, 1, f.cancelled)
}

func TestRunLoginUnexpectedStepCancelsAndNamesIt(t *testing.T) {
	f := &fakeLogin{start: &bridgev2.LoginStep{Type: bridgev2.LoginStepTypeUserInput, StepID: "fi.mau.whatsapp.phone_number"}}
	err := runLogin(context.Background(), f, &bytes.Buffer{})
	require.Error(t, err)
	require.Contains(t, err.Error(), "user_input")
	require.Contains(t, err.Error(), "fi.mau.whatsapp.phone_number")
	require.Equal(t, 1, f.cancelled)
}

func TestRunLoginStartErrorCancels(t *testing.T) {
	f := &fakeLogin{startErr: errors.New("boom")}
	require.ErrorContains(t, runLogin(context.Background(), f, &bytes.Buffer{}), "boom")
	require.Equal(t, 1, f.cancelled)
}

func TestRunLoginWaitErrorCancels(t *testing.T) {
	f := &fakeLogin{start: qrStep("code"), waitErr: context.Canceled}
	require.Error(t, runLogin(context.Background(), fakeWaiter{f}, &bytes.Buffer{}))
	require.Equal(t, 1, f.cancelled)
}

func TestRunLoginCannotWaitCancels(t *testing.T) {
	f := &fakeLogin{start: qrStep("code")}
	require.Error(t, runLogin(context.Background(), f, &bytes.Buffer{}), "a QR step on a process that cannot wait is unusable")
	require.Equal(t, 1, f.cancelled)
}
