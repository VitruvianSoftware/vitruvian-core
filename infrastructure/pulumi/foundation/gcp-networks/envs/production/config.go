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
	"os"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"

	vpc_sc "github.com/VitruvianSoftware/pulumi-library/go/pkg/vpc_service_controls"
)

// VpcFlowLogsConfig mirrors the upstream VPC flow logs configuration.
type VpcFlowLogsConfig struct {
	AggregationInterval string  `json:"aggregation_interval"`
	FlowSampling        float64 `json:"flow_sampling"`
	Metadata            string  `json:"metadata"`
}

// NetConfig holds the per-environment (spoke) configuration for the networks
// stage. This mirrors the upstream Terraform foundation's
// 3-networks-hub-and-spoke/envs/<env> variables.tf. The environment identity
// and the spoke CIDR plan are pinned as consts in this leaf's main.go; the
// shared/hub settings live in the sibling envs/shared leaf.
type NetConfig struct {
	// Core identifiers
	OrgID string

	// Regions
	Region1 string // Primary region
	Region2 string // Secondary region

	// Cross-stage references
	OrgStackName string

	// DNS (spoke peering zone to the DNS hub)
	Domain           string
	DnsEnableLogging bool

	// Firewall
	FirewallPoliciesEnableLogging bool

	// PSC
	PscIP string

	// NAT
	NatBgpAsn       int
	NatNumAddresses int

	// Feature toggles (matching upstream defaults)
	NatEnabled               bool // default false, matching upstream (spoke NAT)
	WindowsActivationEnabled bool // default false, matching upstream

	// VPC Flow Logs
	VpcFlowLogs *VpcFlowLogsConfig

	// VPC Service Controls
	VpcScRestrictedServices []string
	EnforceVpcSc            bool
	PolicyID                string   // Override ACM policy ID (if not using StackReference)
	VpcScMembers            []string // Members to add to access levels
}

func loadNetConfig(ctx *pulumi.Context) *NetConfig {
	conf := config.New(ctx, "")

	c := &NetConfig{
		OrgID:        conf.Require("org_id"),
		Region1:      envOrConfig("NETWORKS_DEFAULT_REGION", conf, "default_region"),
		Region2:      envOrConfig("NETWORKS_SECONDARY_REGION", conf, "secondary_region"),
		OrgStackName: conf.Get("org_stack_name"),
		Domain:       conf.Get("domain"),
		PscIP:        conf.Get("psc_ip"),
		PolicyID:     conf.Get("access_context_manager_policy_id"),
	}

	// Structured config
	conf.GetObject("vpc_sc_restricted_services", &c.VpcScRestrictedServices)
	conf.GetObject("vpc_sc_members", &c.VpcScMembers)

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
	if val, err := conf.TryBool("nat_enabled"); err == nil {
		c.NatEnabled = val
	}
	if val, err := conf.TryBool("windows_activation_enabled"); err == nil {
		c.WindowsActivationEnabled = val
	}

	// Apply defaults
	// Region defaults. Source of truth = gcp-bootstrap common_config
	// (default_region=us-central1, default_region_2=us-west1). The deploy CONSUMES
	// those from bootstrap: foundation-net-deploy reads bootstrap's stack output and
	// injects NETWORKS_DEFAULT_REGION / NETWORKS_SECONDARY_REGION, which win here
	// (see envOrConfig below). We can't read them via an in-program StackReference
	// because a StackReference output is async and the region is baked into LOGICAL
	// resource names (subnets via network/v2 networking.go "name+"-"+s.Name", the
	// hub cloud routers "hub-cr-<region>-..."), which must be static strings. The
	// committed config / const fallback below is the preview + local value and is
	// GUARDED in config_test.go to equal the canonical bootstrap regions, so preview
	// and deploy agree and a silent drift (how the secondary became us-south1) fails CI.
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
		c.OrgStackName = "ipv1337/foundation-org-shared/production"
	}
	if c.PscIP == "" {
		c.PscIP = "10.17.0.6"
	}
	if len(c.VpcScRestrictedServices) == 0 {
		c.VpcScRestrictedServices = vpc_sc.GetDefaultRestrictedServices()
	}

	c.NatBgpAsn = 64514
	c.NatNumAddresses = 2

	return c
}

// envOrConfig returns the environment variable env when set (non-empty), else the
// Pulumi config value at key. The deploy injects the bootstrap-sourced region via
// env (see the Region defaults note in loadNetConfig); config/const is the fallback.
func envOrConfig(env string, conf *config.Config, key string) string {
	if v := os.Getenv(env); v != "" {
		return v
	}
	return conf.Get(key)
}
