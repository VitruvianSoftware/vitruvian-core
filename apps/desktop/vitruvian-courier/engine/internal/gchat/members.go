// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"slices"
	"strings"

	"maunium.net/go/mautrix/bridgev2/networkid"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/gchat/pb"
)

// A Google Chat "app" (GitHub, Drive, a Jira bot...) shows up in a chat's membership list next to the people, tagged
// UserType BOT on its UserId. Native Google Chat does not count apps as people: a group of three people with the
// GitHub app added has three participants, not four, and its name lists the people only. These helpers keep that
// rule in one place. What they do NOT touch is what an app says: its messages still arrive with its name and
// avatar; only its place in the member list, the composed group name and the group-or-DM decision go.

// isAppUser reports whether u is a Google Chat app rather than a person. A UserId with no type is a person (the
// enum's zero value is HUMAN), which is also what a payload that predates the field looks like.
func isAppUser(u *pb.UserId) bool {
	return u != nil && u.GetType() == pb.UserType_BOT
}

// memberRoster collects the member IDs one chat's payloads list, remembering which of them are apps. An ID is an
// app if any list that carries it says so: the lists do not all carry the type, and one that omits it must not
// turn an app back into a person.
type memberRoster struct {
	ids  []string
	apps map[string]struct{}
}

// add records u (blank IDs and repeats are dropped).
func (r *memberRoster) add(u *pb.UserId) {
	id := strings.TrimSpace(u.GetId())
	if id == "" {
		return
	}
	if !slices.Contains(r.ids, id) {
		r.ids = append(r.ids, id)
	}
	if isAppUser(u) {
		if r.apps == nil {
			r.apps = make(map[string]struct{})
		}
		r.apps[id] = struct{}{}
	}
}

// appIDs is the apps seen, in the order they were first listed.
func (r *memberRoster) appIDs() []string {
	var out []string
	for _, id := range r.ids {
		if _, ok := r.apps[id]; ok {
			out = append(out, id)
		}
	}
	return out
}

// visibleMemberIDs is memberIDs without the apps: who the chat shows as its members. When nobody but apps (and
// me) is left, the apps stay, because that chat is one with an app: a DM with the GitHub app is a DM with GitHub.
func visibleMemberIDs(memberIDs, appIDs []string, own networkid.UserID) []string {
	if len(appIDs) == 0 {
		return memberIDs
	}
	people := make([]string, 0, len(memberIDs))
	hasOtherPerson := false
	for _, raw := range memberIDs {
		id := strings.TrimSpace(raw)
		if slices.Contains(appIDs, id) {
			continue
		}
		people = append(people, raw)
		if id != "" && MakeUserID(id) != own {
			hasOtherPerson = true
		}
	}
	if !hasOtherPerson {
		return memberIDs
	}
	return people
}

// mergeAppIDs is the apps known so far plus the ones just seen, limited to IDs still in memberIDs (an app that
// left the chat is no longer worth remembering).
func mergeAppIDs(known, seen, memberIDs []string) []string {
	var out []string
	for _, id := range append(slices.Clone(known), seen...) {
		id = strings.TrimSpace(id)
		if id == "" || slices.Contains(out, id) || !slices.Contains(memberIDs, id) {
			continue
		}
		out = append(out, id)
	}
	return out
}

// sameNameList reports whether a and b are the same comma-separated list of names, in any order. It is how an
// old, composed group name is told apart from one a person typed.
func sameNameList(a, b string) bool {
	split := func(s string) []string {
		parts := strings.Split(s, ",")
		for i := range parts {
			parts[i] = strings.TrimSpace(parts[i])
		}
		slices.Sort(parts)
		return parts
	}
	return strings.TrimSpace(a) != "" && slices.Equal(split(a), split(b))
}
