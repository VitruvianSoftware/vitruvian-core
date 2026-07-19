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
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// SharedConfig holds the configuration for the shared root: the hierarchical
// firewall parent and its folder associations.
type SharedConfig struct {
	ParentID                      string
	FirewallAssociations          []string
	FirewallPoliciesEnableLogging bool
}

func loadSharedConfig(ctx *pulumi.Context) *SharedConfig {
	conf := config.New(ctx, "")

	c := &SharedConfig{
		ParentID: conf.Require("parent_id"),
	}
	conf.GetObject("firewall_associations", &c.FirewallAssociations)

	if val, err := conf.TryBool("firewall_policies_enable_logging"); err == nil {
		c.FirewallPoliciesEnableLogging = val
	} else {
		c.FirewallPoliciesEnableLogging = true // Default to true matching TF
	}

	if len(c.FirewallAssociations) == 0 {
		c.FirewallAssociations = []string{c.ParentID} // Fallback to parent
	}

	return c
}
