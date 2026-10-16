// Package ids maps network identifiers to the Matrix-shaped IDs the bridges expect.
package ids

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"regexp"
	"strings"

	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/id"
)

const ServerName = "courier.local"

const Me id.UserID = "@me:" + ServerName

// contentHashRE is the only shape of media name we will accept: a lower-case SHA-256 hex string.
var contentHashRE = regexp.MustCompile(`^[0-9a-f]{64}$`)

func h(parts ...string) string {
	sum := sha256.Sum256([]byte(strings.Join(parts, "\x00")))
	return hex.EncodeToString(sum[:])[:32]
}

func GhostMXID(network string, uid networkid.UserID) id.UserID {
	return id.NewUserID(network+"_"+id.EncodeUserLocalpart(string(uid)), ServerName)
}

func ParseGhostMXID(network string, mxid id.UserID) (networkid.UserID, bool) {
	local, server, err := mxid.Parse()
	if err != nil || server != ServerName || !strings.HasPrefix(local, network+"_") {
		return "", false
	}
	dec, err := id.DecodeUserLocalpart(strings.TrimPrefix(local, network+"_"))
	if err != nil {
		return "", false
	}
	return networkid.UserID(dec), true
}

func RoomID(network string, key networkid.PortalKey) id.RoomID {
	return id.RoomID("!" + h("room", network, string(key.ID), string(key.Receiver)) + ":" + ServerName)
}

func EventID(roomID id.RoomID, key networkid.PortalKey, msg networkid.MessageID, part networkid.PartID) id.EventID {
	return id.EventID("$" + h("evt", string(roomID), string(key.ID), string(msg), string(part)))
}

func ReactionEventID(roomID id.RoomID, msg networkid.MessageID, part networkid.PartID, sender networkid.UserID, emoji networkid.EmojiID) id.EventID {
	return id.EventID("$" + h("react", string(roomID), string(msg), string(part), string(sender), string(emoji)))
}

func RandomEventID() id.EventID {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return id.EventID("$" + hex.EncodeToString(b))
}

func ContentURI(hash string) id.ContentURIString {
	return id.ContentURIString("mxc://" + ServerName + "/" + hash)
}

// ParseContentURI returns the media hash for one of our own mxc:// URIs. It
// returns ok=false for foreign servers and for any suffix that is not a real hash.
func ParseContentURI(uri id.ContentURIString) (string, bool) {
	rest, ok := strings.CutPrefix(string(uri), "mxc://"+ServerName+"/")
	if !ok || !contentHashRE.MatchString(rest) {
		return "", false
	}
	return rest, true
}
