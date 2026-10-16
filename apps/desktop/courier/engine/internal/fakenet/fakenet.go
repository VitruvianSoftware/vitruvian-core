// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package fakenet is an in-memory chat network so the bridge-to-store glue is tested in CI without real accounts.
package fakenet

import (
	"context"
	"errors"
	"sync/atomic"
	"time"

	"go.mau.fi/util/configupgrade"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/simplevent"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
)

// Sent is one text message the bridge delivered to the fake network.
type Sent struct {
	PortalID string // the remote chat the message was sent to
	Body     string
	ReplyTo  string // the remote ID of the message it replies to, when the bridge resolved one
}

// File is one file message (image, video, audio or file) the bridge delivered to the fake network.
type File struct {
	PortalID string
	MsgType  event.MessageType
	Body     string
	FileName string
	URL      string // the content URI in courier's media store
	MimeType string
	Size     int
	Width    int
	Height   int
	ReplyTo  string
}

// Reaction is one reaction the bridge delivered to the fake network.
type Reaction struct {
	PortalID string
	TargetID string // the remote ID of the message reacted to
	Emoji    string
}

// Receipt is one read receipt the bridge delivered to the fake network.
type Receipt struct {
	PortalID  string
	MessageID string // the remote ID of the message read up to; empty when the receipt was not for a bridged message
}

// Network is a fake bridgev2.NetworkConnector. Messages the bridge delivers to the "network" land on Sent.
type Network struct {
	br        *bridgev2.Bridge
	Sent      chan Sent
	Files     chan File
	Reactions chan Reaction
	Receipts  chan Receipt
	// Hold, when set before the first send, makes every message delivery wait until it is closed (or the bridge
	// gives up), so a test can look at a message while it is still pending.
	Hold chan struct{}
	// failure is the error every delivery returns while it is set. See FailWith.
	failure atomic.Pointer[error]
	// LoginDelay makes a client report IsLoggedIn()==false until this long after Connect, the way a real
	// network connector does: Connect returns after the socket handshake, and the login only counts once the
	// server's success message is handled. Zero (the default) means logged in at once.
	LoginDelay time.Duration
}

func New() *Network {
	return &Network{
		Sent: make(chan Sent, 16), Files: make(chan File, 16),
		Reactions: make(chan Reaction, 16), Receipts: make(chan Receipt, 16),
	}
}

// FailWith makes every message, file and reaction delivery fail with err until it is called again with nil.
func (n *Network) FailWith(err error) {
	if err == nil {
		n.failure.Store(nil)
		return
	}
	n.failure.Store(&err)
}

func (n *Network) failed() error {
	if p := n.failure.Load(); p != nil {
		return *p
	}
	return nil
}

var _ bridgev2.NetworkConnector = (*Network)(nil)

func (n *Network) Init(br *bridgev2.Bridge)    { n.br = br }
func (n *Network) Start(context.Context) error { return nil }
func (n *Network) GetName() bridgev2.BridgeName {
	return bridgev2.BridgeName{DisplayName: "Fake", NetworkID: "fake", BeeperBridgeType: "fake", DefaultPort: 0}
}
func (n *Network) GetDBMetaTypes() database.MetaTypes { return database.MetaTypes{} }
func (n *Network) GetCapabilities() *bridgev2.NetworkGeneralCapabilities {
	return &bridgev2.NetworkGeneralCapabilities{}
}

func (n *Network) GetConfig() (string, any, configupgrade.Upgrader) {
	return "", nil, configupgrade.NoopUpgrader
}
func (n *Network) GetBridgeInfoVersion() (int, int)    { return 1, 1 }
func (n *Network) GetLoginFlows() []bridgev2.LoginFlow { return nil }
func (n *Network) CreateLogin(context.Context, *bridgev2.User, string) (bridgev2.LoginProcess, error) {
	return nil, bridgev2.ErrInvalidLoginFlowID
}

func (n *Network) LoadUserLogin(_ context.Context, login *bridgev2.UserLogin) error {
	login.Client = &client{n: n, login: login}
	return nil
}

// Login creates the one test login for the local user without any login flow.
func (n *Network) Login(ctx context.Context, br *bridgev2.Bridge) (*bridgev2.UserLogin, error) {
	user, err := br.GetUserByMXID(ctx, ids.Me)
	if err != nil {
		return nil, err
	}
	login, err := user.NewLogin(ctx, &database.UserLogin{ID: "fake-login", RemoteName: "Me"}, nil)
	if err != nil {
		return nil, err
	}
	login.Client.Connect(ctx)
	return login, nil
}

// Incoming queues a remote text message, as if the network had just delivered it.
func (n *Network) Incoming(login *bridgev2.UserLogin, chatID, senderID, msgID, body string) {
	n.br.QueueRemoteEvent(login, &simplevent.Message[string]{
		EventMeta: simplevent.EventMeta{
			Type: bridgev2.RemoteEventMessage, CreatePortal: true, Timestamp: time.Now(),
			PortalKey: networkid.PortalKey{ID: networkid.PortalID(chatID), Receiver: login.ID},
			Sender:    bridgev2.EventSender{Sender: networkid.UserID(senderID)},
		},
		ID:   networkid.MessageID(msgID),
		Data: body,
		ConvertMessageFunc: func(_ context.Context, _ *bridgev2.Portal, _ bridgev2.MatrixAPI, data string) (*bridgev2.ConvertedMessage, error) {
			return &bridgev2.ConvertedMessage{Parts: []*bridgev2.ConvertedMessagePart{{
				Type:    event.EventMessage,
				Content: &event.MessageEventContent{MsgType: event.MsgText, Body: data},
			}}}, nil
		},
	})
}

type client struct {
	n           *Network
	login       *bridgev2.UserLogin
	connectedAt atomic.Pointer[time.Time]
}

var _ bridgev2.NetworkAPI = (*client)(nil)

func (c *client) Connect(context.Context) {
	now := time.Now()
	c.connectedAt.Store(&now)
}
func (c *client) Disconnect() { c.connectedAt.Store(nil) }
func (c *client) IsLoggedIn() bool {
	if c.n.LoginDelay <= 0 {
		return true
	}
	at := c.connectedAt.Load()
	return at != nil && time.Since(*at) >= c.n.LoginDelay
}
func (c *client) LogoutRemote(context.Context) {}
func (c *client) IsThisUser(_ context.Context, uid networkid.UserID) bool {
	return uid == "me"
}

func (c *client) GetChatInfo(context.Context, *bridgev2.Portal) (*bridgev2.ChatInfo, error) {
	name := "Fake chat"
	return &bridgev2.ChatInfo{Name: &name}, nil
}

func (c *client) GetUserInfo(context.Context, *bridgev2.Ghost) (*bridgev2.UserInfo, error) {
	return &bridgev2.UserInfo{}, nil
}

// GetCapabilities says the fake network takes every kind of file, replies and reactions, and wants read receipts.
func (c *client) GetCapabilities(context.Context, *bridgev2.Portal) *event.RoomFeatures {
	anyFile := func() *event.FileFeatures {
		return &event.FileFeatures{MimeTypes: map[string]event.CapabilitySupportLevel{"*/*": event.CapLevelFullySupported}}
	}
	return &event.RoomFeatures{
		File: event.FileFeatureMap{
			event.MsgImage: anyFile(), event.MsgVideo: anyFile(), event.MsgAudio: anyFile(), event.MsgFile: anyFile(),
		},
		Reply: event.CapLevelFullySupported, Reaction: event.CapLevelFullySupported, ReadReceipts: true,
	}
}

var (
	_ bridgev2.ReadReceiptHandlingNetworkAPI = (*client)(nil)
	_ bridgev2.ReactionHandlingNetworkAPI    = (*client)(nil)
)

// hold waits out Network.Hold, if a test set one.
func (c *client) hold(ctx context.Context) error {
	if c.n.Hold == nil {
		return nil
	}
	select {
	case <-c.n.Hold:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (c *client) HandleMatrixMessage(ctx context.Context, msg *bridgev2.MatrixMessage) (*bridgev2.MatrixMessageResponse, error) {
	if err := c.hold(ctx); err != nil {
		return nil, err
	}
	if err := c.n.failed(); err != nil {
		return nil, err
	}
	replyTo := ""
	if msg.ReplyTo != nil {
		replyTo = string(msg.ReplyTo.ID)
	}
	// Never block the bridge's event loop if nobody is draining the channels.
	if msg.Content.MsgType == event.MsgText {
		select {
		case c.n.Sent <- Sent{PortalID: string(msg.Portal.ID), Body: msg.Content.Body, ReplyTo: replyTo}:
		default:
			return nil, errors.New("fakenet: Sent buffer is full")
		}
	} else {
		f := File{
			PortalID: string(msg.Portal.ID), MsgType: msg.Content.MsgType, Body: msg.Content.Body,
			FileName: msg.Content.FileName, URL: string(msg.Content.URL), ReplyTo: replyTo,
		}
		if info := msg.Content.Info; info != nil {
			f.MimeType, f.Size, f.Width, f.Height = info.MimeType, info.Size, info.Width, info.Height
		}
		select {
		case c.n.Files <- f:
		default:
			return nil, errors.New("fakenet: Files buffer is full")
		}
	}
	return &bridgev2.MatrixMessageResponse{DB: &database.Message{
		ID:       networkid.MessageID("out-" + string(msg.Event.ID)),
		SenderID: "me", Timestamp: time.Now(),
	}}, nil
}

func (c *client) HandleMatrixReadReceipt(_ context.Context, msg *bridgev2.MatrixReadReceipt) error {
	r := Receipt{PortalID: string(msg.Portal.ID)}
	if msg.ExactMessage != nil {
		r.MessageID = string(msg.ExactMessage.ID)
	}
	select {
	case c.n.Receipts <- r:
		return nil
	default:
		return errors.New("fakenet: Receipts buffer is full")
	}
}

func (c *client) PreHandleMatrixReaction(_ context.Context, msg *bridgev2.MatrixReaction) (bridgev2.MatrixReactionPreResponse, error) {
	return bridgev2.MatrixReactionPreResponse{SenderID: "me", Emoji: msg.Content.RelatesTo.Key}, nil
}

func (c *client) HandleMatrixReaction(ctx context.Context, msg *bridgev2.MatrixReaction) (*database.Reaction, error) {
	if err := c.hold(ctx); err != nil {
		return nil, err
	}
	if err := c.n.failed(); err != nil {
		return nil, err
	}
	select {
	case c.n.Reactions <- Reaction{PortalID: string(msg.Portal.ID), TargetID: string(msg.TargetMessage.ID), Emoji: msg.PreHandleResp.Emoji}:
		return &database.Reaction{}, nil
	default:
		return nil, errors.New("fakenet: Reactions buffer is full")
	}
}

func (c *client) HandleMatrixReactionRemove(context.Context, *bridgev2.MatrixReactionRemove) error {
	return nil
}
