// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package fakenet

import (
	"context"
	"time"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/simplevent"
	"maunium.net/go/mautrix/event"
)

// Message is one remote text message for IncomingMessage: Incoming's message with the rest a real network says.
type Message struct {
	// ID is the message's remote ID, and Body its text.
	ID, Body string
	// SenderID is who wrote it, by network ID; with FromMe it is ignored, and the message is mine (sent from another
	// device), as a real bridge reports one.
	SenderID string
	FromMe   bool
	// At is when it was sent; zero is now.
	At time.Time
	// ReplyTo and ThreadRoot are remote IDs of messages already in the chat: the one this replies to, and the root of
	// the thread it is in. Empty says none.
	ReplyTo, ThreadRoot string
}

// IncomingMessage queues m into the login's own chat chatID, as if the network had just delivered it: Incoming with
// a time, a sender that may be me, and a reply or thread.
func (n *Network) IncomingMessage(login *bridgev2.UserLogin, chatID string, m Message) {
	at := m.At
	if at.IsZero() {
		at = time.Now()
	}
	sender := bridgev2.EventSender{Sender: networkid.UserID(m.SenderID)}
	if m.FromMe {
		sender = bridgev2.EventSender{Sender: "me", IsFromMe: true, SenderLogin: login.ID}
	}
	var replyTo *networkid.MessageOptionalPartID
	if m.ReplyTo != "" {
		replyTo = &networkid.MessageOptionalPartID{MessageID: networkid.MessageID(m.ReplyTo)}
	}
	var root *networkid.MessageID
	if m.ThreadRoot != "" {
		r := networkid.MessageID(m.ThreadRoot)
		root = &r
	}
	n.br.QueueRemoteEvent(login, &simplevent.Message[string]{
		EventMeta: simplevent.EventMeta{
			Type: bridgev2.RemoteEventMessage, CreatePortal: true, Timestamp: at,
			PortalKey: networkid.PortalKey{ID: networkid.PortalID(chatID), Receiver: login.ID},
			Sender:    sender,
		},
		ID:   networkid.MessageID(m.ID),
		Data: m.Body,
		ConvertMessageFunc: func(_ context.Context, _ *bridgev2.Portal, _ bridgev2.MatrixAPI, data string) (*bridgev2.ConvertedMessage, error) {
			return &bridgev2.ConvertedMessage{
				ReplyTo:    replyTo,
				ThreadRoot: root,
				Parts: []*bridgev2.ConvertedMessagePart{{
					Type:    event.EventMessage,
					Content: &event.MessageEventContent{MsgType: event.MsgText, Body: data},
				}},
			}, nil
		},
	})
}

// IncomingReaction queues a remote reaction with emoji from senderID ("me" is mine, from another device) to the
// message targetID in the login's own chat chatID, sent at at (zero is now).
func (n *Network) IncomingReaction(login *bridgev2.UserLogin, chatID, senderID, targetID, emoji string, at time.Time) {
	if at.IsZero() {
		at = time.Now()
	}
	sender := bridgev2.EventSender{Sender: networkid.UserID(senderID)}
	if senderID == "me" {
		sender = bridgev2.EventSender{Sender: "me", IsFromMe: true, SenderLogin: login.ID}
	}
	n.br.QueueRemoteEvent(login, &simplevent.Reaction{
		EventMeta: simplevent.EventMeta{
			Type: bridgev2.RemoteEventReaction, Timestamp: at,
			PortalKey: networkid.PortalKey{ID: networkid.PortalID(chatID), Receiver: login.ID},
			Sender:    sender,
		},
		TargetMessage: networkid.MessageID(targetID),
		Emoji:         emoji,
	})
}
