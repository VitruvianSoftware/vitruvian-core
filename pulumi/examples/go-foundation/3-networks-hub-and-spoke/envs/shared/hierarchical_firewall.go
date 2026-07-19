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

package main

import (
	"foundation-3-networks-hub-and-spoke/modules/hierarchical_firewall_policy"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// deployHierarchicalFirewall provisions the org/folder-level hierarchical
// firewall policy (hub only), mirroring upstream
// 3-networks-hub-and-spoke/envs/shared/hierarchical_firewall.tf.
func deployHierarchicalFirewall(ctx *pulumi.Context, cfg *NetSharedConfig) error {
	return hierarchical_firewall_policy.New(ctx, &hierarchical_firewall_policy.Args{
		ParentID:      cfg.ParentID,
		Env:           pinnedEnv,
		Associations:  cfg.FirewallAssociations,
		EnableLogging: cfg.FirewallPoliciesEnableLogging,
	})
}
