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

package networking

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type HierarchicalFirewallPolicyArgs struct {
	ParentID      pulumi.StringInput
	ShortName     string
	Description   string
	Associations  []string
	EnableLogging bool
}

type HierarchicalFirewallPolicy struct {
	pulumi.ResourceState
	Policy       *compute.FirewallPolicy
	Associations []*compute.FirewallPolicyAssociation
	Rules        []*compute.FirewallPolicyRule
}

func NewHierarchicalFirewallPolicy(ctx *pulumi.Context, name string, args *HierarchicalFirewallPolicyArgs, opts ...pulumi.ResourceOption) (*HierarchicalFirewallPolicy, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}

	component := &HierarchicalFirewallPolicy{}
	err := ctx.RegisterComponentResource("pkg:index:HierarchicalFirewallPolicy", name, component, opts...)
	if err != nil {
		return nil, err
	}

	fwPolicy, err := compute.NewFirewallPolicy(ctx, name+"-policy", &compute.FirewallPolicyArgs{
		Parent:      args.ParentID,
		ShortName:   pulumi.String(args.ShortName),
		Description: pulumi.String(args.Description),
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.Policy = fwPolicy

	for i, assocTarget := range args.Associations {
		assoc, err := compute.NewFirewallPolicyAssociation(ctx, fmt.Sprintf("%s-assoc-%d", name, i), &compute.FirewallPolicyAssociationArgs{
			FirewallPolicy:   fwPolicy.ID(),
			AttachmentTarget: pulumi.String(assocTarget),
			Name:             pulumi.String(fmt.Sprintf("%s-assoc-%d", args.ShortName, i)),
		}, pulumi.Parent(fwPolicy))
		if err != nil {
			return nil, err
		}
		component.Associations = append(component.Associations, assoc)
	}

	// Rule 1: Delegate RFC1918 ingress
	r1, err := compute.NewFirewallPolicyRule(ctx, name+"-delegate-rfc1918-ingress", &compute.FirewallPolicyRuleArgs{
		FirewallPolicy: fwPolicy.ID(),
		Priority:       pulumi.Int(500),
		Direction:      pulumi.String("INGRESS"),
		Action:         pulumi.String("goto_next"),
		Description:    pulumi.String("Delegate RFC1918 ingress"),
		Match: &compute.FirewallPolicyRuleMatchArgs{
			SrcIpRanges: pulumi.StringArray{
				pulumi.String("192.168.0.0/16"),
				pulumi.String("10.0.0.0/8"),
				pulumi.String("172.16.0.0/12"),
			},
			Layer4Configs: compute.FirewallPolicyRuleMatchLayer4ConfigArray{
				&compute.FirewallPolicyRuleMatchLayer4ConfigArgs{
					IpProtocol: pulumi.String("all"),
				},
			},
		},
		EnableLogging: pulumi.Bool(false),
	}, pulumi.Parent(fwPolicy))
	if err != nil {
		return nil, err
	}
	component.Rules = append(component.Rules, r1)

	// Rule 2: Delegate RFC1918 egress
	r2, err := compute.NewFirewallPolicyRule(ctx, name+"-delegate-rfc1918-egress", &compute.FirewallPolicyRuleArgs{
		FirewallPolicy: fwPolicy.ID(),
		Priority:       pulumi.Int(510),
		Direction:      pulumi.String("EGRESS"),
		Action:         pulumi.String("goto_next"),
		Description:    pulumi.String("Delegate RFC1918 egress"),
		Match: &compute.FirewallPolicyRuleMatchArgs{
			DestIpRanges: pulumi.StringArray{
				pulumi.String("192.168.0.0/16"),
				pulumi.String("10.0.0.0/8"),
				pulumi.String("172.16.0.0/12"),
			},
			Layer4Configs: compute.FirewallPolicyRuleMatchLayer4ConfigArray{
				&compute.FirewallPolicyRuleMatchLayer4ConfigArgs{
					IpProtocol: pulumi.String("all"),
				},
			},
		},
		EnableLogging: pulumi.Bool(false),
	}, pulumi.Parent(fwPolicy))
	if err != nil {
		return nil, err
	}
	component.Rules = append(component.Rules, r2)

	// Rule 3: Allow IAP SSH RDP
	r3, err := compute.NewFirewallPolicyRule(ctx, name+"-allow-iap-ssh-rdp", &compute.FirewallPolicyRuleArgs{
		FirewallPolicy: fwPolicy.ID(),
		Priority:       pulumi.Int(5000),
		Direction:      pulumi.String("INGRESS"),
		Action:         pulumi.String("allow"),
		Description:    pulumi.String("Always allow SSH and RDP from IAP"),
		Match: &compute.FirewallPolicyRuleMatchArgs{
			SrcIpRanges: pulumi.StringArray{
				pulumi.String("35.235.240.0/20"),
			},
			Layer4Configs: compute.FirewallPolicyRuleMatchLayer4ConfigArray{
				&compute.FirewallPolicyRuleMatchLayer4ConfigArgs{
					IpProtocol: pulumi.String("tcp"),
					Ports: pulumi.StringArray{
						pulumi.String("22"),
						pulumi.String("3389"),
					},
				},
			},
		},
		EnableLogging: pulumi.Bool(args.EnableLogging),
	}, pulumi.Parent(fwPolicy))
	if err != nil {
		return nil, err
	}
	component.Rules = append(component.Rules, r3)

	// Rule 4: Allow Windows Activation
	r4, err := compute.NewFirewallPolicyRule(ctx, name+"-allow-windows-activation", &compute.FirewallPolicyRuleArgs{
		FirewallPolicy: fwPolicy.ID(),
		Priority:       pulumi.Int(5100),
		Direction:      pulumi.String("EGRESS"),
		Action:         pulumi.String("allow"),
		Description:    pulumi.String("Always outgoing Windows KMS traffic"),
		Match: &compute.FirewallPolicyRuleMatchArgs{
			DestIpRanges: pulumi.StringArray{
				pulumi.String("35.190.247.13/32"),
			},
			Layer4Configs: compute.FirewallPolicyRuleMatchLayer4ConfigArray{
				&compute.FirewallPolicyRuleMatchLayer4ConfigArgs{
					IpProtocol: pulumi.String("tcp"),
					Ports: pulumi.StringArray{
						pulumi.String("1688"),
					},
				},
			},
		},
		EnableLogging: pulumi.Bool(args.EnableLogging),
	}, pulumi.Parent(fwPolicy))
	if err != nil {
		return nil, err
	}
	component.Rules = append(component.Rules, r4)

	// Rule 5: Allow Google HBS and HCS
	r5, err := compute.NewFirewallPolicyRule(ctx, name+"-allow-google-hbs-hcs", &compute.FirewallPolicyRuleArgs{
		FirewallPolicy: fwPolicy.ID(),
		Priority:       pulumi.Int(5200),
		Direction:      pulumi.String("INGRESS"),
		Action:         pulumi.String("allow"),
		Description:    pulumi.String("Always allow connections from Google load balancer and health check ranges"),
		Match: &compute.FirewallPolicyRuleMatchArgs{
			SrcIpRanges: pulumi.StringArray{
				pulumi.String("35.191.0.0/16"),
				pulumi.String("130.211.0.0/22"),
				pulumi.String("209.85.152.0/22"),
				pulumi.String("209.85.204.0/22"),
			},
			Layer4Configs: compute.FirewallPolicyRuleMatchLayer4ConfigArray{
				&compute.FirewallPolicyRuleMatchLayer4ConfigArgs{
					IpProtocol: pulumi.String("tcp"),
					Ports: pulumi.StringArray{
						pulumi.String("80"),
						pulumi.String("443"),
					},
				},
			},
		},
		EnableLogging: pulumi.Bool(args.EnableLogging),
	}, pulumi.Parent(fwPolicy))
	if err != nil {
		return nil, err
	}
	component.Rules = append(component.Rules, r5)

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"policyId": fwPolicy.ID(),
	})

	return component, nil
}
