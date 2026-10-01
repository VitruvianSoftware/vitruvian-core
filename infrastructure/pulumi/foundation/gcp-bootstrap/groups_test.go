// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package main

import (
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const groupType = "gcp:cloudidentity/group:Group"

// groupMocks records the inputs each resource was registered with, keyed by
// type token, and answers the one invoke deployGroups makes.
type groupMocks struct {
	mu     sync.Mutex
	inputs map[string][]resource.PropertyMap
}

func (m *groupMocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.inputs == nil {
		m.inputs = map[string][]resource.PropertyMap{}
	}
	m.inputs[args.TypeToken] = append(m.inputs[args.TypeToken], args.Inputs)
	return args.Name + "_id", args.Inputs, nil
}

func (m *groupMocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	if args.Token == "gcp:organizations/getOrganization:getOrganization" {
		return resource.NewPropertyMapFromMap(map[string]interface{}{
			"directoryCustomerId": "C0test",
			"orgId":               "123456789",
		}), nil
	}
	return args.Args, nil
}

func (m *groupMocks) of(typ string) []resource.PropertyMap {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.inputs[typ]
}

// A Cloud Identity membership can exist in Google without being in Pulumi
// state: the provider reads a membership back immediately after creating it,
// and when that read is not yet visible it records nothing and reports no
// error (run 36915108605, "expected non-nil error with nil state during
// Create"). The next apply then tries to create a membership that is already
// there. Every membership this stack declares must therefore be created with
// createIgnoreAlreadyExists, so that apply adopts it instead of failing.
func TestDeployGroups_MembershipsAdoptExisting(t *testing.T) {
	m := &groupMocks{}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, _, err := deployGroups(ctx, &Config{
			OrgID:                "123456789",
			InitialGroupConfig:   "WITH_INITIAL_OWNER",
			GroupSessionExempt:   "gcp-session-exempt@example.com",
			SessionExemptMembers: []string{"a@example.com", "b@example.com"},
		})
		return err
	}, pulumi.WithMocks("foundation-bootstrap", "test", m))
	require.NoError(t, err)

	require.Len(t, m.of(groupType), 1, "the session-exempt group")
	memberships := m.of(groupMembershipType)
	require.Len(t, memberships, 2, "one membership per configured member")
	for _, in := range memberships {
		got, ok := in["createIgnoreAlreadyExists"]
		require.True(t, ok, "membership registered without createIgnoreAlreadyExists: %v", in)
		assert.True(t, got.IsBool() && got.BoolValue(), "createIgnoreAlreadyExists must be true, got %v", got)
	}
}

// The option is scoped to memberships. A group that already exists must still
// fail loudly rather than be silently taken over, so nothing else may gain an
// "ignore already exists" input.
func TestDeployGroups_GroupItselfIsNotAdopted(t *testing.T) {
	m := &groupMocks{}
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, _, err := deployGroups(ctx, &Config{
			OrgID:                "123456789",
			InitialGroupConfig:   "WITH_INITIAL_OWNER",
			GroupSessionExempt:   "gcp-session-exempt@example.com",
			SessionExemptMembers: []string{"a@example.com"},
		})
		return err
	}, pulumi.WithMocks("foundation-bootstrap", "test", m))
	require.NoError(t, err)

	groups := m.of(groupType)
	require.Len(t, groups, 1)
	_, ok := groups[0]["createIgnoreAlreadyExists"]
	assert.False(t, ok, "the group must not carry createIgnoreAlreadyExists")
}
