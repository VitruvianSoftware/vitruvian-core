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

// Package hierarchical_firewall_policy is the Pulumi port of upstream
// terraform-example-foundation 3-networks-svpc/modules/
// hierarchical_firewall_policy. It creates the org/folder-level hierarchical
// firewall policy and associates it with the foundation folders (envs/shared
// only).
package hierarchical_firewall_policy

import (
	"fmt"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	networking "github.com/VitruvianSoftware/pulumi-library/go/pkg/network/v2"
)

// New creates the hierarchical firewall policy, associating it with the
// configured foundation folders.
func New(ctx *pulumi.Context, args *Args) error {
	_, err := networking.NewHierarchicalFirewallPolicy(ctx, "hierarchical-fw", &networking.HierarchicalFirewallPolicyArgs{
		ParentID:      pulumi.String(args.ParentID),
		ShortName:     fmt.Sprintf("fw-%s-svpc-hierarchical", args.Env),
		Description:   "Hierarchical firewall rules",
		Associations:  args.Associations,
		EnableLogging: args.EnableLogging,
	})
	return err
}
