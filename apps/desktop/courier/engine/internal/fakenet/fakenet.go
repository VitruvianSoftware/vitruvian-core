// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package fakenet is an in-memory chat network so the bridge-to-store glue is tested in CI without real accounts.
package fakenet

import (
	"context"
	"encoding/json"
	"errors"
	"sort"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"go.mau.fi/util/configupgrade"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/simplevent"
	"maunium.net/go/mautrix/bridgev2/status"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
)

// Call is one group or chat-management call the bridge delivered to the fake network.
type Call struct {
	Method   string
	PortalID string
	Target   string
	Value    string
}

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

// TagChange is one change of a chat's tags the bridge delivered to the fake network: the tags the chat has now,
// sorted. Empty means none (unpinned).
type TagChange struct {
	PortalID string
	Tags     []event.RoomTag
}

// MuteChange is one mute the bridge delivered to the fake network: MutedUntil is Unix milliseconds, -1 for
// "forever" and 0 for "not muted".
type MuteChange struct {
	PortalID   string
	MutedUntil int64
}

// UnreadChange is one "marked unread" flag the bridge delivered to the fake network.
type UnreadChange struct {
	PortalID string
	Unread   bool
}

// Accept is one accepted message request the bridge delivered to the fake network.
type Accept struct {
	PortalID string
}

// Edit is one edit of a message the bridge delivered to the fake network.
type Edit struct {
	PortalID string
	TargetID string // the remote ID of the message edited
	Body     string // the new text
}

// Remove is one deleted message (a redaction) the bridge delivered to the fake network.
type Remove struct {
	PortalID string
	TargetID string // the remote ID of the message deleted
}

// Poll is one new poll the bridge delivered to the fake network.
type Poll struct {
	PortalID      string
	Question      string
	Options       []string // the options' text, in order
	MaxSelections int
}

// Vote is one poll vote the bridge delivered to the fake network.
type Vote struct {
	PortalID string
	PollID   string   // the remote ID of the poll voted in
	Answers  []string // the chosen options' IDs
}

// TimerChange is one change of a chat's disappearing-message timer the bridge delivered to the fake network.
type TimerChange struct {
	PortalID string
	Type     event.DisappearingType // "" (none) when the timer is turned off
	Timer    time.Duration
}

// TypingChange is one change of my typing the bridge delivered to the fake network (HandleMatrixTyping): Typing is
// a start, otherwise a stop. bridgev2 hands one over only when the chat's typing list changes.
type TypingChange struct {
	PortalID string
	Typing   bool
}

// ChatStart is one one-to-one chat the bridge asked the fake network to start (Reply Privately): with the person
// UserID (their network ID), by the login LoginID, through CreateChatWithGhost (Via ViaGhost) or ResolveIdentifier
// (Via ViaIdentifier).
type ChatStart struct {
	LoginID, UserID string
	Via             StartChats
}

// StartChats is how a login's client starts a one-to-one chat with someone, as the networks differ (Global
// Constraints' Reply Privately row).
type StartChats int

const (
	// ViaGhost is bridgev2.GhostDMCreatingNetworkAPI's CreateChatWithGhost, as WhatsApp, Signal and Slack start one.
	// The default.
	ViaGhost StartChats = iota
	// ViaIdentifier is bridgev2.IdentifierResolvingNetworkAPI's ResolveIdentifier alone, as Telegram (the user's
	// numeric ID) and Google Messages start one.
	ViaIdentifier
	// NoChatStarts is a client that starts no chats: it implements neither interface.
	NoChatStarts
)

// Contact is a person returned by GetContactList, SearchUsers, or ResolveIdentifier on the fake network.
type Contact struct {
	UserID      string
	Name        string
	AvatarURL   id.ContentURIString
	Identifiers []string
}

// DirectChatID is the remote chat ID of the one-to-one chat the fake network starts with userID.
func DirectChatID(userID string) string { return "dm-" + userID }

// Chat is what the fake network says about one chat when the bridge first asks (GetChatInfo). Nil fields say
// nothing.
type Chat struct {
	// Name is the chat's title reported by GetChatInfo; nil defaults to "Fake chat".
	Name *string
	// Tag and MutedUntil are the chat's own state on the network (bridgev2's UserLocal info): Tag
	// "m.favourite" is a chat pinned on the phone, "m.lowpriority" one archived there.
	Tag        *event.RoomTag
	MutedUntil *time.Time
	// MessageRequest says the chat is someone new writing first, waiting to be accepted.
	MessageRequest *bool
	// Direct says the chat is one-to-one (bridgev2's RoomTypeDM). bridgev2 takes a delivery receipt only in one.
	Direct *bool
	// Members are the people the chat lists, by network ID, beside me: a real bridge's member list, which may leave
	// out some who write (a large Telegram group lists only some). Nil says nothing.
	Members []string
}

// Network is a fake bridgev2.NetworkConnector. Messages the bridge delivers to the "network" land on Sent.
type Network struct {
	br        *bridgev2.Bridge
	Sent      chan Sent
	Files     chan File
	Reactions chan Reaction
	Receipts  chan Receipt
	// Typings receives my typing as the bridge delivers it, from every client, plain or not.
	Typings chan TypingChange
	// Tags, Mutes, Unreads and Accepts receive the chat changes the bridge delivers. A network made with NewPlain
	// takes none of them, so nothing ever lands there.
	Tags    chan TagChange
	Mutes   chan MuteChange
	Unreads chan UnreadChange
	Accepts chan Accept
	// Edits, Removes, Polls, Votes and Timers receive the message changes the bridge delivers: edits, deletions
	// (redactions), new polls, poll votes and disappearing-timer changes. Every client takes them, plain or not;
	// the room features (Features) decide which ones the bridge lets through.
	Edits   chan Edit
	Removes chan Remove
	Polls   chan Poll
	Votes   chan Vote
	Timers  chan TimerChange
	// ReactionRemoves receives the reactions the bridge takes back (a redaction of a reaction).
	ReactionRemoves chan Reaction
	// ChatStarts receives each one-to-one chat the bridge asks a client to start (StartChats).
	ChatStarts chan ChatStart
	// StartChats, set before a login is made, is how its client starts a one-to-one chat. The zero value starts none.
	StartChats StartChats
	// ChatStartErr, when set, is what every chat start answers (CreateChatWithGhost and ResolveIdentifier), before
	// anything reaches ChatStarts: a network that can't find the person, say.
	ChatStartErr error
	// ChatInfoErr, when set, is what GetChatInfo answers, and a chat start then says nothing of the chat (no
	// PortalInfo), so the bridge has to ask: a network that can't describe the chat it just made.
	ChatInfoErr error
	// OmitPortalInfo, when set, makes startChat and CreateGroup return a CreateChatResponse with PortalInfo == nil
	// even when ChatInfoErr is nil, as Telegram's ResolveIdentifier does, so the caller or bridgev2 must call GetChatInfo.
	OmitPortalInfo bool
	// Contacts are the entries returned by GetContactList.
	Contacts []Contact
	// SearchResults are the entries returned by SearchUsers.
	SearchResults []Contact
	// EchoTimers, when set before a timer change is sent, makes the network echo the change back while the bridge is
	// still handling it, and the bridge pass the echo on as its notice (bridgev2's DisappearingMessageNotice with its
	// com.beeper.action_message), as a network and bridge that don't drop their own echo would. No pinned bridge does:
	// each stores the new timer on the portal first, so the echo matches it and is dropped.
	EchoTimers bool
	// Refuse, when set before a change is sent, makes the network refuse every pin, mute, unread mark, request
	// accept, edit, deletion, reaction removal, poll, vote, timer change and chat start, the way an offline or
	// unhappy network does.
	Refuse bool
	// Features, when set before the bridge first asks, is what the client's GetCapabilities returns: the room
	// features of every chat. Nil means the default (every kind of file, replies, reactions, read receipts).
	// Change it later with SetFeatures.
	Features *event.RoomFeatures
	// Hold, when set before the first send, makes every message delivery wait until it is closed (or the bridge
	// gives up), so a test can look at a message while it is still pending.
	Hold chan struct{}
	// HoldChanges, when set before a chat or message change is sent (a pin, a mute, an edit, a deletion…), makes
	// each such delivery wait until it is closed, so a test can hold a change mid-delivery.
	HoldChanges chan struct{}
	// Holding, when set, gets one value each time a delivery reaches Hold or HoldChanges and starts to wait, so a
	// test knows a delivery is in flight before it lets go. Give it a buffer for every hold the test reaches: one
	// past it is dropped (reachedHold), never waited on.
	Holding chan struct{}
	// failure is the error every delivery returns while it is set. See FailWith.
	failure atomic.Pointer[error]
	// LoginDelay makes a client report IsLoggedIn()==false until this long after Connect, the way a real
	// network connector does: Connect returns after the socket handshake, and the login only counts once the
	// server's success message is handled. Zero (the default) means logged in at once.
	LoginDelay time.Duration
	// Script, when set, is the login CreateLogin returns for the flow ScriptFlow.
	Script *ScriptedLogin
	// PlainLogins, when set before a login is made, names logins (by ID) whose client is plain, as NewPlain's are,
	// though the network's others take chat changes: a test can tell which login a change was asked of.
	PlainLogins map[string]bool

	plain   bool // the client takes no tags, mutes, unread marks or request accepts
	chatsMu sync.Mutex
	chats   map[string]Chat
	featMu  sync.Mutex // guards Features and loginFeatures after the bridge has started
	// loginFeatures is SetLoginFeatures': what one login's client says, by login ID, over Features.
	loginFeatures map[string]*event.RoomFeatures
	rawMu         sync.Mutex
	raws          []json.RawMessage
	callsMu       sync.Mutex
	calls         []Call
}

func (n *Network) recordCall(c Call) {
	n.callsMu.Lock()
	defer n.callsMu.Unlock()
	n.calls = append(n.calls, c)
}

// Calls returns all group and chat-management calls recorded by the fake network.
func (n *Network) Calls() []Call {
	n.callsMu.Lock()
	defer n.callsMu.Unlock()
	return append([]Call(nil), n.calls...)
}

// ResetCalls clears the recorded group and chat-management calls.
func (n *Network) ResetCalls() {
	n.callsMu.Lock()
	defer n.callsMu.Unlock()
	n.calls = nil
}

// Raws is the content of every message and file delivered so far, in order, as the bridge was handed it when it
// came as JSON (one sent from what was stored, such as a held or scheduled message); nil for an event built in
// memory.
func (n *Network) Raws() []json.RawMessage {
	n.rawMu.Lock()
	defer n.rawMu.Unlock()
	return append([]json.RawMessage(nil), n.raws...)
}

// New is a fake network whose client takes pins (tags), mutes, unread marks and request accepts, as WhatsApp
// takes the first three and Signal the last.
func New() *Network {
	return &Network{
		Sent: make(chan Sent, 16), Files: make(chan File, 16),
		Reactions: make(chan Reaction, 16), Receipts: make(chan Receipt, 16), Typings: make(chan TypingChange, 16),
		Tags: make(chan TagChange, 16), Mutes: make(chan MuteChange, 16),
		Unreads: make(chan UnreadChange, 16), Accepts: make(chan Accept, 16),
		Edits: make(chan Edit, 16), Removes: make(chan Remove, 16), Polls: make(chan Poll, 16),
		Votes: make(chan Vote, 16), Timers: make(chan TimerChange, 16), ReactionRemoves: make(chan Reaction, 16),
		ChatStarts: make(chan ChatStart, 16),
	}
}

// SetFeatures changes what GetCapabilities returns from now on. The bridge only asks again when it makes a room or
// updates a chat's capabilities, so a chat already made keeps its stored features.
func (n *Network) SetFeatures(rf *event.RoomFeatures) {
	n.featMu.Lock()
	defer n.featMu.Unlock()
	n.Features = rf
}

// SetLoginFeatures makes the client of the login loginID alone say rf from now on, whatever Features says: two
// accounts whose chats can do different things, so a test can tell which login's client was asked.
func (n *Network) SetLoginFeatures(loginID string, rf *event.RoomFeatures) {
	n.featMu.Lock()
	defer n.featMu.Unlock()
	if n.loginFeatures == nil {
		n.loginFeatures = map[string]*event.RoomFeatures{}
	}
	n.loginFeatures[loginID] = rf
}

func (n *Network) features(loginID string) *event.RoomFeatures {
	n.featMu.Lock()
	defer n.featMu.Unlock()
	if rf, ok := n.loginFeatures[loginID]; ok {
		return rf
	}
	return n.Features
}

// NewPlain is a fake network whose client takes none of the chat changes New's does, as Google Messages and
// Slack take none.
func NewPlain() *Network {
	n := New()
	n.plain = true
	return n
}

// SetChat says what GetChatInfo reports for chatID from now on.
func (n *Network) SetChat(chatID string, c Chat) {
	n.chatsMu.Lock()
	defer n.chatsMu.Unlock()
	if n.chats == nil {
		n.chats = map[string]Chat{}
	}
	n.chats[chatID] = c
}

func (n *Network) chat(chatID string) Chat {
	n.chatsMu.Lock()
	defer n.chatsMu.Unlock()
	return n.chats[chatID]
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
func (n *Network) CreateLogin(_ context.Context, user *bridgev2.User, flow string) (bridgev2.LoginProcess, error) {
	if flow == ScriptFlow && n.Script != nil {
		n.Script.bind(user)
		return n.Script, nil
	}
	return nil, bridgev2.ErrInvalidLoginFlowID
}

func (n *Network) LoadUserLogin(_ context.Context, login *bridgev2.UserLogin) error {
	c := &client{n: n, login: login}
	plain := n.plain || n.PlainLogins[string(login.ID)]
	switch {
	case plain && n.StartChats == ViaGhost:
		login.Client = &ghostDMClient{c}
	case plain && n.StartChats == ViaIdentifier:
		login.Client = &resolvingClient{c}
	case plain:
		login.Client = c
	case n.StartChats == ViaGhost:
		login.Client = &ghostDMSyncingClient{&syncingClient{c}}
	case n.StartChats == ViaIdentifier:
		login.Client = &resolvingSyncingClient{&syncingClient{c}}
	default:
		login.Client = &syncingClient{c}
	}
	return nil
}

// Login creates the one test login for the local user without any login flow: LoginAs "fake-login", named "Me".
func (n *Network) Login(ctx context.Context, br *bridgev2.Bridge) (*bridgev2.UserLogin, error) {
	return n.LoginAs(ctx, br, "fake-login", "Me")
}

// LoginAs creates a login of the local user with login ID id and remote name name, without any login flow: a second
// account beside Login's, say. Its client is connected, and logged in unless LoginDelay or SetLoggedIn says otherwise.
func (n *Network) LoginAs(ctx context.Context, br *bridgev2.Bridge, id, name string) (*bridgev2.UserLogin, error) {
	user, err := br.GetUserByMXID(ctx, ids.Me)
	if err != nil {
		return nil, err
	}
	login, err := user.NewLogin(ctx, &database.UserLogin{ID: networkid.UserLoginID(id), RemoteName: name}, nil)
	if err != nil {
		return nil, err
	}
	// A network knows its own user, as a real bridge's ghost of the logged-in account: bridgev2 stores a reaction of
	// mine under that sender (reaction_sender_fkey), so taking one back can find it.
	if _, err = br.GetGhostByID(ctx, "me"); err != nil {
		return nil, err
	}
	login.Client.Connect(ctx)
	return login, nil
}

// Incoming queues a remote text message, as if the network had just delivered it, into the login's own chat chatID
// (a portal whose receiver is the login).
func (n *Network) Incoming(login *bridgev2.UserLogin, chatID, senderID, msgID, body string) {
	n.incoming(login, networkid.PortalKey{ID: networkid.PortalID(chatID), Receiver: login.ID}, senderID, msgID, body)
}

func (n *Network) incoming(login *bridgev2.UserLogin, key networkid.PortalKey, senderID, msgID, body string) {
	n.br.QueueRemoteEvent(login, &simplevent.Message[string]{
		EventMeta: simplevent.EventMeta{
			Type: bridgev2.RemoteEventMessage, CreatePortal: true, Timestamp: time.Now(),
			PortalKey: key,
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

// IncomingShared is Incoming into a chat no one login owns: a portal with no receiver, which every login of the
// network shares (as a WhatsApp group is: surprise 8). Its bridge info names no login.
func (n *Network) IncomingShared(login *bridgev2.UserLogin, chatID, senderID, msgID, body string) {
	n.incoming(login, networkid.PortalKey{ID: networkid.PortalID(chatID)}, senderID, msgID, body)
}

// Receipt queues a remote receipt from senderID in chatID for the messages msgIDs (remote IDs, oldest first), as if
// the network had just said so: a read receipt up to the last of them, or with delivered a delivery receipt for each.
// senderID "me" is the network's own user (IsThisUser), as a real bridge's receipt of mine from another device is.
func (n *Network) Receipt(login *bridgev2.UserLogin, chatID, senderID string, msgIDs []string, delivered bool) {
	typ := bridgev2.RemoteEventReadReceipt
	if delivered {
		typ = bridgev2.RemoteEventDeliveryReceipt
	}
	targets := make([]networkid.MessageID, 0, len(msgIDs))
	for _, m := range msgIDs {
		targets = append(targets, networkid.MessageID(m))
	}
	r := &simplevent.Receipt{
		EventMeta: simplevent.EventMeta{
			Type: typ, Timestamp: time.Now(),
			PortalKey: networkid.PortalKey{ID: networkid.PortalID(chatID), Receiver: login.ID},
			Sender:    bridgev2.EventSender{Sender: networkid.UserID(senderID), IsFromMe: senderID == "me"},
		},
		Targets: targets,
	}
	if len(targets) > 0 && !delivered {
		r.LastTarget = targets[len(targets)-1]
	}
	n.br.QueueRemoteEvent(login, r)
}

// Typing queues someone typing in a chat, as if the network had just said so. A timeout of 0 means they stopped.
func (n *Network) Typing(login *bridgev2.UserLogin, chatID, senderID string, timeout time.Duration) {
	n.br.QueueRemoteEvent(login, &simplevent.Typing{
		EventMeta: simplevent.EventMeta{
			Type: bridgev2.RemoteEventTyping, Timestamp: time.Now(),
			PortalKey: networkid.PortalKey{ID: networkid.PortalID(chatID), Receiver: login.ID},
			Sender:    bridgev2.EventSender{Sender: networkid.UserID(senderID)},
		},
		Timeout: timeout, Type: bridgev2.TypingTypeText,
	})
}

type client struct {
	n           *Network
	login       *bridgev2.UserLogin
	connectedAt atomic.Pointer[time.Time]
	// forced is SetLoggedIn's answer for IsLoggedIn: 0 while it was never called, 1 logged in, 2 not.
	forced atomic.Int32
}

// SetLoggedIn makes login's client report IsLoggedIn() on (whatever LoginDelay says) from now on, and then sends the
// login's bridge state through bridgev2, as a real connector does when its connection comes and goes: CONNECTED when
// on, TRANSIENT_DISCONNECT when off. The state reaches the store (a "bridge" change), so a test drives a connection
// change instead of waiting for one. A login whose client isn't this network's is left alone.
func (n *Network) SetLoggedIn(login *bridgev2.UserLogin, on bool) {
	b, ok := login.Client.(interface{ base() *client })
	if !ok {
		return
	}
	c := b.base()
	state := status.StateTransientDisconnect
	if on {
		c.forced.Store(1)
		state = status.StateConnected
	} else {
		c.forced.Store(2)
	}
	login.BridgeState.Send(status.BridgeState{StateEvent: state})
}

var _ bridgev2.NetworkAPI = (*client)(nil)

// base is the plain client under every kind of this network's client.
func (c *client) base() *client { return c }

func (c *client) Connect(context.Context) {
	now := time.Now()
	c.connectedAt.Store(&now)
}
func (c *client) Disconnect() { c.connectedAt.Store(nil) }
func (c *client) IsLoggedIn() bool {
	switch c.forced.Load() {
	case 1:
		return true
	case 2:
		return false
	}
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

func (c *client) GetChatInfo(_ context.Context, portal *bridgev2.Portal) (*bridgev2.ChatInfo, error) {
	if c.n.ChatInfoErr != nil {
		return nil, c.n.ChatInfoErr
	}
	name := "Fake chat"
	ch := c.n.chat(string(portal.ID))
	if ch.Name != nil {
		name = *ch.Name
	}
	info := &bridgev2.ChatInfo{Name: &name}
	if ch.Tag != nil || ch.MutedUntil != nil {
		info.UserLocal = &bridgev2.UserLocalPortalInfo{Tag: ch.Tag, MutedUntil: ch.MutedUntil}
	}
	info.MessageRequest = ch.MessageRequest
	if ch.Direct != nil && *ch.Direct {
		dm := database.RoomTypeDM
		info.Type = &dm
	}
	if ch.Members != nil {
		info.Members = c.members(ch.Members...)
		info.Members.IsFull = true
		if ch.Direct != nil && *ch.Direct && len(ch.Members) == 1 {
			info.Members.OtherUserID = networkid.UserID(ch.Members[0])
		}
	} else {
		level := 50
		info.Members = &bridgev2.ChatMemberList{
			MemberMap: bridgev2.ChatMemberMap{
				"": {
					EventSender: bridgev2.EventSender{IsFromMe: true, SenderLogin: c.login.ID},
					Membership:  event.MembershipJoin,
					PowerLevel:  &level,
				},
			},
			PowerLevels: &bridgev2.PowerLevelOverrides{
				Invite:       &level,
				Kick:         &level,
				StateDefault: &level,
			},
		}
	}
	return info, nil
}

// members is a member list of people (network IDs) and me, all joined.
func (c *client) members(people ...string) *bridgev2.ChatMemberList {
	level := 50
	m := bridgev2.ChatMemberMap{}.Set(bridgev2.ChatMember{
		EventSender: bridgev2.EventSender{Sender: "me", IsFromMe: true, SenderLogin: c.login.ID},
		Membership:  event.MembershipJoin,
		PowerLevel:  &level,
	})
	for _, p := range people {
		m.Set(bridgev2.ChatMember{EventSender: bridgev2.EventSender{Sender: networkid.UserID(p)}, Membership: event.MembershipJoin})
	}
	return &bridgev2.ChatMemberList{
		MemberMap: m,
		PowerLevels: &bridgev2.PowerLevelOverrides{
			Invite:       &level,
			Kick:         &level,
			StateDefault: &level,
		},
	}
}

func (c *client) GetUserInfo(context.Context, *bridgev2.Ghost) (*bridgev2.UserInfo, error) {
	return &bridgev2.UserInfo{}, nil
}

// GetCapabilities is what SetLoginFeatures set for this client's login, else Network.Features when set. Otherwise
// the fake network takes every kind of file, replies and reactions, and wants read receipts.
func (c *client) GetCapabilities(context.Context, *bridgev2.Portal) *event.RoomFeatures {
	if rf := c.n.features(string(c.login.ID)); rf != nil {
		return rf
	}
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
	_ bridgev2.ReadReceiptHandlingNetworkAPI    = (*client)(nil)
	_ bridgev2.TypingHandlingNetworkAPI         = (*client)(nil)
	_ bridgev2.ReactionHandlingNetworkAPI       = (*client)(nil)
	_ bridgev2.EditHandlingNetworkAPI           = (*client)(nil)
	_ bridgev2.RedactionHandlingNetworkAPI      = (*client)(nil)
	_ bridgev2.PollHandlingNetworkAPI           = (*client)(nil)
	_ bridgev2.DisappearTimerChangingNetworkAPI = (*client)(nil)
	_ bridgev2.RoomNameHandlingNetworkAPI       = (*client)(nil)
	_ bridgev2.RoomTopicHandlingNetworkAPI      = (*client)(nil)
	_ bridgev2.RoomAvatarHandlingNetworkAPI     = (*client)(nil)
	_ bridgev2.MembershipHandlingNetworkAPI     = (*client)(nil)
	_ bridgev2.PowerLevelHandlingNetworkAPI     = (*client)(nil)
	_ bridgev2.DeleteChatHandlingNetworkAPI     = (*client)(nil)
)

// hold waits out Network.Hold, if a test set one.
func (c *client) hold(ctx context.Context) error {
	if c.n.Hold == nil {
		return nil
	}
	c.n.reachedHold()
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
	c.n.rawMu.Lock()
	c.n.raws = append(c.n.raws, msg.Event.Content.VeryRaw)
	c.n.rawMu.Unlock()
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
	return sentMessage(msg.Event), nil
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

// HandleMatrixTyping records my typing, as bridgev2 hands it over.
func (c *client) HandleMatrixTyping(_ context.Context, msg *bridgev2.MatrixTyping) error {
	select {
	case c.n.Typings <- TypingChange{PortalID: string(msg.Portal.ID), Typing: msg.IsTyping}:
		return nil
	default:
		return errors.New("fakenet: Typings buffer is full")
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

func (c *client) HandleMatrixReactionRemove(_ context.Context, msg *bridgev2.MatrixReactionRemove) error {
	r := Reaction{
		PortalID: string(msg.Portal.ID), TargetID: string(msg.TargetReaction.MessageID), Emoji: msg.TargetReaction.Emoji,
	}
	return deliver(c.n, c.n.ReactionRemoves, r, "ReactionRemoves")
}

// syncingClient is the client of a network made with New: the plain client plus the four chat-change interfaces.
type syncingClient struct{ *client }

var (
	_ bridgev2.TagHandlingNetworkAPI             = (*syncingClient)(nil)
	_ bridgev2.MuteHandlingNetworkAPI            = (*syncingClient)(nil)
	_ bridgev2.MarkedUnreadHandlingNetworkAPI    = (*syncingClient)(nil)
	_ bridgev2.MessageRequestAcceptingNetworkAPI = (*syncingClient)(nil)
)

// errRefused is what a network with Refuse set answers.
var errRefused = errors.New("fakenet: the network refused the change")

// reachedHold tells Holding, if set, that a delivery has reached a hold. It never waits: with Holding's buffer full
// the signal is dropped, so a test that holds more deliveries than it sized Holding for fails at its own wait (recv's
// timeout) rather than leaving the bridge's goroutine stuck here and the test hanging.
func (n *Network) reachedHold() {
	if n.Holding == nil {
		return
	}
	select {
	case n.Holding <- struct{}{}:
	default:
	}
}

// deliver puts v on ch, unless the network refuses or nobody is draining ch.
func deliver[T any](n *Network, ch chan T, v T, what string) error {
	if n.HoldChanges != nil {
		n.reachedHold()
		<-n.HoldChanges
	}
	if n.Refuse {
		return errRefused
	}
	select {
	case ch <- v:
		return nil
	default:
		return errors.New("fakenet: " + what + " buffer is full")
	}
}

func (c *syncingClient) HandleRoomTag(_ context.Context, msg *bridgev2.MatrixRoomTag) error {
	tags := []event.RoomTag{}
	for t := range msg.Content.Tags {
		tags = append(tags, t)
	}
	sort.Slice(tags, func(i, j int) bool { return tags[i] < tags[j] })
	return deliver(c.n, c.n.Tags, TagChange{PortalID: string(msg.Portal.ID), Tags: tags}, "Tags")
}

func (c *syncingClient) HandleMute(_ context.Context, msg *bridgev2.MatrixMute) error {
	return deliver(c.n, c.n.Mutes, MuteChange{PortalID: string(msg.Portal.ID), MutedUntil: msg.Content.MutedUntil}, "Mutes")
}

func (c *syncingClient) HandleMarkedUnread(_ context.Context, msg *bridgev2.MatrixMarkedUnread) error {
	return deliver(c.n, c.n.Unreads, UnreadChange{PortalID: string(msg.Portal.ID), Unread: msg.Content.Unread}, "Unreads")
}

func (c *syncingClient) HandleMatrixAcceptMessageRequest(_ context.Context, msg *bridgev2.MatrixAcceptMessageRequest) error {
	return deliver(c.n, c.n.Accepts, Accept{PortalID: string(msg.Portal.ID)}, "Accepts")
}

// sentMessage is the network's answer to a message it took: the remote ID it gives the message.
func sentMessage(evt *event.Event) *bridgev2.MatrixMessageResponse {
	return &bridgev2.MatrixMessageResponse{DB: &database.Message{
		ID:       networkid.MessageID("out-" + string(evt.ID)),
		SenderID: "me", Timestamp: time.Now(),
	}}
}

func (c *client) HandleMatrixEdit(_ context.Context, msg *bridgev2.MatrixEdit) error {
	return deliver(c.n, c.n.Edits, Edit{
		PortalID: string(msg.Portal.ID), TargetID: string(msg.EditTarget.ID), Body: msg.Content.Body,
	}, "Edits")
}

func (c *client) HandleMatrixMessageRemove(_ context.Context, msg *bridgev2.MatrixMessageRemove) error {
	return deliver(c.n, c.n.Removes, Remove{PortalID: string(msg.Portal.ID), TargetID: string(msg.TargetMessage.ID)}, "Removes")
}

func (c *client) HandleMatrixPollStart(_ context.Context, msg *bridgev2.MatrixPollStart) (*bridgev2.MatrixMessageResponse, error) {
	p := Poll{
		PortalID: string(msg.Portal.ID), Question: msg.Content.PollStart.Question.GetText(),
		Options: []string{}, MaxSelections: msg.Content.PollStart.MaxSelections,
	}
	for _, o := range msg.Content.PollStart.Answers {
		p.Options = append(p.Options, o.GetText())
	}
	if err := deliver(c.n, c.n.Polls, p, "Polls"); err != nil {
		return nil, err
	}
	return sentMessage(msg.Event), nil
}

func (c *client) HandleMatrixPollVote(_ context.Context, msg *bridgev2.MatrixPollVote) (*bridgev2.MatrixMessageResponse, error) {
	v := Vote{PortalID: string(msg.Portal.ID), PollID: string(msg.VoteTo.ID), Answers: append([]string{}, msg.Content.Response.Answers...)}
	if err := deliver(c.n, c.n.Votes, v, "Votes"); err != nil {
		return nil, err
	}
	return sentMessage(msg.Event), nil
}

// HandleMatrixDisappearingTimer records the change and, as a real network does once it has taken it, sets the
// portal's timer.
func (c *client) HandleMatrixDisappearingTimer(ctx context.Context, msg *bridgev2.MatrixDisappearingTimer) (bool, error) {
	tc := TimerChange{PortalID: string(msg.Portal.ID), Type: msg.Content.Type, Timer: msg.Content.Timer.Duration}
	if err := deliver(c.n, c.n.Timers, tc, "Timers"); err != nil {
		return false, err
	}
	if c.n.EchoTimers {
		timer := msg.Content.Timer.Duration
		typ := msg.Content.Type
		if timer == 0 {
			typ = event.DisappearingTypeNone
		}
		_, err := msg.Portal.Bridge.Bot.SendMessage(ctx, msg.Portal.MXID, event.EventMessage, &event.Content{
			Parsed: bridgev2.DisappearingMessageNotice(timer, false),
			Raw: map[string]any{"com.beeper.action_message": map[string]any{
				"type": "disappearing_timer", "timer": timer.Milliseconds(), "timer_type": typ, "implicit": false,
			}},
		}, &bridgev2.MatrixSendExtra{Timestamp: time.UnixMilli(msg.Event.Timestamp)})
		if err != nil {
			return false, err
		}
	}
	msg.Portal.Disappear = database.DisappearingSetting{Type: msg.Content.Type, Timer: msg.Content.Timer.Duration}
	if msg.Portal.Disappear.Timer == 0 {
		msg.Portal.Disappear.Type = event.DisappearingTypeNone
	}
	return true, nil
}

func (c *client) HandleMatrixRoomName(_ context.Context, msg *bridgev2.MatrixRoomName) (bool, error) {
	if c.n.Refuse {
		return false, errRefused
	}
	if err := c.n.failed(); err != nil {
		return false, err
	}
	c.n.recordCall(Call{Method: "HandleMatrixRoomName", PortalID: string(msg.Portal.ID), Value: msg.Content.Name})
	return true, nil
}

func (c *client) HandleMatrixRoomTopic(_ context.Context, msg *bridgev2.MatrixRoomTopic) (bool, error) {
	if c.n.Refuse {
		return false, errRefused
	}
	if err := c.n.failed(); err != nil {
		return false, err
	}
	c.n.recordCall(Call{Method: "HandleMatrixRoomTopic", PortalID: string(msg.Portal.ID), Value: msg.Content.Topic})
	return true, nil
}

func (c *client) HandleMatrixRoomAvatar(_ context.Context, msg *bridgev2.MatrixRoomAvatar) (bool, error) {
	if c.n.Refuse {
		return false, errRefused
	}
	if err := c.n.failed(); err != nil {
		return false, err
	}
	c.n.recordCall(Call{Method: "HandleMatrixRoomAvatar", PortalID: string(msg.Portal.ID), Value: string(msg.Content.URL)})
	return true, nil
}

func (c *client) HandleMatrixMembership(_ context.Context, msg *bridgev2.MatrixMembershipChange) (*bridgev2.MatrixMembershipResult, error) {
	if c.n.Refuse {
		return nil, errRefused
	}
	if err := c.n.failed(); err != nil {
		return nil, err
	}
	target := msg.Event.GetStateKey()
	c.n.recordCall(Call{Method: "HandleMatrixMembership", PortalID: string(msg.Portal.ID), Target: target, Value: string(msg.Type.To)})
	return &bridgev2.MatrixMembershipResult{}, nil
}

func (c *client) HandleMatrixPowerLevels(_ context.Context, msg *bridgev2.MatrixPowerLevelChange) (bool, error) {
	if c.n.Refuse {
		return false, errRefused
	}
	if err := c.n.failed(); err != nil {
		return false, err
	}
	var target, val string
	for u, ch := range msg.Users {
		target = string(u)
		val = strconv.Itoa(ch.NewLevel)
		break
	}
	c.n.recordCall(Call{Method: "HandleMatrixPowerLevels", PortalID: string(msg.Portal.ID), Target: target, Value: val})
	return true, nil
}

func (c *client) HandleMatrixDeleteChat(_ context.Context, msg *bridgev2.MatrixDeleteChat) error {
	if c.n.Refuse {
		return errRefused
	}
	if err := c.n.failed(); err != nil {
		return err
	}
	c.n.recordCall(Call{Method: "HandleMatrixDeleteChat", PortalID: string(msg.Portal.ID)})
	return nil
}

// The clients that start one-to-one chats (StartChats), over the plain client and the syncing one.
type (
	ghostDMClient          struct{ *client }
	resolvingClient        struct{ *client }
	ghostDMSyncingClient   struct{ *syncingClient }
	resolvingSyncingClient struct{ *syncingClient }
)

var (
	_ bridgev2.GhostDMCreatingNetworkAPI     = (*ghostDMClient)(nil)
	_ bridgev2.GhostDMCreatingNetworkAPI     = (*ghostDMSyncingClient)(nil)
	_ bridgev2.IdentifierResolvingNetworkAPI = (*resolvingClient)(nil)
	_ bridgev2.IdentifierResolvingNetworkAPI = (*resolvingSyncingClient)(nil)
	_ bridgev2.ContactListingNetworkAPI      = (*client)(nil)
	_ bridgev2.UserSearchingNetworkAPI       = (*ghostDMClient)(nil)
	_ bridgev2.UserSearchingNetworkAPI       = (*ghostDMSyncingClient)(nil)
	_ bridgev2.UserSearchingNetworkAPI       = (*resolvingClient)(nil)
	_ bridgev2.UserSearchingNetworkAPI       = (*resolvingSyncingClient)(nil)
	_ bridgev2.GroupCreatingNetworkAPI       = (*ghostDMClient)(nil)
	_ bridgev2.GroupCreatingNetworkAPI       = (*ghostDMSyncingClient)(nil)
	_ bridgev2.GroupCreatingNetworkAPI       = (*resolvingClient)(nil)
	_ bridgev2.GroupCreatingNetworkAPI       = (*resolvingSyncingClient)(nil)
)

func (c *ghostDMClient) CreateChatWithGhost(ctx context.Context, g *bridgev2.Ghost) (*bridgev2.CreateChatResponse, error) {
	return c.startChat(ctx, string(g.ID), ViaGhost)
}

func (c *ghostDMClient) ResolveIdentifier(ctx context.Context, identifier string, create bool) (*bridgev2.ResolveIdentifierResponse, error) {
	return c.resolve(ctx, identifier, create)
}

func (c *resolvingClient) ResolveIdentifier(ctx context.Context, identifier string, create bool) (*bridgev2.ResolveIdentifierResponse, error) {
	return c.resolve(ctx, identifier, create)
}

func (c *ghostDMSyncingClient) CreateChatWithGhost(ctx context.Context, g *bridgev2.Ghost) (*bridgev2.CreateChatResponse, error) {
	return c.startChat(ctx, string(g.ID), ViaGhost)
}

func (c *ghostDMSyncingClient) ResolveIdentifier(ctx context.Context, identifier string, create bool) (*bridgev2.ResolveIdentifierResponse, error) {
	return c.resolve(ctx, identifier, create)
}

func (c *resolvingSyncingClient) ResolveIdentifier(ctx context.Context, identifier string, create bool) (*bridgev2.ResolveIdentifierResponse, error) {
	return c.resolve(ctx, identifier, create)
}

func (c *client) contactToResponse(ctx context.Context, ct Contact) (*bridgev2.ResolveIdentifierResponse, error) {
	uid := networkid.UserID(ct.UserID)
	g, err := c.n.br.GetGhostByID(ctx, uid)
	if err != nil {
		return nil, err
	}
	name := ct.Name
	idsCopy := append([]string(nil), ct.Identifiers...)
	ui := &bridgev2.UserInfo{
		Name:        &name,
		Identifiers: append([]string(nil), ct.Identifiers...),
	}
	if ct.AvatarURL != "" {
		g.AvatarMXC = ct.AvatarURL
	}
	g.UpdateInfo(ctx, ui)
	ui.Identifiers = idsCopy
	return &bridgev2.ResolveIdentifierResponse{
		Ghost:    g,
		UserID:   uid,
		UserInfo: ui,
	}, nil
}

func (c *client) GetContactList(ctx context.Context) ([]*bridgev2.ResolveIdentifierResponse, error) {
	if c.n.Refuse {
		return nil, errRefused
	}
	if err := c.n.failed(); err != nil {
		return nil, err
	}
	out := make([]*bridgev2.ResolveIdentifierResponse, 0, len(c.n.Contacts))
	for _, ct := range c.n.Contacts {
		r, err := c.contactToResponse(ctx, ct)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, nil
}

func (c *client) SearchUsers(ctx context.Context, _ string) ([]*bridgev2.ResolveIdentifierResponse, error) {
	if c.n.Refuse {
		return nil, errRefused
	}
	if err := c.n.failed(); err != nil {
		return nil, err
	}
	out := make([]*bridgev2.ResolveIdentifierResponse, 0, len(c.n.SearchResults))
	for _, ct := range c.n.SearchResults {
		r, err := c.contactToResponse(ctx, ct)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, nil
}

func (c *client) CreateGroup(_ context.Context, params *bridgev2.GroupCreateParams) (*bridgev2.CreateChatResponse, error) {
	if c.n.Refuse {
		return nil, errRefused
	}
	if c.n.ChatStartErr != nil {
		return nil, c.n.ChatStartErr
	}
	if err := c.n.failed(); err != nil {
		return nil, err
	}
	name := "Fake group"
	if params != nil && params.Name != nil && params.Name.Name != "" {
		name = params.Name.Name
	}
	var people []string
	if params != nil {
		for _, p := range params.Participants {
			people = append(people, string(p))
		}
	}
	chatID := "group-" + name
	direct := false
	c.n.SetChat(chatID, Chat{Name: &name, Direct: &direct, Members: people})
	c.n.recordCall(Call{Method: "CreateGroup", PortalID: chatID, Value: name})
	grpType := database.RoomTypeDefault
	members := c.members(people...)
	members.IsFull = true
	resp := &bridgev2.CreateChatResponse{
		PortalKey: networkid.PortalKey{ID: networkid.PortalID(chatID), Receiver: c.login.ID},
	}
	if c.n.ChatInfoErr == nil && !c.n.OmitPortalInfo {
		resp.PortalInfo = &bridgev2.ChatInfo{Name: &name, Type: &grpType, Members: members}
	}
	return resp, nil
}

// resolve is ResolveIdentifier: every identifier is a person of the network's, named by their network ID; with create
// it starts the one-to-one chat with them (startChat).
func (c *client) resolve(ctx context.Context, identifier string, create bool) (*bridgev2.ResolveIdentifierResponse, error) {
	if c.n.ChatStartErr != nil {
		return nil, c.n.ChatStartErr
	}
	g, err := c.n.br.GetGhostByID(ctx, networkid.UserID(identifier))
	if err != nil {
		return nil, err
	}
	resp := &bridgev2.ResolveIdentifierResponse{Ghost: g, UserID: networkid.UserID(identifier)}
	if create {
		if resp.Chat, err = c.startChat(ctx, identifier, ViaIdentifier); err != nil {
			return nil, err
		}
	}
	return resp, nil
}

// startChat records the start on ChatStarts (refused while Refuse is set, held by HoldChanges) and answers the
// login's own one-to-one chat with userID (DirectChatID), as a network does: the person and me as its members.
func (c *client) startChat(_ context.Context, userID string, via StartChats) (*bridgev2.CreateChatResponse, error) {
	if c.n.ChatStartErr != nil {
		return nil, c.n.ChatStartErr
	}
	if err := deliver(c.n, c.n.ChatStarts, ChatStart{LoginID: string(c.login.ID), UserID: userID, Via: via}, "ChatStarts"); err != nil {
		return nil, err
	}
	chatID := DirectChatID(userID)
	direct := true
	existing := c.n.chat(chatID)
	existing.Direct = &direct
	if existing.Members == nil {
		existing.Members = []string{userID}
	}
	c.n.SetChat(chatID, existing) // the network knows the chat now
	name := "Fake chat"
	if existing.Name != nil {
		name = *existing.Name
	}
	dm := database.RoomTypeDM
	members := c.members(userID)
	members.IsFull, members.OtherUserID = true, networkid.UserID(userID)
	resp := &bridgev2.CreateChatResponse{PortalKey: networkid.PortalKey{ID: networkid.PortalID(chatID), Receiver: c.login.ID}}
	if c.n.ChatInfoErr == nil && !c.n.OmitPortalInfo {
		resp.PortalInfo = &bridgev2.ChatInfo{Name: &name, Type: &dm, Members: members}
	}
	return resp, nil
}
