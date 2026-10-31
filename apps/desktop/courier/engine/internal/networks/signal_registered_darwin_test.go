// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

//go:build darwin

package networks

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	signal "go.mau.fi/mautrix-signal/pkg/connector"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/gchat"
)

// On macOS Signal and Google Chat are registered after the portable four.
func TestSignalIsRegisteredLastOnDarwin(t *testing.T) {
	var names []string
	for _, n := range All() {
		names = append(names, n.Name)
	}
	require.Equal(t, []string{"whatsapp", "telegram", "gmessages", "slack", "signal", "gchat"}, names)

	signal, ok := Get("signal")
	require.True(t, ok)
	require.Equal(t, "Signal", signal.DisplayName)
	require.Equal(t, []string{"qr"}, signal.Flows)

	gchatNet, ok := Get("gchat")
	require.True(t, ok)
	require.Equal(t, "Google Chat", gchatNet.DisplayName)
	require.Equal(t, []string{"cookies"}, gchatNet.Flows)
}

// platformClients adds Signal's and Google Chat's rows of the sync table.
func platformClients() map[string]platformClient {
	return map[string]platformClient{
		"signal": {
			client: (*signal.SignalClient)(nil), sent: []string{"accept_request"}, implements: []string{"accept_request"},
		},
		"gchat": {
			client: (*gchat.Client)(nil), sent: []string{}, implements: []string{},
		},
	}
}

// platformActionRows adds Signal's rows of the message action table: a DM and a group, plus a note to self (my own
// chat with myself), where the bridge sets no edit or delete age limit. The client's UserLogin is set: Signal tells
// a note to self by it.
func platformActionRows() (map[string]actionRow, map[string]handlerRow) {
	client := &signal.SignalClient{UserLogin: &bridgev2.UserLogin{UserLogin: &database.UserLogin{ID: "my-uuid"}}}
	sig := actions.Features{
		Reply: true, Edit: true, EditMaxAge: 24 * time.Hour, EditMaxCount: 10, Unsend: true, UnsendMaxAge: 24 * time.Hour,
		Poll:         &actions.PollFeatures{MaxOptions: 10, OptionMaxLength: 100},
		Disappearing: &actions.DisappearingFeatures{Type: "after_read", Timers: actions.SignalTimers},
		Formatting:   everyKind, MaxTextLength: 2000,
	}
	self := sig
	self.EditMaxAge, self.UnsendMaxAge = 0, 0
	noteToSelf := portalOf(database.RoomTypeDM, "my-uuid", nil)
	noteToSelf.Receiver = "my-uuid"
	gcClient := (*gchat.Client)(nil)
	gcDM := actions.Features{
		Reply: true, Edit: true, Unsend: true,
		Formatting: noSpoiler, MentionRoom: false, MaxTextLength: 4096,
	}
	gcSpace := gcDM
	gcSpace.MentionRoom = true
	gcThreadedSpace := gcSpace
	gcThreadedSpace.Thread = true
	return map[string]actionRow{
			"signal dm":            {client, portalOf(database.RoomTypeDM, "their-uuid", nil), sig},
			"signal group":         {client, portalOf(database.RoomTypeDefault, "group-id", nil), sig},
			"signal note to self":  {client, noteToSelf, self},
			"gchat dm":             {gcClient, portalOf(database.RoomTypeDM, gchat.MakeDMPortalID("111"), &gchat.PortalMetadata{TopicThreaded: false}), gcDM},
			"gchat space":          {gcClient, portalOf(database.RoomTypeDefault, gchat.MakeSpacePortalID("222"), &gchat.PortalMetadata{TopicThreaded: false}), gcSpace},
			"gchat threaded space": {gcClient, portalOf(database.RoomTypeDefault, gchat.MakeSpacePortalID("333"), &gchat.PortalMetadata{TopicThreaded: true}), gcThreadedSpace},
		}, map[string]handlerRow{
			"signal": {client, []string{"edit", "remove", "poll", "timer"}},
			"gchat":  {gcClient, []string{"edit", "remove"}},
		}
}

// platformPollChecks adds Signal to TestPollsArriveAsPolls.
func platformPollChecks() map[string]func(data any) bool {
	return map[string]func(data any) bool{
		"signal": func(data any) bool { return data.(*signal.SignalConfig).ExtEvPolls },
	}
}

// platformReceiptColumns adds Signal's and Google Chat's columns of the receipts, typing and accounts table.
func platformReceiptColumns() map[string]receiptNetwork {
	return map[string]receiptNetwork{
		"signal": {
			connector: &signal.SignalConnector{}, client: (*signal.SignalClient)(nil),
			sends: []string{"read_receipts", "typing"}, replyPrivately: []string{"resolve_identifier", "create_chat_with_ghost"},
			implicitReads: true,
		},
		"gchat": {
			connector: gchat.NewConnector(), client: (*gchat.Client)(nil),
			sends: []string{"read_receipts", "typing"}, replyPrivately: []string{},
			implicitReads: false,
		},
	}
}
