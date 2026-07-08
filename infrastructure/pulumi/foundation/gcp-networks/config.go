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

// NetConfig holds all configuration for the networks stage.
// This mirrors the upstream Terraform foundation's 3-networks-hub-and-spoke
// variables.tf and the Go example foundation's NetConfig struct.
//
// In the monorepo promotion model, each Pulumi stack (development,
// nonproduction, production) deploys exactly one spoke VPC. The development
// stack additionally deploys the shared hub VPC.
type NetConfig struct {
	// Environment identity (from per-stack config)
	Env     string // e.g. "development", "nonproduction", "production"
	EnvCode string // e.g. "d", "n", "p"

	// Core identifiers
	OrgID    string
	ParentID string // Network folder ID (from 1-org)

	// Hub project (from 1-org, enable_hub_and_spoke=true)
	HubProjectID string

	// Regions
	Region1 string // Primary region
	Region2 string // Secondary region

	// Cross-stage references
	OrgStackName string

	// DNS
	Domain            string
	TargetNameServers []string
	DnsEnableLogging  bool

	// Firewall
	FirewallPoliciesEnableLogging bool

	// PSC
	PscIP string

	// BGP / NAT
	BgpAsn          int
	NatBgpAsn       int
	NatNumAddresses int

	// VPC Flow Logs
	VpcFlowLogs *VpcFlowLogsConfig

	// VPC Service Controls
	VpcScRestrictedServices []string
	EnforceVpcSc            bool

	// Per-environment spoke CIDRs (assigned based on EnvCode)
	SpokeSubnet1Cidr string
	SpokeSubnet2Cidr string
	SpokeProxy1Cidr  string
	SpokeProxy2Cidr  string
	SpokeGkePod1Cidr string
	SpokeGkeSvc1Cidr string
	SpokeGkePod2Cidr string
	SpokeGkeSvc2Cidr string

	// Hub CIDRs (shared, only used by development stack)
	HubSubnet1Cidr string
	HubSubnet2Cidr string
}

func loadNetConfig(ctx *pulumi.Context) *NetConfig {
	conf := config.New(ctx, "")

	c := &NetConfig{
		Env:          conf.Require("env"),
		EnvCode:      conf.Require("env_code"),
		OrgID:        conf.Require("org_id"),
		HubProjectID: conf.Require("hub_project_id"),
		ParentID:     conf.Get("parent_id"),
		Region1:      conf.Get("default_region"),
		Region2:      conf.Get("secondary_region"),
		OrgStackName: conf.Get("org_stack_name"),
		Domain:       conf.Get("domain"),
		PscIP:        conf.Get("psc_ip"),
	}

	// Structured config
	conf.GetObject("target_name_servers", &c.TargetNameServers)
	conf.GetObject("vpc_sc_restricted_services", &c.VpcScRestrictedServices)

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
		c.OrgStackName = "ipv1337/foundation-org/production"
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

	// Hub CIDRs (shared across all envs)
	if c.HubSubnet1Cidr == "" {
		c.HubSubnet1Cidr = "10.0.64.0/18"
	}
	if c.HubSubnet2Cidr == "" {
		c.HubSubnet2Cidr = "10.1.64.0/18"
	}

	// Assign spoke CIDRs based on EnvCode to avoid peering overlaps.
	// Defaults derived from the reference architecture.
	switch c.EnvCode {
	case "d":
		c.SpokeSubnet1Cidr = "10.8.64.0/18"
		c.SpokeSubnet2Cidr = "10.9.64.0/18"
		c.SpokeProxy1Cidr = "10.26.2.0/23"
		c.SpokeProxy2Cidr = "10.27.2.0/23"
		c.SpokeGkePod1Cidr = "100.72.64.0/18"
		c.SpokeGkeSvc1Cidr = "100.73.64.0/18"
		c.SpokeGkePod2Cidr = "100.74.64.0/18"
		c.SpokeGkeSvc2Cidr = "100.75.64.0/18"
	case "n":
		c.SpokeSubnet1Cidr = "10.8.128.0/18"
		c.SpokeSubnet2Cidr = "10.9.128.0/18"
		c.SpokeProxy1Cidr = "10.26.4.0/23"
		c.SpokeProxy2Cidr = "10.27.4.0/23"
		c.SpokeGkePod1Cidr = "100.72.128.0/18"
		c.SpokeGkeSvc1Cidr = "100.73.128.0/18"
		c.SpokeGkePod2Cidr = "100.74.128.0/18"
		c.SpokeGkeSvc2Cidr = "100.75.128.0/18"
	case "p":
		c.SpokeSubnet1Cidr = "10.8.192.0/18"
		c.SpokeSubnet2Cidr = "10.9.192.0/18"
		c.SpokeProxy1Cidr = "10.26.6.0/23"
		c.SpokeProxy2Cidr = "10.27.6.0/23"
		c.SpokeGkePod1Cidr = "100.72.192.0/18"
		c.SpokeGkeSvc1Cidr = "100.73.192.0/18"
		c.SpokeGkePod2Cidr = "100.74.192.0/18"
		c.SpokeGkeSvc2Cidr = "100.75.192.0/18"
	default:
		// Fallback to development CIDRs
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
