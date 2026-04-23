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

// Package networking provides Pulumi components for GCP networking.
//
// The NetworkFirewallPolicy component matches the upstream
// terraform-google-modules/network//modules/network-firewall-policy module.
// It is fully data-driven: callers supply a list of FirewallRule structs
// and the component creates the policy, associations, and rules dynamically.
// Both global and regional policies are supported via PolicyRegion.
package networking

import (
	"fmt"
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// FirewallLayer4Config mirrors a single layer4_configs entry.
type FirewallLayer4Config struct {
	IpProtocol string
	Ports      []string
}

// FirewallRuleMatch mirrors the upstream match block with full field support.
type FirewallRuleMatch struct {
	SrcIpRanges             []string
	SrcFqdns                []string
	SrcRegionCodes          []string
	SrcThreatIntelligences  []string
	SrcAddressGroups        []string
	SrcSecureTags           []pulumi.StringInput
	SrcNetworks             []string
	SrcNetworkScope         string
	DestIpRanges            []string
	DestFqdns               []string
	DestRegionCodes         []string
	DestThreatIntelligences []string
	DestAddressGroups       []string
	DestNetworkScope        string
	Layer4Configs           []FirewallLayer4Config
}

// FirewallRule defines a single firewall policy rule.
// This struct mirrors the upstream TF module's rule variable type.
type FirewallRule struct {
	Priority              int
	Direction             string // "INGRESS" or "EGRESS"
	Action                string // "allow", "deny", "apply_security_profile_group"
	RuleName              string
	Description           string
	EnableLogging         bool
	Disabled              bool
	TargetServiceAccounts []string
	TargetSecureTags      []pulumi.StringInput
	Match                 FirewallRuleMatch
}

// NetworkFirewallPolicyArgs is the input for the data-driven firewall policy component.
type NetworkFirewallPolicyArgs struct {
	ProjectID   pulumi.StringInput
	PolicyName  string
	Description string
	// PolicyRegion: if empty, creates a global policy. If set, creates a regional policy.
	PolicyRegion string
	// TargetVPCs: list of VPC self-links to associate the policy with.
	// Format: "projects/{project}/global/networks/{network}"
	TargetVPCs []pulumi.StringInput
	// Rules: the full list of firewall rules to create.
	Rules []FirewallRule
}

// NetworkFirewallPolicy is the component output.
type NetworkFirewallPolicy struct {
	pulumi.ResourceState
	// For global policies
	Policy *compute.NetworkFirewallPolicy
	// For regional policies
	RegionalPolicy *compute.RegionNetworkFirewallPolicy
}

func NewNetworkFirewallPolicy(ctx *pulumi.Context, name string, args *NetworkFirewallPolicyArgs, opts ...pulumi.ResourceOption) (*NetworkFirewallPolicy, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}

	component := &NetworkFirewallPolicy{}
	err := ctx.RegisterComponentResource("pkg:index:NetworkFirewallPolicy", name, component, opts...)
	if err != nil {
		return nil, err
	}

	description := args.Description
	if description == "" {
		description = fmt.Sprintf("Firewall rules for %s", args.PolicyName)
	}

	isGlobal := args.PolicyRegion == ""

	if isGlobal {
		// ===================== GLOBAL POLICY =====================
		policy, err := compute.NewNetworkFirewallPolicy(ctx, name+"-policy", &compute.NetworkFirewallPolicyArgs{
			Project:     args.ProjectID,
			Name:        pulumi.String(args.PolicyName),
			Description: pulumi.String(description),
		}, pulumi.Parent(component))
		if err != nil {
			return nil, err
		}
		component.Policy = policy

		// Associations — one per target VPC
		for i, vpc := range args.TargetVPCs {
			// Extract network name from self-link for the association name
			assocName := fmt.Sprintf("%s-assoc-%d", name, i)
			_, err = compute.NewNetworkFirewallPolicyAssociation(ctx, assocName, &compute.NetworkFirewallPolicyAssociationArgs{
				Project:          args.ProjectID,
				FirewallPolicy:   policy.Name,
				AttachmentTarget: vpc,
				Name: vpc.ToStringOutput().ApplyT(func(v string) string {
					parts := strings.Split(v, "/")
					netName := parts[len(parts)-1]
					return fmt.Sprintf("%s-%s", args.PolicyName, netName)
				}).(pulumi.StringOutput),
			}, pulumi.Parent(policy))
			if err != nil {
				return nil, err
			}
		}

		// Rules — one per priority
		for _, rule := range args.Rules {
			ruleArgs := buildGlobalRuleArgs(args.ProjectID, policy.Name, rule)
			_, err = compute.NewNetworkFirewallPolicyRule(ctx,
				fmt.Sprintf("%s-rule-%d", name, rule.Priority),
				ruleArgs, pulumi.Parent(policy))
			if err != nil {
				return nil, err
			}
		}
	} else {
		// ===================== REGIONAL POLICY =====================
		regPolicy, err := compute.NewRegionNetworkFirewallPolicy(ctx, name+"-policy", &compute.RegionNetworkFirewallPolicyArgs{
			Project:     args.ProjectID,
			Name:        pulumi.String(args.PolicyName),
			Description: pulumi.String(description),
			Region:      pulumi.String(args.PolicyRegion),
		}, pulumi.Parent(component))
		if err != nil {
			return nil, err
		}
		component.RegionalPolicy = regPolicy

		// Associations
		for i, vpc := range args.TargetVPCs {
			assocName := fmt.Sprintf("%s-assoc-%d", name, i)
			_, err = compute.NewRegionNetworkFirewallPolicyAssociation(ctx, assocName, &compute.RegionNetworkFirewallPolicyAssociationArgs{
				Project:          args.ProjectID,
				FirewallPolicy:   regPolicy.Name,
				AttachmentTarget: vpc,
				Region:           pulumi.String(args.PolicyRegion),
				Name: vpc.ToStringOutput().ApplyT(func(v string) string {
					parts := strings.Split(v, "/")
					netName := parts[len(parts)-1]
					return fmt.Sprintf("%s-%s-%s", args.PolicyName, args.PolicyRegion, netName)
				}).(pulumi.StringOutput),
			}, pulumi.Parent(regPolicy))
			if err != nil {
				return nil, err
			}
		}

		// Regional rules
		for _, rule := range args.Rules {
			ruleArgs := buildRegionalRuleArgs(args.ProjectID, regPolicy.Name, args.PolicyRegion, rule)
			_, err = compute.NewRegionNetworkFirewallPolicyRule(ctx,
				fmt.Sprintf("%s-rule-%d", name, rule.Priority),
				ruleArgs, pulumi.Parent(regPolicy))
			if err != nil {
				return nil, err
			}
		}
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"policyName": pulumi.String(args.PolicyName),
	})

	return component, nil
}

// buildGlobalRuleArgs constructs a global NetworkFirewallPolicyRuleArgs from our FirewallRule struct.
func buildGlobalRuleArgs(projectID pulumi.StringInput, policyName pulumi.StringOutput, rule FirewallRule) *compute.NetworkFirewallPolicyRuleArgs {
	matchArgs := buildGlobalMatchArgs(rule)

	ruleArgs := &compute.NetworkFirewallPolicyRuleArgs{
		Project:        projectID,
		FirewallPolicy: policyName,
		Priority:       pulumi.Int(rule.Priority),
		Direction:      pulumi.String(rule.Direction),
		Action:         pulumi.String(rule.Action),
		RuleName:       pulumi.String(rule.RuleName),
		Description:    pulumi.String(rule.Description),
		EnableLogging:  pulumi.Bool(rule.EnableLogging),
		Disabled:       pulumi.Bool(rule.Disabled),
		Match:          matchArgs,
	}

	if len(rule.TargetServiceAccounts) > 0 {
		ruleArgs.TargetServiceAccounts = toPulumiStringArray(rule.TargetServiceAccounts)
	}

	if len(rule.TargetSecureTags) > 0 {
		var tags compute.NetworkFirewallPolicyRuleTargetSecureTagArray
		for _, t := range rule.TargetSecureTags {
			tags = append(tags, &compute.NetworkFirewallPolicyRuleTargetSecureTagArgs{
				Name: t,
			})
		}
		ruleArgs.TargetSecureTags = tags
	}

	return ruleArgs
}

func buildGlobalMatchArgs(rule FirewallRule) *compute.NetworkFirewallPolicyRuleMatchArgs {
	m := rule.Match
	matchArgs := &compute.NetworkFirewallPolicyRuleMatchArgs{}

	if len(m.SrcIpRanges) > 0 {
		matchArgs.SrcIpRanges = toPulumiStringArray(m.SrcIpRanges)
	}
	if len(m.DestIpRanges) > 0 {
		matchArgs.DestIpRanges = toPulumiStringArray(m.DestIpRanges)
	}

	// Direction-sensitive fields
	if rule.Direction == "INGRESS" {
		if len(m.SrcFqdns) > 0 {
			matchArgs.SrcFqdns = toPulumiStringArray(m.SrcFqdns)
		}
		if len(m.SrcRegionCodes) > 0 {
			matchArgs.SrcRegionCodes = toPulumiStringArray(m.SrcRegionCodes)
		}
		if len(m.SrcThreatIntelligences) > 0 {
			matchArgs.SrcThreatIntelligences = toPulumiStringArray(m.SrcThreatIntelligences)
		}
		if len(m.SrcAddressGroups) > 0 {
			matchArgs.SrcAddressGroups = toPulumiStringArray(m.SrcAddressGroups)
		}
		if len(m.SrcSecureTags) > 0 {
			var tags compute.NetworkFirewallPolicyRuleMatchSrcSecureTagArray
			for _, t := range m.SrcSecureTags {
				tags = append(tags, &compute.NetworkFirewallPolicyRuleMatchSrcSecureTagArgs{
					Name: t,
				})
			}
			matchArgs.SrcSecureTags = tags
		}
	}
	if rule.Direction == "EGRESS" {
		if len(m.DestFqdns) > 0 {
			matchArgs.DestFqdns = toPulumiStringArray(m.DestFqdns)
		}
		if len(m.DestRegionCodes) > 0 {
			matchArgs.DestRegionCodes = toPulumiStringArray(m.DestRegionCodes)
		}
		if len(m.DestThreatIntelligences) > 0 {
			matchArgs.DestThreatIntelligences = toPulumiStringArray(m.DestThreatIntelligences)
		}
		if len(m.DestAddressGroups) > 0 {
			matchArgs.DestAddressGroups = toPulumiStringArray(m.DestAddressGroups)
		}
	}

	if len(m.SrcNetworks) > 0 {
		matchArgs.SrcNetworks = toPulumiStringArray(m.SrcNetworks)
	}

	// Layer4 configs
	var l4 compute.NetworkFirewallPolicyRuleMatchLayer4ConfigArray
	for _, cfg := range m.Layer4Configs {
		l4Args := &compute.NetworkFirewallPolicyRuleMatchLayer4ConfigArgs{
			IpProtocol: pulumi.String(cfg.IpProtocol),
		}
		if len(cfg.Ports) > 0 {
			l4Args.Ports = toPulumiStringArray(cfg.Ports)
		}
		l4 = append(l4, l4Args)
	}
	matchArgs.Layer4Configs = l4

	return matchArgs
}

// buildRegionalRuleArgs constructs a regional rule — same fields but different type.
func buildRegionalRuleArgs(projectID pulumi.StringInput, policyName pulumi.StringOutput, region string, rule FirewallRule) *compute.RegionNetworkFirewallPolicyRuleArgs {
	m := rule.Match

	matchArgs := &compute.RegionNetworkFirewallPolicyRuleMatchArgs{}
	if len(m.SrcIpRanges) > 0 {
		matchArgs.SrcIpRanges = toPulumiStringArray(m.SrcIpRanges)
	}
	if len(m.DestIpRanges) > 0 {
		matchArgs.DestIpRanges = toPulumiStringArray(m.DestIpRanges)
	}
	if rule.Direction == "INGRESS" {
		if len(m.SrcFqdns) > 0 {
			matchArgs.SrcFqdns = toPulumiStringArray(m.SrcFqdns)
		}
		if len(m.SrcRegionCodes) > 0 {
			matchArgs.SrcRegionCodes = toPulumiStringArray(m.SrcRegionCodes)
		}
		if len(m.SrcThreatIntelligences) > 0 {
			matchArgs.SrcThreatIntelligences = toPulumiStringArray(m.SrcThreatIntelligences)
		}
		if len(m.SrcAddressGroups) > 0 {
			matchArgs.SrcAddressGroups = toPulumiStringArray(m.SrcAddressGroups)
		}
	}
	if rule.Direction == "EGRESS" {
		if len(m.DestFqdns) > 0 {
			matchArgs.DestFqdns = toPulumiStringArray(m.DestFqdns)
		}
		if len(m.DestRegionCodes) > 0 {
			matchArgs.DestRegionCodes = toPulumiStringArray(m.DestRegionCodes)
		}
		if len(m.DestThreatIntelligences) > 0 {
			matchArgs.DestThreatIntelligences = toPulumiStringArray(m.DestThreatIntelligences)
		}
		if len(m.DestAddressGroups) > 0 {
			matchArgs.DestAddressGroups = toPulumiStringArray(m.DestAddressGroups)
		}
	}
	if len(m.SrcNetworks) > 0 {
		matchArgs.SrcNetworks = toPulumiStringArray(m.SrcNetworks)
	}

	var l4 compute.RegionNetworkFirewallPolicyRuleMatchLayer4ConfigArray
	for _, cfg := range m.Layer4Configs {
		l4Args := &compute.RegionNetworkFirewallPolicyRuleMatchLayer4ConfigArgs{
			IpProtocol: pulumi.String(cfg.IpProtocol),
		}
		if len(cfg.Ports) > 0 {
			l4Args.Ports = toPulumiStringArray(cfg.Ports)
		}
		l4 = append(l4, l4Args)
	}
	matchArgs.Layer4Configs = l4

	ruleArgs := &compute.RegionNetworkFirewallPolicyRuleArgs{
		Project:        projectID,
		FirewallPolicy: policyName,
		Region:         pulumi.String(region),
		Priority:       pulumi.Int(rule.Priority),
		Direction:      pulumi.String(rule.Direction),
		Action:         pulumi.String(rule.Action),
		RuleName:       pulumi.String(rule.RuleName),
		Description:    pulumi.String(rule.Description),
		EnableLogging:  pulumi.Bool(rule.EnableLogging),
		Disabled:       pulumi.Bool(rule.Disabled),
		Match:          matchArgs,
	}

	if len(rule.TargetServiceAccounts) > 0 {
		ruleArgs.TargetServiceAccounts = toPulumiStringArray(rule.TargetServiceAccounts)
	}

	if len(rule.TargetSecureTags) > 0 {
		var tags compute.RegionNetworkFirewallPolicyRuleTargetSecureTagArray
		for _, t := range rule.TargetSecureTags {
			tags = append(tags, &compute.RegionNetworkFirewallPolicyRuleTargetSecureTagArgs{
				Name: t,
			})
		}
		ruleArgs.TargetSecureTags = tags
	}

	return ruleArgs
}

func toPulumiStringArray(ss []string) pulumi.StringArray {
	var out pulumi.StringArray
	for _, s := range ss {
		out = append(out, pulumi.String(s))
	}
	return out
}

// ========================================================================
// Convenience: BuildFoundationRules creates the standard set of
// foundation firewall rules matching the upstream TF firewall.tf.
// This is a helper for callers who want the standard 4-rule set.
// ========================================================================

func BuildFoundationRules(envCode string, enableLogging bool, restrictedApiCidr string, subnetIPs []string, enableInternal bool) []FirewallRule {
	rules := []FirewallRule{
		{
			Priority:      65530,
			Direction:     "EGRESS",
			Action:        "deny",
			RuleName:      fmt.Sprintf("fw-%s-svpc-65530-e-d-all-all-all", envCode),
			Description:   "Lower priority rule to deny all egress traffic.",
			EnableLogging: enableLogging,
			Match: FirewallRuleMatch{
				DestIpRanges: []string{"0.0.0.0/0"},
				Layer4Configs: []FirewallLayer4Config{
					{IpProtocol: "all"},
				},
			},
		},
		{
			Priority:      1000,
			Direction:     "EGRESS",
			Action:        "allow",
			RuleName:      fmt.Sprintf("fw-%s-svpc-1000-e-a-allow-google-apis-all-tcp-443", envCode),
			Description:   "Lower priority rule to allow restricted google apis on TCP port 443.",
			EnableLogging: enableLogging,
			Match: FirewallRuleMatch{
				DestIpRanges: []string{restrictedApiCidr},
				Layer4Configs: []FirewallLayer4Config{
					{IpProtocol: "tcp", Ports: []string{"443"}},
				},
			},
		},
	}

	if enableInternal {
		rules = append(rules,
			FirewallRule{
				Priority:      10000,
				Direction:     "EGRESS",
				Action:        "allow",
				RuleName:      fmt.Sprintf("fw-%s-svpc-10000-e-a-all-all-all", envCode),
				Description:   "Allow all egress to the provided IP range.",
				EnableLogging: enableLogging,
				Match: FirewallRuleMatch{
					DestIpRanges: subnetIPs,
					Layer4Configs: []FirewallLayer4Config{
						{IpProtocol: "all"},
					},
				},
			},
			FirewallRule{
				Priority:      10001,
				Direction:     "INGRESS",
				Action:        "allow",
				RuleName:      fmt.Sprintf("fw-%s-svpc-10001-i-a-all", envCode),
				Description:   "Allow all ingress to the provided IP range.",
				EnableLogging: enableLogging,
				Match: FirewallRuleMatch{
					SrcIpRanges: subnetIPs,
					Layer4Configs: []FirewallLayer4Config{
						{IpProtocol: "all"},
					},
				},
			},
		)
	}

	return rules
}
