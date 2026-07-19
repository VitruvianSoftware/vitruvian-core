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

	vpc_sc "github.com/VitruvianSoftware/pulumi-library/go/pkg/vpc_service_controls"
)

type VpcFlowLogsConfig struct {
	AggregationInterval string  `json:"aggregation_interval"`
	FlowSampling        float64 `json:"flow_sampling"`
	Metadata            string  `json:"metadata"`
}

// NetSharedConfig holds the configuration for the shared/hub root of the
// networks stage, mirroring upstream 3-networks-hub-and-spoke/envs/shared
// variables.tf: the shared/global network settings (hub CIDRs, DNS hub,
// hierarchical firewall associations, transitivity toggle) plus the common
// identifiers shared with the spoke leaves.
type NetSharedConfig struct {
	HubProjectID                  string
	Region1                       string
	Region2                       string
	ParentID                      string
	Domain                        string
	PolicyID                      string
	OrgStackName                  string
	PscIP                         string
	BgpAsn                        int
	NatBgpAsn                     int
	NatNumAddresses               int
	TargetNameServers             []string
	VpcScMembers                  []string
	VpcScRestrictedServices       []string
	HubSubnet1Cidr                string
	HubSubnet2Cidr                string
	FirewallAssociations          []string
	FirewallPoliciesEnableLogging bool
	DnsEnableLogging              bool
	EnforceVpcSc                  bool
	EnableHubAndSpokeTransitivity bool
	HubNatEnabled                 bool
	VpcFlowLogs                   *VpcFlowLogsConfig
}

func loadNetSharedConfig(ctx *pulumi.Context) *NetSharedConfig {
	conf := config.New(ctx, "")

	c := &NetSharedConfig{
		HubProjectID: conf.Require("hub_project_id"),
		Region1:      conf.Get("region1"),
		Region2:      conf.Get("region2"),
		ParentID:     conf.Require("parent_id"),
		Domain:       conf.Get("domain"),
		PolicyID:     conf.Get("policy_id"),
		OrgStackName: conf.Get("org_stack_name"),
		PscIP:        conf.Get("psc_ip"),
	}
	conf.GetObject("vpc_sc_members", &c.VpcScMembers)
	conf.GetObject("vpc_sc_restricted_services", &c.VpcScRestrictedServices)
	conf.GetObject("target_name_servers", &c.TargetNameServers)
	conf.GetObject("firewall_associations", &c.FirewallAssociations)

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

	if val, err := conf.TryBool("enable_hub_and_spoke_transitivity"); err == nil {
		c.EnableHubAndSpokeTransitivity = val
	} else {
		c.EnableHubAndSpokeTransitivity = false
	}

	if val, err := conf.TryBool("hub_nat_enabled"); err == nil {
		c.HubNatEnabled = val
	} else {
		c.HubNatEnabled = false
	}

	if c.Region1 == "" {
		c.Region1 = "us-central1"
	}
	if c.Region2 == "" {
		c.Region2 = "us-west1"
	}
	if c.Domain == "" {
		c.Domain = "example.com."
	}
	if c.OrgStackName == "" {
		c.OrgStackName = "org"
	}
	if c.PscIP == "" {
		c.PscIP = "10.17.0.6"
	}
	if len(c.VpcScRestrictedServices) == 0 {
		c.VpcScRestrictedServices = vpc_sc.GetDefaultRestrictedServices()
	}
	if len(c.FirewallAssociations) == 0 {
		c.FirewallAssociations = []string{c.ParentID} // Fallback to parent
	}
	if len(c.TargetNameServers) == 0 {
		c.TargetNameServers = []string{"10.0.0.1"}
	}

	// Hub CIDRs — defaults derived from the upstream reference architecture
	if c.HubSubnet1Cidr == "" {
		c.HubSubnet1Cidr = "10.8.0.0/18"
	}
	if c.HubSubnet2Cidr == "" {
		c.HubSubnet2Cidr = "10.9.0.0/18"
	}

	c.BgpAsn = 64514
	c.NatBgpAsn = 64514
	c.NatNumAddresses = 2

	return c
}
