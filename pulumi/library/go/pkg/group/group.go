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

// Package group provides a reusable component for creating Google Workspace /
// Cloud Identity groups. This mirrors the upstream
// terraform-google-modules/terraform-google-group module.
//
// The component creates:
//   - A Cloud Identity Group with configurable type labels
//   - Optional owner, manager, and member memberships
//
// Group types are controlled via the Types field:
//   - "default"  → cloudidentity.googleapis.com/groups.discussion_forum
//   - "security" → cloudidentity.googleapis.com/groups.security
//   - "dynamic"  → cloudidentity.googleapis.com/groups.dynamic
//   - "external" → system/groups/external
package group

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/cloudidentity"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// labelKeys maps human-readable group type names to Cloud Identity label keys.
// Mirrors the TF module's local.label_keys map.
var labelKeys = map[string]string{
	"default":  "cloudidentity.googleapis.com/groups.discussion_forum",
	"dynamic":  "cloudidentity.googleapis.com/groups.dynamic",
	"security": "cloudidentity.googleapis.com/groups.security",
	"external": "system/groups/external",
}

// GroupArgs configures the Group component.
// This mirrors the variables from terraform-google-modules/group/google.
type GroupArgs struct {
	// ID is the group email address (e.g. "gcp-org-admins@example.com").
	ID string
	// DisplayName is the human-readable group name.
	DisplayName string
	// Description is an optional extended description.
	Description string
	// CustomerID is the Google Workspace customer ID (e.g. "C01234abc").
	// Obtained from google_organization data source's directory_customer_id.
	CustomerID pulumi.StringInput
	// InitialGroupConfig controls the initial group setup.
	// Valid values: "WITH_INITIAL_OWNER", "EMPTY", "INITIAL_GROUP_CONFIG_UNSPECIFIED".
	// Defaults to "WITH_INITIAL_OWNER" matching the TF foundation.
	InitialGroupConfig string
	// Types defines the group type labels.
	// Defaults to ["default"] (discussion forum).
	// Use ["default", "security"] for security groups.
	Types []string

	// Owners is a list of member email addresses to add as OWNER+MEMBER.
	Owners []string
	// Managers is a list of member email addresses to add as MANAGER+MEMBER.
	Managers []string
	// Members is a list of member email addresses to add as MEMBER.
	Members []string
}

// Group is a Pulumi component that creates a Cloud Identity group with memberships.
type Group struct {
	pulumi.ResourceState

	// GroupResource is the underlying Cloud Identity group.
	GroupResource *cloudidentity.Group
	// GroupID is the fully qualified group resource name.
	GroupID pulumi.StringOutput
	// GroupEmail is the group email address.
	GroupEmail pulumi.StringOutput
}

// NewGroup creates a Cloud Identity group and optional memberships.
// This mirrors terraform-google-modules/group/google.
func NewGroup(ctx *pulumi.Context, name string, args *GroupArgs, opts ...pulumi.ResourceOption) (*Group, error) {
	component := &Group{}
	err := ctx.RegisterComponentResource("pkg:index:Group", name, component, opts...)
	if err != nil {
		return nil, err
	}

	// Apply defaults
	initialConfig := args.InitialGroupConfig
	if initialConfig == "" {
		initialConfig = "WITH_INITIAL_OWNER"
	}
	types := args.Types
	if len(types) == 0 {
		types = []string{"default"}
	}
	displayName := args.DisplayName
	if displayName == "" {
		displayName = args.ID
	}

	// Build labels from types
	labels := pulumi.StringMap{}
	for _, t := range types {
		key, ok := labelKeys[t]
		if !ok {
			return nil, fmt.Errorf("unknown group type %q; valid types: default, security, dynamic, external", t)
		}
		labels[key] = pulumi.String("")
	}

	// Create the group
	grp, err := cloudidentity.NewGroup(ctx, name, &cloudidentity.GroupArgs{
		DisplayName:        pulumi.String(displayName),
		Description:        pulumi.String(args.Description),
		Parent:             pulumi.Sprintf("customers/%s", args.CustomerID),
		InitialGroupConfig: pulumi.String(initialConfig),
		GroupKey: &cloudidentity.GroupGroupKeyArgs{
			Id: pulumi.String(args.ID),
		},
		Labels: labels,
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.GroupResource = grp
	component.GroupID = grp.Name
	component.GroupEmail = pulumi.String(args.ID).ToStringOutput()

	// Create memberships: owners get OWNER + MEMBER roles
	for i, owner := range args.Owners {
		if _, err := cloudidentity.NewGroupMembership(ctx, fmt.Sprintf("%s-owner-%d", name, i), &cloudidentity.GroupMembershipArgs{
			Group: grp.ID(),
			PreferredMemberKey: &cloudidentity.GroupMembershipPreferredMemberKeyArgs{
				Id: pulumi.String(owner),
			},
			Roles: cloudidentity.GroupMembershipRoleArray{
				&cloudidentity.GroupMembershipRoleArgs{Name: pulumi.String("OWNER")},
				&cloudidentity.GroupMembershipRoleArgs{Name: pulumi.String("MEMBER")},
			},
		}, pulumi.Parent(component)); err != nil {
			return nil, err
		}
	}

	// Managers get MANAGER + MEMBER roles
	for i, manager := range args.Managers {
		if _, err := cloudidentity.NewGroupMembership(ctx, fmt.Sprintf("%s-manager-%d", name, i), &cloudidentity.GroupMembershipArgs{
			Group: grp.ID(),
			PreferredMemberKey: &cloudidentity.GroupMembershipPreferredMemberKeyArgs{
				Id: pulumi.String(manager),
			},
			Roles: cloudidentity.GroupMembershipRoleArray{
				&cloudidentity.GroupMembershipRoleArgs{Name: pulumi.String("MEMBER")},
				&cloudidentity.GroupMembershipRoleArgs{Name: pulumi.String("MANAGER")},
			},
		}, pulumi.Parent(component)); err != nil {
			return nil, err
		}
	}

	// Members get MEMBER role only
	for i, member := range args.Members {
		if _, err := cloudidentity.NewGroupMembership(ctx, fmt.Sprintf("%s-member-%d", name, i), &cloudidentity.GroupMembershipArgs{
			Group: grp.ID(),
			PreferredMemberKey: &cloudidentity.GroupMembershipPreferredMemberKeyArgs{
				Id: pulumi.String(member),
			},
			Roles: cloudidentity.GroupMembershipRoleArray{
				&cloudidentity.GroupMembershipRoleArgs{Name: pulumi.String("MEMBER")},
			},
		}, pulumi.Parent(component)); err != nil {
			return nil, err
		}
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"groupId":    grp.Name,
		"groupEmail": pulumi.String(args.ID),
	})

	return component, nil
}
