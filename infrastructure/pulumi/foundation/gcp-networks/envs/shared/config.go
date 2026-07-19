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
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"

	vpc_sc "github.com/VitruvianSoftware/pulumi-library/go/pkg/vpc_service_controls"
)

// VpcFlowLogsConfig mirrors the upstream VPC flow logs configuration.
type VpcFlowLogsConfig struct {
	AggregationInterval string  `json:"aggregation_interval"`
	FlowSampling        float64 `json:"flow_sampling"`
	Metadata            string  `json:"metadata"`
}

// NetSharedConfig holds the configuration for the shared/hub root of the
// networks stage. This mirrors the upstream Terraform foundation's
// 3-networks-hub-and-spoke/envs/shared variables.tf: the shared/global
// network settings (hub CIDRs, DNS hub, hierarchical firewall associations,
// transitivity toggle) plus the common identifiers shared with the spoke
// leaves.
type NetSharedConfig struct {
	// Core identifiers
	OrgID    string
	ParentID string // Network folder ID (from 1-org)

	// Regions
	Region1 string // Primary region
	Region2 string // Secondary region

	// Cross-stage references
	OrgStackName string

	// DNS (hub forwarding zone)
	Domain            string
	TargetNameServers []string
	DnsEnableLogging  bool

	// Firewall
	FirewallPoliciesEnableLogging bool

	// Hierarchical Firewall folder associations (matching upstream 6-folder pattern)
	HierarchicalFwAssociations []string

	// PSC
	PscIP string

	// BGP / NAT
	BgpAsn          int
	NatBgpAsn       int
	NatNumAddresses int

	// Feature toggles (matching upstream defaults)
	EnableHubAndSpokeTransitivity bool // default false, matching upstream
	HubNatEnabled                 bool // default false, matching upstream
	WindowsActivationEnabled      bool // default false, matching upstream

	// VPC Flow Logs
	VpcFlowLogs *VpcFlowLogsConfig

	// VPC Service Controls
	VpcScRestrictedServices []string
	EnforceVpcSc            bool
	PolicyID                string   // Override ACM policy ID (if not using StackReference)
	VpcScMembers            []string // Members to add to access levels

	// Hub CIDRs — matching upstream: 10.8.0.0/18 (R1), 10.9.0.0/18 (R2)
	HubSubnet1Cidr string
	HubSubnet2Cidr string
	HubProxy1Cidr  string // Hub proxy-only subnet R1
	HubProxy2Cidr  string // Hub proxy-only subnet R2
}

func loadNetSharedConfig(ctx *pulumi.Context) *NetSharedConfig {
	conf := config.New(ctx, "")

	c := &NetSharedConfig{
		OrgID:        conf.Require("org_id"),
		ParentID:     conf.Get("parent_id"),
		Region1:      conf.Get("default_region"),
		Region2:      conf.Get("secondary_region"),
		OrgStackName: conf.Get("org_stack_name"),
		Domain:       conf.Get("domain"),
		PscIP:        conf.Get("psc_ip"),
		PolicyID:     conf.Get("access_context_manager_policy_id"),
	}

	// Structured config
	conf.GetObject("target_name_servers", &c.TargetNameServers)
	conf.GetObject("vpc_sc_restricted_services", &c.VpcScRestrictedServices)
	conf.GetObject("vpc_sc_members", &c.VpcScMembers)

	conf.GetObject("hierarchical_fw_associations", &c.HierarchicalFwAssociations)

	var flowLogs VpcFlowLogsConfig
	if err := conf.GetObject("vpc_flow_logs", &flowLogs); err == nil {
		c.VpcFlowLogs = &flowLogs
	} else {
		// Default matches TF upstream default
		c.VpcFlowLogs = &VpcFlowLogsConfig{
			AggregationInterval: "INTERVAL_5_SEC",
			FlowSampling:        0.5,
			Metadata:            "INCLUDE_ALL_METADATA",
		}
	}

	// Boolean config with defaults
	if val, err := conf.TryBool("firewall_policies_enable_logging"); err == nil {
		c.FirewallPoliciesEnableLogging = val
	} else {
		c.FirewallPoliciesEnableLogging = true // Default to true matching TF
	}

	if val, err := conf.TryBool("dns_enable_logging"); err == nil {
		c.DnsEnableLogging = val
	} else {
		c.DnsEnableLogging = true
	}

	if val, err := conf.TryBool("enforce_vpcsc"); err == nil {
		c.EnforceVpcSc = val
	} else {
		c.EnforceVpcSc = false // TF defaults enforce_vpcsc=false (dry-run first)
	}

	// Feature toggles — all default false to match upstream TF defaults
	if val, err := conf.TryBool("enable_hub_and_spoke_transitivity"); err == nil {
		c.EnableHubAndSpokeTransitivity = val
	}
	if val, err := conf.TryBool("hub_nat_enabled"); err == nil {
		c.HubNatEnabled = val
	}
	if val, err := conf.TryBool("windows_activation_enabled"); err == nil {
		c.WindowsActivationEnabled = val
	}

	// Apply defaults
	if c.Region1 == "" {
		c.Region1 = "us-central1"
	}
	if c.Region2 == "" {
		c.Region2 = "us-south1"
	}
	if c.Domain == "" {
		c.Domain = "example.com."
	}
	if c.OrgStackName == "" {
		c.OrgStackName = "ipv1337/foundation-org-shared/production"
	}
	if c.PscIP == "" {
		c.PscIP = "10.17.0.6"
	}
	if len(c.VpcScRestrictedServices) == 0 {
		c.VpcScRestrictedServices = vpc_sc.GetDefaultRestrictedServices()
	}
	if len(c.TargetNameServers) == 0 {
		c.TargetNameServers = []string{"10.0.0.1"}
	}

	// Hub CIDRs — matching upstream TF hub-and-spoke 10.8.0.0/18 + 10.9.0.0/18
	if c.HubSubnet1Cidr == "" {
		c.HubSubnet1Cidr = "10.8.0.0/18"
	}
	if c.HubSubnet2Cidr == "" {
		c.HubSubnet2Cidr = "10.9.0.0/18"
	}
	// Hub proxy-only subnets — matching upstream 10.26.0.0/23 + 10.27.0.0/23
	if c.HubProxy1Cidr == "" {
		c.HubProxy1Cidr = "10.26.0.0/23"
	}
	if c.HubProxy2Cidr == "" {
		c.HubProxy2Cidr = "10.27.0.0/23"
	}

	c.BgpAsn = 64514
	c.NatBgpAsn = 64514
	c.NatNumAddresses = 2

	return c
}
