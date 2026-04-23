/*
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package group

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	gcpGroup      = "gcp:cloudidentity/group:Group"
	gcpMembership = "gcp:cloudidentity/groupMembership:GroupMembership"
)

func basicArgs() *GroupArgs {
	return &GroupArgs{
		ID:          "gcp-org-admins@example.com",
		DisplayName: "GCP Org Admins",
		Description: "Organization administrators",
		CustomerID:  pulumi.String("C01234abc"),
	}
}

// ---------- Basic Creation ----------

func TestNewGroup_CreatesGroup(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		g, err := NewGroup(ctx, "test-group", basicArgs())
		require.NoError(t, err)
		assert.NotNil(t, g.GroupResource)
		return nil
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	groups := tracker.RequireType(t, gcpGroup, 1)
	assert.Equal(t, "GCP Org Admins", groups[0].Inputs["displayName"].StringValue())
	assert.Equal(t, "Organization administrators", groups[0].Inputs["description"].StringValue())
	assert.Equal(t, "WITH_INITIAL_OWNER", groups[0].Inputs["initialGroupConfig"].StringValue())
}

func TestNewGroup_DefaultLabels(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewGroup(ctx, "test-labels", basicArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	groups := tracker.RequireType(t, gcpGroup, 1)
	labels := groups[0].Inputs["labels"].ObjectValue()
	_, hasDefault := labels["cloudidentity.googleapis.com/groups.discussion_forum"]
	assert.True(t, hasDefault, "should have default discussion_forum label")
}

func TestNewGroup_SecurityType(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicArgs()
		args.Types = []string{"default", "security"}
		_, err := NewGroup(ctx, "test-security", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	groups := tracker.RequireType(t, gcpGroup, 1)
	labels := groups[0].Inputs["labels"].ObjectValue()
	_, hasSecurity := labels["cloudidentity.googleapis.com/groups.security"]
	_, hasDefault := labels["cloudidentity.googleapis.com/groups.discussion_forum"]
	assert.True(t, hasSecurity, "should have security label")
	assert.True(t, hasDefault, "should also have default label")
}

// ---------- GroupKey ----------

func TestNewGroup_GroupKey(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewGroup(ctx, "test-key", basicArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	groups := tracker.RequireType(t, gcpGroup, 1)
	groupKey := groups[0].Inputs["groupKey"].ObjectValue()
	assert.Equal(t, "gcp-org-admins@example.com", groupKey["id"].StringValue())
}

// ---------- Memberships ----------

func TestNewGroup_NoMemberships(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewGroup(ctx, "test-no-members", basicArgs())
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	assert.Equal(t, 0, tracker.TypeCount(gcpMembership))
}

func TestNewGroup_WithOwners(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicArgs()
		args.Owners = []string{"admin1@example.com", "admin2@example.com"}
		_, err := NewGroup(ctx, "test-owners", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	memberships := tracker.RequireType(t, gcpMembership, 2)
	// Check that at least one has the OWNER role
	hasOwner := false
	for _, m := range memberships {
		roles := m.Inputs["roles"].ArrayValue()
		for _, r := range roles {
			if r.ObjectValue()["name"].StringValue() == "OWNER" {
				hasOwner = true
			}
		}
	}
	assert.True(t, hasOwner, "should have OWNER role")
}

func TestNewGroup_WithManagers(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicArgs()
		args.Managers = []string{"manager@example.com"}
		_, err := NewGroup(ctx, "test-managers", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	memberships := tracker.RequireType(t, gcpMembership, 1)
	hasManager := false
	for _, m := range memberships {
		roles := m.Inputs["roles"].ArrayValue()
		for _, r := range roles {
			if r.ObjectValue()["name"].StringValue() == "MANAGER" {
				hasManager = true
			}
		}
	}
	assert.True(t, hasManager, "should have MANAGER role")
}

func TestNewGroup_WithMembers(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicArgs()
		args.Members = []string{"user1@example.com", "user2@example.com", "user3@example.com"}
		_, err := NewGroup(ctx, "test-members", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, gcpMembership, 3)
}

func TestNewGroup_MixedMemberships(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicArgs()
		args.Owners = []string{"owner@example.com"}
		args.Managers = []string{"manager@example.com"}
		args.Members = []string{"member@example.com"}
		_, err := NewGroup(ctx, "test-mixed", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	// 1 owner + 1 manager + 1 member = 3 memberships
	tracker.RequireType(t, gcpMembership, 3)
}

// ---------- Defaults ----------

func TestNewGroup_DisplayNameDefault(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicArgs()
		args.DisplayName = "" // empty → should default to ID
		_, err := NewGroup(ctx, "test-default-name", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	groups := tracker.RequireType(t, gcpGroup, 1)
	assert.Equal(t, "gcp-org-admins@example.com", groups[0].Inputs["displayName"].StringValue())
}

func TestNewGroup_InitialGroupConfigDefault(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicArgs()
		args.InitialGroupConfig = "" // empty → should default to WITH_INITIAL_OWNER
		_, err := NewGroup(ctx, "test-default-config", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", tracker))
	require.NoError(t, err)

	groups := tracker.RequireType(t, gcpGroup, 1)
	assert.Equal(t, "WITH_INITIAL_OWNER", groups[0].Inputs["initialGroupConfig"].StringValue())
}

// ---------- Error Cases ----------

func TestNewGroup_InvalidType(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		args := basicArgs()
		args.Types = []string{"invalid"}
		_, err := NewGroup(ctx, "test-bad-type", args)
		return err
	}, pulumi.WithMocks("test-project", "test-stack", testutil.NewTracker()))
	require.Error(t, err)
	assert.Contains(t, err.Error(), "unknown group type")
}
