// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package networks

import (
	"context"
	"fmt"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	gmessages "go.mau.fi/mautrix-gmessages/pkg/connector"
	"go.mau.fi/mautrix-gmessages/pkg/libgm"
	"go.mau.fi/mautrix-gmessages/pkg/libgm/gmproto"
	"google.golang.org/protobuf/proto"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/host"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/media"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/store"
)

// These tests cover tools/go_deps/mautrix-gmessages-nested-conversation-ids.patch, through the pinned bridge's own
// code paths: an update is encrypted as the phone would, handed to libgm's client (Client.HandleRPCMsg, the way a
// long poll delivers it), and what comes out is what the bridge would have acted on.

const gmAccount = "account-a"

type gmWorld struct {
	h     *host.Host
	s     *store.Store
	login *bridgev2.UserLogin
	gc    *gmessages.GMClient
}

// newGMWorld starts a Google Messages bridge on a temporary directory with no login, then adds one for an account
// with fresh keys. The login is loaded, not connected: nothing reaches Google.
func newGMWorld(t *testing.T) *gmWorld {
	t.Helper()
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	h, err := host.Start(ctx, dir, "gmessages", s, &media.Store{Dir: filepath.Join(dir, "media")}, &gmessages.GMConnector{}, zerolog.Nop())
	require.NoError(t, err)
	t.Cleanup(h.Stop)
	w := &gmWorld{h: h, s: s}
	user, err := h.Me(ctx)
	require.NoError(t, err)
	w.login, err = user.NewLogin(ctx, &database.UserLogin{
		ID:         gmAccount,
		RemoteName: "Account A",
		Metadata:   &gmessages.UserLoginMetadata{Session: libgm.NewAuthData(), IDPrefix: "1"},
	}, nil)
	require.NoError(t, err)
	w.gc = w.login.Client.(*gmessages.GMClient)
	require.NotNil(t, w.gc.Client)
	return w
}

// reload makes the login's client again, as a start does: it reads the phone number mappings the database holds.
func (w *gmWorld) reload(t *testing.T) {
	t.Helper()
	require.NoError(t, w.h.Bridge.Network.LoadUserLogin(context.Background(), w.login))
	w.gc = w.login.Client.(*gmessages.GMClient)
}

// deliver hands libgm an update (or response) of the given action, encrypted with the login's own keys.
func (w *gmWorld) deliver(t *testing.T, payload proto.Message) {
	t.Helper()
	plain, err := proto.Marshal(payload)
	require.NoError(t, err)
	enc, err := w.gc.Client.AuthData.RequestCrypto.Encrypt(plain)
	require.NoError(t, err)
	data, err := proto.Marshal(&gmproto.RPCMessageData{Action: gmproto.ActionType_GET_UPDATES, EncryptedData: enc})
	require.NoError(t, err)
	w.gc.Client.HandleRPCMsg(&gmproto.IncomingRPCMessage{
		ResponseID: fmt.Sprintf("response-%d", time.Now().UnixNano()), BugleRoute: gmproto.BugleRoute_DataEvent, MessageData: data,
	})
}

// capture replaces the bridge's handler with one that records what libgm would have handed it.
func (w *gmWorld) capture() *capturedEvents {
	c := &capturedEvents{}
	w.gc.Client.SetEventHandler(func(evt any) {
		c.mu.Lock()
		defer c.mu.Unlock()
		c.events = append(c.events, evt)
	})
	return c
}

type capturedEvents struct {
	mu     sync.Mutex
	events []any
}

func (c *capturedEvents) all() []any {
	c.mu.Lock()
	defer c.mu.Unlock()
	return append([]any(nil), c.events...)
}

func messageUpdate(msgs ...*gmproto.Message) *gmproto.UpdateEvents {
	return &gmproto.UpdateEvents{Event: &gmproto.UpdateEvents_MessageEvent{MessageEvent: &gmproto.MessageEvent{Data: msgs}}}
}

func conversationUpdate(convs ...*gmproto.Conversation) *gmproto.UpdateEvents {
	return &gmproto.UpdateEvents{Event: &gmproto.UpdateEvents_ConversationEvent{ConversationEvent: &gmproto.ConversationEvent{Data: convs}}}
}

// directConversation is a one-to-one chat with number as a conversation update carries it; id is where the
// conversation ID is (top-level, or nested only).
func directConversation(id, nestedID, number string, lastMessageMicros int64) *gmproto.Conversation {
	conv := &gmproto.Conversation{
		ConversationID:       id,
		Status:               gmproto.ConversationStatus_ACTIVE,
		LastMessageTimestamp: lastMessageMicros,
		LatestMessageID:      "",
		Participants: []*gmproto.Participant{
			{ID: &gmproto.SmallInfo{Type: gmproto.IdentifierType_PHONE, Number: "+15550000001", ParticipantID: "1"}, IsMe: true, IsVisible: true},
			{ID: &gmproto.SmallInfo{Type: gmproto.IdentifierType_PHONE, Number: number, ParticipantID: "2"}, IsVisible: true},
		},
	}
	if nestedID != "" {
		conv.SomeKindOfGroupID = &gmproto.SomeKindOfGroupID{ConversationID: nestedID, MaybePhoneNumber: number}
	}
	return conv
}

// Google sends some messages with the top-level IDs empty and the real ones nested (field 23 has the conversation ID,
// field 24 the message ID). They must reach the bridge as the chat "1.81" and the message "1.49976", not as "1." and
// "1.", where every such message becomes one chat and overwrites the one before it.
func TestGoogleMessagesMessageWithOnlyNestedIDsIsRoutedByThem(t *testing.T) {
	w := newGMWorld(t)
	got := w.capture()

	w.deliver(t, messageUpdate(
		&gmproto.Message{
			SomeKindOfGroupID: &gmproto.SomeKindOfGroupID{ConversationID: "81", MaybePhoneNumber: "+15550000081"},
			AnotherMessageID:  &gmproto.AnotherMessageID{MessageID: "49976"},
			MessageStatus:     &gmproto.MessageStatus{Status: gmproto.MessageStatusType_INCOMING_COMPLETE},
			ParticipantID:     "2", Timestamp: 1000,
		},
		&gmproto.Message{
			SomeKindOfGroupID: &gmproto.SomeKindOfGroupID{ConversationID: "81"},
			AnotherMessageID:  &gmproto.AnotherMessageID{MessageID: "49977"},
			MessageStatus:     &gmproto.MessageStatus{Status: gmproto.MessageStatusType_INCOMING_COMPLETE},
			ParticipantID:     "2", Timestamp: 2000,
		},
		// IDs at the top level are used as they are, whatever the nested ones say.
		&gmproto.Message{
			MessageID: "50000", ConversationID: "82",
			SomeKindOfGroupID: &gmproto.SomeKindOfGroupID{ConversationID: "other"},
			AnotherMessageID:  &gmproto.AnotherMessageID{MessageID: "other"},
			MessageStatus:     &gmproto.MessageStatus{Status: gmproto.MessageStatusType_INCOMING_COMPLETE},
			ParticipantID:     "2", Timestamp: 3000,
		},
	))

	events := got.all()
	require.Len(t, events, 3)
	first, second, third := events[0].(*libgm.WrappedMessage), events[1].(*libgm.WrappedMessage), events[2].(*libgm.WrappedMessage)
	require.Equal(t, networkid.PortalKey{ID: "1.81", Receiver: gmAccount}, w.gc.MakePortalKey(first.ConversationID))
	require.Equal(t, networkid.MessageID("1.49976"), w.gc.MakeMessageID(first.MessageID))
	require.Equal(t, networkid.PortalKey{ID: "1.81", Receiver: gmAccount}, w.gc.MakePortalKey(second.ConversationID))
	require.Equal(t, networkid.MessageID("1.49977"), w.gc.MakeMessageID(second.MessageID), "two messages are two messages")
	require.Equal(t, networkid.PortalKey{ID: "1.82", Receiver: gmAccount}, w.gc.MakePortalKey(third.ConversationID))
	require.Equal(t, networkid.MessageID("1.50000"), w.gc.MakeMessageID(third.MessageID))
}

// A conversation update's nested IDs are used the same way (the conversation ID in field 31, the latest message ID in
// field 35), and so are a typing notice's.
func TestGoogleMessagesConversationAndTypingWithOnlyNestedIDsAreRoutedByThem(t *testing.T) {
	w := newGMWorld(t)
	got := w.capture()
	conv := directConversation("", "81", "+15550000081", 5)
	conv.LatestMessageAnotherID = &gmproto.AnotherMessageID{MessageID: "49976"}

	w.deliver(t, conversationUpdate(conv))
	w.deliver(t, &gmproto.UpdateEvents{Event: &gmproto.UpdateEvents_TypingEvent{TypingEvent: &gmproto.TypingEvent{
		Data: &gmproto.TypingData{SomeKindOfGroupID: &gmproto.SomeKindOfGroupID{ConversationID: "81"}, User: &gmproto.User{Number: "+15550000081"}},
	}}})

	events := got.all()
	require.Len(t, events, 2)
	require.Equal(t, "81", events[0].(*gmproto.Conversation).ConversationID)
	require.Equal(t, "49976", events[0].(*gmproto.Conversation).LatestMessageID)
	require.Equal(t, "81", events[1].(*gmproto.TypingData).ConversationID)
}

// The same fallback for the responses the bridge asks the phone for: the conversation list, one conversation, the
// messages of a chat (backfill).
func TestFillMissingIDsCoversResponsesToo(t *testing.T) {
	list := &gmproto.ListConversationsResponse{Conversations: []*gmproto.Conversation{
		directConversation("", "81", "+15550000081", 1), directConversation("90", "", "+15550000090", 1),
	}}
	libgm.FillMissingIDs(list)
	require.Equal(t, "81", list.Conversations[0].ConversationID)
	require.Equal(t, "90", list.Conversations[1].ConversationID)

	one := &gmproto.GetConversationResponse{Conversation: directConversation("", "81", "+15550000081", 1)}
	libgm.FillMissingIDs(one)
	require.Equal(t, "81", one.Conversation.ConversationID)

	made := &gmproto.GetOrCreateConversationResponse{Conversation: directConversation("", "81", "+15550000081", 1)}
	libgm.FillMissingIDs(made)
	require.Equal(t, "81", made.Conversation.ConversationID)

	msgs := &gmproto.ListMessagesResponse{Messages: []*gmproto.Message{{
		SomeKindOfGroupID: &gmproto.SomeKindOfGroupID{ConversationID: "81"},
		AnotherMessageID:  &gmproto.AnotherMessageID{MessageID: "49976"},
	}}}
	libgm.FillMissingIDs(msgs)
	require.Equal(t, "81", msgs.Messages[0].ConversationID)
	require.Equal(t, "49976", msgs.Messages[0].MessageID)

	libgm.FillMissingIDs(nil) // nothing to fill: no panic
	libgm.FillMissingIDs(&gmproto.UpdateEvents{})
	libgm.FillMissingIDs(&gmproto.ListMessagesResponse{Messages: []*gmproto.Message{nil}})
}

// An update that has no conversation ID even in its nested fields (or a message with no message ID) is dropped, and
// the bridge, with its own handler in place, makes no chat for it: no portal "1." and no phone number mapped to it.
func TestGoogleMessagesEventsWithNoIDsAnywhereAreDroppedAndMakeNoChat(t *testing.T) {
	ctx := context.Background()
	t.Run("libgm drops them", func(t *testing.T) {
		w := newGMWorld(t)
		got := w.capture()
		w.deliver(t, messageUpdate(
			&gmproto.Message{MessageStatus: &gmproto.MessageStatus{Status: gmproto.MessageStatusType_INCOMING_COMPLETE}, Timestamp: 1},
			&gmproto.Message{ConversationID: "81", MessageStatus: &gmproto.MessageStatus{Status: gmproto.MessageStatusType_INCOMING_COMPLETE}, Timestamp: 2},
			&gmproto.Message{MessageID: "7", MessageStatus: &gmproto.MessageStatus{Status: gmproto.MessageStatusType_INCOMING_COMPLETE}, Timestamp: 3},
			&gmproto.Message{MessageID: "8", ConversationID: "81", MessageStatus: &gmproto.MessageStatus{Status: gmproto.MessageStatusType_INCOMING_COMPLETE}, Timestamp: 4},
		))
		w.deliver(t, conversationUpdate(directConversation("", "", "+15550000081", 5)))
		w.deliver(t, &gmproto.UpdateEvents{Event: &gmproto.UpdateEvents_TypingEvent{TypingEvent: &gmproto.TypingEvent{Data: &gmproto.TypingData{}}}})
		events := got.all()
		require.Len(t, events, 1, "only the message that has both IDs gets through")
		require.Equal(t, "8", events[0].(*libgm.WrappedMessage).MessageID)
	})
	t.Run("the bridge makes no chat", func(t *testing.T) {
		w := newGMWorld(t)
		// The bridge's own handler is in place. The phone number is a contact's that the bridge maps to a chat when
		// it knows the conversation: here it doesn't, and must not map it to "1.".
		w.deliver(t, conversationUpdate(directConversation("", "", "+15550000081", time.Now().UnixMicro())))
		w.deliver(t, messageUpdate(&gmproto.Message{
			MessageStatus: &gmproto.MessageStatus{Status: gmproto.MessageStatusType_OUTGOING_COMPLETE}, Timestamp: time.Now().UnixMicro(),
		}))
		time.Sleep(500 * time.Millisecond) // a chat would be made by a goroutine of the bridge's
		portals, err := w.h.Bridge.DB.Portal.GetAll(ctx)
		require.NoError(t, err)
		require.Empty(t, portals, "no chat, least of all one named \"1.\"")
		var n int
		require.NoError(t, w.h.Bridge.DB.QueryRow(ctx, "SELECT COUNT(*) FROM gmessages_direct_conversation").Scan(&n))
		require.Zero(t, n, "and no phone number mapped to one")
	})
}

// seedChat puts a one-to-one chat in the bridge database and the store: its portal row on its room, the room, and the
// phone number mapped to it (the mapping of what the phone says, and a login that exists: the mapping has a foreign
// key on it).
func (w *gmWorld) seedChat(t *testing.T, portalID, room, phone string, lastMessage time.Time) networkid.PortalKey {
	t.Helper()
	ctx := context.Background()
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: room, Network: "gmessages", Name: "Contact", IsDirect: true}))
	key := networkid.PortalKey{ID: networkid.PortalID(portalID), Receiver: gmAccount}
	require.NoError(t, w.h.Bridge.DB.Portal.Insert(ctx, &database.Portal{
		BridgeID: w.h.Bridge.ID, PortalKey: key, MXID: id.RoomID(room), RoomType: database.RoomTypeDM,
		Name: "Contact", NameSet: true, Metadata: &gmessages.PortalMetadata{},
	}))
	_, err := w.h.Bridge.DB.Exec(ctx,
		"INSERT INTO gmessages_direct_conversation (bridge_id, login_id, phone_number, portal_id, last_message_ts) VALUES ($1,$2,$3,$4,$5)",
		w.h.Bridge.ID, gmAccount, phone, portalID, lastMessage.UnixMicro())
	require.NoError(t, err)
	return key
}

func (w *gmWorld) portalRoom(t *testing.T, portalID string) (id.RoomID, bool) {
	t.Helper()
	p, err := w.h.Bridge.DB.Portal.GetByKey(context.Background(), networkid.PortalKey{ID: networkid.PortalID(portalID), Receiver: gmAccount})
	require.NoError(t, err)
	if p == nil {
		return "", false
	}
	return p.MXID, true
}

func (w *gmWorld) mapped(t *testing.T, phone string) string {
	t.Helper()
	var portal string
	err := w.h.Bridge.DB.QueryRow(context.Background(),
		"SELECT portal_id FROM gmessages_direct_conversation WHERE bridge_id=$1 AND login_id=$2 AND phone_number=$3",
		w.h.Bridge.ID, gmAccount, phone).Scan(&portal)
	if err != nil {
		return ""
	}
	return portal
}

// A contact's chat gets a new conversation ID: the bridge moves its portal to it. When storing the new mapping
// fails, the portal must stay where it is, with the mapping pointing at it. It used to move the portal first, and
// a failed mapping update (swallowed) left the portal gone and the mapping dangling. Once the failure is over, the
// same move goes through, so the failed attempt left the bridge's memory right too.
func TestGoogleMessagesDMMoveThatFailsToStoreItsMappingLeavesThePortalWhereItWas(t *testing.T) {
	ctx := context.Background()
	w := newGMWorld(t)
	const phone = "+15550000081"
	w.seedChat(t, "1.81", "!old:courier.local", phone, time.Unix(1000, 0))
	w.reload(t) // the client reads the mapping

	_, err := w.h.Bridge.DB.Exec(ctx, `CREATE TRIGGER fail_mapping BEFORE INSERT ON gmessages_direct_conversation
		BEGIN SELECT RAISE(ABORT, 'forced failure'); END`)
	require.NoError(t, err)

	w.deliver(t, conversationUpdate(directConversation("90", "", phone, time.Unix(2000, 0).UnixMicro())))

	room, ok := w.portalRoom(t, "1.81")
	require.True(t, ok, "the portal was not moved or deleted")
	require.Equal(t, id.RoomID("!old:courier.local"), room)
	_, moved := w.portalRoom(t, "1.90")
	require.False(t, moved, "nothing was made at the new ID")
	require.Equal(t, "1.81", w.mapped(t, phone), "the mapping still points at the portal that is still there")
	tomb, err := w.s.RoomIsTombstoned(ctx, "!old:courier.local")
	require.NoError(t, err)
	require.False(t, tomb)

	_, err = w.h.Bridge.DB.Exec(ctx, "DROP TRIGGER fail_mapping")
	require.NoError(t, err)
	w.deliver(t, conversationUpdate(directConversation("90", "", phone, time.Unix(2001, 0).UnixMicro())))

	room, ok = w.portalRoom(t, "1.90")
	require.True(t, ok, "now the portal moves to the new conversation ID")
	require.Equal(t, id.RoomID("!old:courier.local"), room, "with its room")
	_, still := w.portalRoom(t, "1.81")
	require.False(t, still)
	require.Equal(t, "1.90", w.mapped(t, phone))
}

// A mapping that already names the chat with no conversation ID (what the bug left) is moved to the contact's real
// conversation without touching that chat's portal: nothing is re-ID'd out of it (which would have lost its room to
// the contact), and nothing is made at "1.".
func TestGoogleMessagesNothingIsMovedOutOfAChatWithNoConversationID(t *testing.T) {
	ctx := context.Background()
	w := newGMWorld(t)
	const phone = "+15550000081"
	w.seedChat(t, "1.", "!empty:courier.local", phone, time.Unix(1000, 0))
	w.reload(t)

	w.deliver(t, conversationUpdate(directConversation("81", "", phone, time.Unix(2000, 0).UnixMicro())))

	room, ok := w.portalRoom(t, "1.")
	require.True(t, ok, "the chat with no ID is not touched here (the repair at start removes it)")
	require.Equal(t, id.RoomID("!empty:courier.local"), room, "and keeps its own room")
	tomb, err := w.s.RoomIsTombstoned(ctx, "!empty:courier.local")
	require.NoError(t, err)
	require.False(t, tomb)
	require.Equal(t, "1.81", w.mapped(t, phone), "the contact's number is mapped to the contact's own conversation now")
}
