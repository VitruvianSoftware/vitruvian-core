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

// Package network_firewall_policy provides a data-driven NetworkFirewallPolicy
// component for creating GCP network firewall policies with associations and rules.
// Mirrors: terraform-google-modules/network/google//modules/network-firewall-policy
package network_firewall_policy

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Layer4Config mirrors a single layer4_configs entry.
type Layer4Config struct {
	IpProtocol string
	Ports      []string
}

// SecureTag represents a secure tag reference for firewall rules.
type SecureTag struct {
	Name string
}

// FirewallRule defines a single firewall policy rule.
type FirewallRule struct {
	RuleName              string
	Description           string
	Direction             string // "INGRESS" or "EGRESS"
	Action                string // "allow", "deny", "goto_next"
	Priority              int
	Ranges                []string
	TargetSecureTags      []SecureTag
	TargetServiceAccounts []string
	EnableLogging         bool
	Layer4Configs         []Layer4Config
}

// NetworkFirewallPolicyArgs defines the arguments for the component.
type NetworkFirewallPolicyArgs struct {
	Project     pulumi.StringInput
	Name        string
	Description string
	Network     pulumi.StringInput
	Rules       []FirewallRule
}

// NetworkFirewallPolicy creates a GCP network firewall policy with rules and association.
type NetworkFirewallPolicy struct {
	pulumi.ResourceState
	PolicyID   pulumi.IDOutput
	PolicyName pulumi.StringOutput
}

// NewNetworkFirewallPolicy creates a new network firewall policy component.
func NewNetworkFirewallPolicy(ctx *pulumi.Context, name string, args *NetworkFirewallPolicyArgs, opts ...pulumi.ResourceOption) (*NetworkFirewallPolicy, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}

	component := &NetworkFirewallPolicy{}
	err := ctx.RegisterComponentResource("pkg:index:NetworkFirewallPolicy", name, component, opts...)
	if err != nil {
		return nil, err
	}

	policy, err := compute.NewNetworkFirewallPolicy(ctx, name+"-policy", &compute.NetworkFirewallPolicyArgs{
		Project:     args.Project,
		Name:        pulumi.String(args.Name),
		Description: pulumi.String(args.Description),
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.PolicyID = policy.ID()
	component.PolicyName = policy.Name

	// Associate with the target network
	_, err = compute.NewNetworkFirewallPolicyAssociation(ctx, name+"-assoc", &compute.NetworkFirewallPolicyAssociationArgs{
		Project:          args.Project,
		FirewallPolicy:   policy.Name,
		AttachmentTarget: args.Network,
		Name:             pulumi.Sprintf("%s-assoc", args.Name),
	}, pulumi.Parent(policy))
	if err != nil {
		return nil, err
	}

	// Create rules
	for i, rule := range args.Rules {
		matchArgs := &compute.NetworkFirewallPolicyRuleMatchArgs{}
		if rule.Direction == "INGRESS" {
			var ranges pulumi.StringArray
			for _, r := range rule.Ranges {
				ranges = append(ranges, pulumi.String(r))
			}
			matchArgs.SrcIpRanges = ranges
		} else {
			var ranges pulumi.StringArray
			for _, r := range rule.Ranges {
				ranges = append(ranges, pulumi.String(r))
			}
			matchArgs.DestIpRanges = ranges
		}

		var l4Configs compute.NetworkFirewallPolicyRuleMatchLayer4ConfigArray
		for _, l4 := range rule.Layer4Configs {
			l4Args := &compute.NetworkFirewallPolicyRuleMatchLayer4ConfigArgs{
				IpProtocol: pulumi.String(l4.IpProtocol),
			}
			if len(l4.Ports) > 0 {
				var ports pulumi.StringArray
				for _, p := range l4.Ports {
					ports = append(ports, pulumi.String(p))
				}
				l4Args.Ports = ports
			}
			l4Configs = append(l4Configs, l4Args)
		}
		matchArgs.Layer4Configs = l4Configs

		ruleArgs := &compute.NetworkFirewallPolicyRuleArgs{
			Project:        args.Project,
			FirewallPolicy: policy.Name,
			RuleName:       pulumi.String(rule.RuleName),
			Description:    pulumi.String(rule.Description),
			Direction:      pulumi.String(rule.Direction),
			Action:         pulumi.String(rule.Action),
			Priority:       pulumi.Int(rule.Priority),
			EnableLogging:  pulumi.Bool(rule.EnableLogging),
			Match:          matchArgs,
		}

		if len(rule.TargetSecureTags) > 0 {
			var tags compute.NetworkFirewallPolicyRuleTargetSecureTagArray
			for _, t := range rule.TargetSecureTags {
				tags = append(tags, &compute.NetworkFirewallPolicyRuleTargetSecureTagArgs{
					Name: pulumi.String(t.Name),
				})
			}
			ruleArgs.TargetSecureTags = tags
		}

		if len(rule.TargetServiceAccounts) > 0 {
			var sas pulumi.StringArray
			for _, sa := range rule.TargetServiceAccounts {
				sas = append(sas, pulumi.String(sa))
			}
			ruleArgs.TargetServiceAccounts = sas
		}

		_, err = compute.NewNetworkFirewallPolicyRule(ctx, fmt.Sprintf("%s-rule-%d", name, i), ruleArgs, pulumi.Parent(policy))
		if err != nil {
			return nil, err
		}
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"policyName": policy.Name,
	})

	return component, nil
}
