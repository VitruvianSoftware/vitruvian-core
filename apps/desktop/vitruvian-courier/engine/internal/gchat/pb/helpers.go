// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package pb

import "google.golang.org/protobuf/proto"

// Marshal serializes a generated protobuf message to wire format.
func Marshal(m proto.Message) ([]byte, error) {
	return proto.Marshal(m)
}

// MustMarshal serializes a generated protobuf message to wire format and panics on error.
func MustMarshal(m proto.Message) []byte {
	b, err := proto.Marshal(m)
	if err != nil {
		panic(err)
	}
	return b
}

// Unmarshal parses wire-format bytes into a generated protobuf message.
func Unmarshal(b []byte, m proto.Message) error {
	return proto.Unmarshal(b, m)
}

// Equal reports whether two protobuf messages are equal.
func Equal(x, y proto.Message) bool {
	return proto.Equal(x, y)
}

// String stores v in a new string value and returns a pointer to it.
func String(v string) *string {
	return proto.String(v)
}

// Int64 stores v in a new int64 value and returns a pointer to it.
func Int64(v int64) *int64 {
	return proto.Int64(v)
}

// Int32 stores v in a new int32 value and returns a pointer to it.
func Int32(v int32) *int32 {
	return proto.Int32(v)
}

// Uint64 stores v in a new uint64 value and returns a pointer to it.
func Uint64(v uint64) *uint64 {
	return proto.Uint64(v)
}

// Uint32 stores v in a new uint32 value and returns a pointer to it.
func Uint32(v uint32) *uint32 {
	return proto.Uint32(v)
}

// Bool stores v in a new bool value and returns a pointer to it.
func Bool(v bool) *bool {
	return proto.Bool(v)
}

// SpaceGroupID constructs a GroupId for a named Space.
func SpaceGroupID(spaceID string) *GroupId {
	return &GroupId{
		Id: &GroupId_SpaceId{
			SpaceId: &SpaceId{SpaceId: String(spaceID)},
		},
	}
}

// DMGroupID constructs a GroupId for a Direct Message.
func DMGroupID(dmID string) *GroupId {
	return &GroupId{
		Id: &GroupId_DmId{
			DmId: &DmId{DmId: String(dmID)},
		},
	}
}

// PartsToGroupID constructs a GroupId for either a DM or a Space.
func PartsToGroupID(rawID string, isDM bool) *GroupId {
	if isDM {
		return DMGroupID(rawID)
	}
	return SpaceGroupID(rawID)
}

// GroupIDToParts extracts the raw group ID and whether it is a DM from a GroupId.
func GroupIDToParts(gid *GroupId) (rawID string, isDM bool, ok bool) {
	if gid == nil {
		return "", false, false
	}
	if dm := gid.GetDmId().GetDmId(); dm != "" {
		return dm, true, true
	}
	if sp := gid.GetSpaceId().GetSpaceId(); sp != "" {
		return sp, false, true
	}
	return "", false, false
}

// HumanUserID constructs a UserId with UserType_HUMAN.
func HumanUserID(gaiaID string) *UserId {
	return &UserId{
		Id:   String(gaiaID),
		Type: UserType_HUMAN.Enum(),
	}
}

// UserMemberID constructs a MemberId wrapping a HumanUserID.
func UserMemberID(gaiaID string) *MemberId {
	return &MemberId{
		Id: &MemberId_UserId{
			UserId: HumanUserID(gaiaID),
		},
	}
}
