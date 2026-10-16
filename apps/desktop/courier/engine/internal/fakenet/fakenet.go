// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package fakenet is an in-memory chat network so the bridge-to-store glue is tested in CI without real accounts.
package fakenet

import (
	"context"
	"errors"
	"time"

	"go.mau.fi/util/configupgrade"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/simplevent"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
)

// Sent is one message the bridge delivered to the fake network.
type Sent struct {
	PortalID string // the remote chat the message was sent to
	Body     string
}

// Network is a fake bridgev2.NetworkConnector. Messages the bridge delivers to the "network" land on Sent.
type Network struct {
	br   *bridgev2.Bridge
	Sent chan Sent
}

func New() *Network { return &Network{Sent: make(chan Sent, 16)} }

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
		EventMeta: simplevent.EventMeta{Type: bridgev2.RemoteEventMessage, CreatePortal: true, Timestamp: time.Now(),
			PortalKey: networkid.PortalKey{ID: networkid.PortalID(chatID), Receiver: login.ID},
			Sender:    bridgev2.EventSender{Sender: networkid.UserID(senderID)}},
		ID:   networkid.MessageID(msgID),
		Data: body,
		ConvertMessageFunc: func(_ context.Context, _ *bridgev2.Portal, _ bridgev2.MatrixAPI, data string) (*bridgev2.ConvertedMessage, error) {
			return &bridgev2.ConvertedMessage{Parts: []*bridgev2.ConvertedMessagePart{{Type: event.EventMessage,
				Content: &event.MessageEventContent{MsgType: event.MsgText, Body: data}}}}, nil
		},
	})
}

type client struct {
	n     *Network
	login *bridgev2.UserLogin
}

var _ bridgev2.NetworkAPI = (*client)(nil)

func (c *client) Connect(context.Context)      {}
func (c *client) Disconnect()                  {}
func (c *client) IsLoggedIn() bool             { return true }
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
func (c *client) GetCapabilities(context.Context, *bridgev2.Portal) *event.RoomFeatures {
	return &event.RoomFeatures{}
}
func (c *client) HandleMatrixMessage(_ context.Context, msg *bridgev2.MatrixMessage) (*bridgev2.MatrixMessageResponse, error) {
	// Never block the bridge's event loop if nobody is draining Sent.
	select {
	case c.n.Sent <- Sent{PortalID: string(msg.Portal.ID), Body: msg.Content.Body}:
	default:
		return nil, errors.New("fakenet: Sent buffer is full")
	}
	return &bridgev2.MatrixMessageResponse{DB: &database.Message{ID: networkid.MessageID("out-" + string(msg.Event.ID)),
		SenderID: "me", Timestamp: time.Now()}}, nil
}
