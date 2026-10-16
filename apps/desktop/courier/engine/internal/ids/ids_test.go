package ids

import (
	"testing"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/id"
)

func TestGhostRoundTrip(t *testing.T) {
	uid := networkid.UserID("15551234567@s.whatsapp.net")
	mxid := GhostMXID("whatsapp", uid)
	require.Equal(t, "courier.local", mxid.Homeserver())
	back, ok := ParseGhostMXID("whatsapp", mxid)
	require.True(t, ok)
	require.Equal(t, uid, back)
	_, ok = ParseGhostMXID("signal", mxid)
	require.False(t, ok, "a WhatsApp ghost must not parse as a Signal ghost")
}

func TestDeterministicIDs(t *testing.T) {
	key := networkid.PortalKey{ID: "chat1", Receiver: "me"}
	r1, r2 := RoomID("whatsapp", key), RoomID("whatsapp", key)
	require.Equal(t, r1, r2)
	require.NotEqual(t, r1, RoomID("telegram", key))
	require.Equal(t, EventID(r1, key, "m1", ""), EventID(r1, key, "m1", ""))
	require.NotEqual(t, EventID(r1, key, "m1", ""), EventID(r1, key, "m1", "p2"))
}

const testHash = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"

func TestContentURIRoundTrip(t *testing.T) {
	hash, ok := ParseContentURI(ContentURI(testHash))
	require.True(t, ok)
	require.Equal(t, testHash, hash)
	_, ok = ParseContentURI("mxc://matrix.org/abc")
	require.False(t, ok)
}

func TestParseContentURIRejectsNonHashes(t *testing.T) {
	for _, bad := range []string{
		"mxc://courier.local/a",
		"mxc://courier.local/../x",
		"mxc://courier.local/",
		"mxc://courier.local/" + testHash[:63] + "G",
	} {
		hash, ok := ParseContentURI(id.ContentURIString(bad))
		require.False(t, ok, "%q must be rejected", bad)
		require.Empty(t, hash)
	}
}
