package fakenet

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/bridgeconfig"
	"maunium.net/go/mautrix/bridgev2/commands"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/localmatrix"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func TestRemoteMessageLandsAndReplyGoesOut(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	bdb, err := sqlite.Open(filepath.Join(dir, "fake.db"))
	require.NoError(t, err)
	net := New()
	conn := localmatrix.New("fake", s, &media.Store{Dir: filepath.Join(dir, "media")})
	cfg := &bridgeconfig.BridgeConfig{CommandPrefix: "!fake",
		Permissions: bridgeconfig.PermissionConfig{string(ids.Me): &bridgeconfig.PermissionLevelAdmin}}
	br := bridgev2.NewBridge("fake", bdb, zerolog.Nop(), cfg, conn, net, func(b *bridgev2.Bridge) bridgev2.CommandProcessor { return commands.NewProcessor(b) })
	require.NoError(t, br.Start(ctx))
	defer br.Stop()

	login, err := net.Login(ctx, br)
	require.NoError(t, err)

	net.Incoming(login, "chat1", "alice", "m1", "hello from the network")

	// Don't assume how bridgev2 picks the room ID: find whichever room received the message.
	var roomID id.RoomID
	require.Eventually(t, func() bool {
		rooms, _ := s.ListRooms(ctx)
		for _, r := range rooms {
			evs, _ := s.Events(ctx, r.ID, 10)
			for _, e := range evs {
				if e.Type == event.EventMessage.Type && strings.Contains(string(e.Content), "hello from the network") {
					roomID = id.RoomID(r.ID)
					return true
				}
			}
		}
		return false
	}, 5*time.Second, 50*time.Millisecond, "remote message never reached courier.db")

	reply := &event.Event{Type: event.EventMessage, RoomID: roomID, Sender: ids.Me, ID: ids.RandomEventID(),
		Timestamp: time.Now().UnixMilli(), Content: event.Content{Parsed: &event.MessageEventContent{MsgType: event.MsgText, Body: "hi alice"}}}
	br.QueueMatrixEvent(ctx, reply)
	select {
	case body := <-net.Sent:
		require.Equal(t, "hi alice", body)
	case <-time.After(5 * time.Second):
		t.Fatal("reply never reached the fake network")
	}
}
