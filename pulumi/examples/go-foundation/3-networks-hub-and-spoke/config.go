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
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/accesscontextmanager"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"

	vpc_sc "github.com/VitruvianSoftware/pulumi-library/go/pkg/vpc_service_controls"
)

type VpcFlowLogsConfig struct {
	AggregationInterval string  `json:"aggregation_interval"`
	FlowSampling        float64 `json:"flow_sampling"`
	Metadata            string  `json:"metadata"`
}

type NetConfig struct {
	Env                           string
	EnvCode                       string
	HubProjectID                  string
	SpokeProjectID                string
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
	VpcScProjects                 []string
	VpcScRestrictedServices       []string
	VpcScIngressPolicies          accesscontextmanager.ServicePerimeterStatusIngressPolicyArray
	VpcScEgressPolicies           accesscontextmanager.ServicePerimeterStatusEgressPolicyArray
	VpcScIngressPoliciesDryRun    accesscontextmanager.ServicePerimeterSpecIngressPolicyArray
	VpcScEgressPoliciesDryRun     accesscontextmanager.ServicePerimeterSpecEgressPolicyArray
	SpokeSubnet1Cidr              string
	SpokeSubnet2Cidr              string
	SpokeProxy1Cidr               string
	SpokeProxy2Cidr               string
	SpokeGkePod1Cidr              string
	SpokeGkeSvc1Cidr              string
	SpokeGkePod2Cidr              string
	SpokeGkeSvc2Cidr              string
	HubSubnet1Cidr                string
	HubSubnet2Cidr                string
	FirewallAssociations          []string
	FirewallPoliciesEnableLogging bool
	DnsEnableLogging              bool
	EnforceVpcSc                  bool
	EnableHubAndSpokeTransitivity bool
	HubNatEnabled                 bool
	NatEnabled                    bool
	WindowsActivationEnabled      bool
	VpcFlowLogs                   *VpcFlowLogsConfig
}

func loadNetConfig(ctx *pulumi.Context) *NetConfig {
	conf := config.New(ctx, "")

	c := &NetConfig{
		Env:            conf.Require("env"),
		EnvCode:        conf.Require("env_code"),
		HubProjectID:   conf.Require("hub_project_id"),
		SpokeProjectID: conf.Get("spoke_project_id"),
		Region1:        conf.Get("region1"),
		Region2:        conf.Get("region2"),
		ParentID:       conf.Require("parent_id"),
		Domain:         conf.Get("domain"),
		PolicyID:       conf.Get("policy_id"),
		OrgStackName:   conf.Get("org_stack_name"),
		PscIP:          conf.Get("psc_ip"),
	}
	conf.GetObject("vpc_sc_members", &c.VpcScMembers)
	conf.GetObject("vpc_sc_projects", &c.VpcScProjects)
	conf.GetObject("vpc_sc_restricted_services", &c.VpcScRestrictedServices)
	conf.GetObject("vpc_sc_ingress_policies", &c.VpcScIngressPolicies)
	conf.GetObject("vpc_sc_egress_policies", &c.VpcScEgressPolicies)
	conf.GetObject("vpc_sc_ingress_policies_dry_run", &c.VpcScIngressPoliciesDryRun)
	conf.GetObject("vpc_sc_egress_policies_dry_run", &c.VpcScEgressPoliciesDryRun)
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

	if val, err := conf.TryBool("nat_enabled"); err == nil {
		c.NatEnabled = val
	} else {
		c.NatEnabled = false
	}

	if val, err := conf.TryBool("windows_activation_enabled"); err == nil {
		c.WindowsActivationEnabled = val
	} else {
		c.WindowsActivationEnabled = false
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

	// Assign CIDRs based on EnvCode to avoid peering overlaps
	// Defaults derived from reference architecture
	if c.HubSubnet1Cidr == "" {
		c.HubSubnet1Cidr = "10.8.0.0/18"
	}
	if c.HubSubnet2Cidr == "" {
		c.HubSubnet2Cidr = "10.9.0.0/18"
	}

	if c.EnvCode == "d" {
		c.SpokeSubnet1Cidr = "10.8.64.0/18"
		c.SpokeSubnet2Cidr = "10.9.64.0/18"
		c.SpokeProxy1Cidr = "10.26.2.0/23"
		c.SpokeProxy2Cidr = "10.27.2.0/23"
		c.SpokeGkePod1Cidr = "100.72.64.0/18"
		c.SpokeGkeSvc1Cidr = "100.73.64.0/18"
		c.SpokeGkePod2Cidr = "100.74.64.0/18"
		c.SpokeGkeSvc2Cidr = "100.75.64.0/18"
	} else if c.EnvCode == "n" {
		c.SpokeSubnet1Cidr = "10.8.128.0/18"
		c.SpokeSubnet2Cidr = "10.9.128.0/18"
		c.SpokeProxy1Cidr = "10.26.4.0/23"
		c.SpokeProxy2Cidr = "10.27.4.0/23"
		c.SpokeGkePod1Cidr = "100.72.128.0/18"
		c.SpokeGkeSvc1Cidr = "100.73.128.0/18"
		c.SpokeGkePod2Cidr = "100.74.128.0/18"
		c.SpokeGkeSvc2Cidr = "100.75.128.0/18"
	} else if c.EnvCode == "p" {
		c.SpokeSubnet1Cidr = "10.8.192.0/18"
		c.SpokeSubnet2Cidr = "10.9.192.0/18"
		c.SpokeProxy1Cidr = "10.26.6.0/23"
		c.SpokeProxy2Cidr = "10.27.6.0/23"
		c.SpokeGkePod1Cidr = "100.72.192.0/18"
		c.SpokeGkeSvc1Cidr = "100.73.192.0/18"
		c.SpokeGkePod2Cidr = "100.74.192.0/18"
		c.SpokeGkeSvc2Cidr = "100.75.192.0/18"
	} else {
		// Fallback
		c.SpokeSubnet1Cidr = "10.8.64.0/18"
		c.SpokeSubnet2Cidr = "10.9.64.0/18"
		c.SpokeProxy1Cidr = "10.26.2.0/23"
		c.SpokeProxy2Cidr = "10.27.2.0/23"
		c.SpokeGkePod1Cidr = "100.72.64.0/18"
		c.SpokeGkeSvc1Cidr = "100.73.64.0/18"
		c.SpokeGkePod2Cidr = "100.74.64.0/18"
		c.SpokeGkeSvc2Cidr = "100.75.64.0/18"
	}

	c.BgpAsn = 64514
	c.NatBgpAsn = 64514
	c.NatNumAddresses = 2

	return c
}
