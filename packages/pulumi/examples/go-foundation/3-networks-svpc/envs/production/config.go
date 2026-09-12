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

// NetConfig holds the per-environment configuration, mirroring upstream
// 3-networks-svpc/envs/<env> variables.tf. The environment identity is pinned
// as consts in this leaf's main.go; the shared/global settings (hierarchical
// firewall) live in the sibling envs/shared leaf.
type NetConfig struct {
	ProjectID                     string
	Region1                       string
	Region2                       string
	PolicyID                      string
	OrgStackName                  string
	DNSProjectID                  string
	Domain                        string
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
	FirewallPoliciesEnableLogging bool
	DnsEnableLogging              bool
	EnforceVpcSc                  bool
	EnableDedicatedInterconnect   bool
	NatEnabled                    bool
	WindowsActivationEnabled      bool
	VpcFlowLogs                   *VpcFlowLogsConfig
}

func loadNetConfig(ctx *pulumi.Context) *NetConfig {
	conf := config.New(ctx, "")

	c := &NetConfig{
		ProjectID:    conf.Require("project_id"),
		Region1:      conf.Get("region1"),
		Region2:      conf.Get("region2"),
		PolicyID:     conf.Get("policy_id"),
		OrgStackName: conf.Get("org_stack_name"),
		DNSProjectID: conf.Get("dns_project_id"),
		Domain:       conf.Get("domain"),
		PscIP:        conf.Get("psc_ip"),
	}
	conf.GetObject("vpc_sc_members", &c.VpcScMembers)
	conf.GetObject("vpc_sc_projects", &c.VpcScProjects)
	conf.GetObject("vpc_sc_restricted_services", &c.VpcScRestrictedServices)
	conf.GetObject("vpc_sc_ingress_policies", &c.VpcScIngressPolicies)
	conf.GetObject("vpc_sc_egress_policies", &c.VpcScEgressPolicies)
	conf.GetObject("vpc_sc_ingress_policies_dry_run", &c.VpcScIngressPoliciesDryRun)
	conf.GetObject("vpc_sc_egress_policies_dry_run", &c.VpcScEgressPoliciesDryRun)
	conf.GetObject("target_name_servers", &c.TargetNameServers)

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

	if val, err := conf.TryBool("enable_dedicated_interconnect"); err == nil {
		c.EnableDedicatedInterconnect = val
	} else {
		c.EnableDedicatedInterconnect = false
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

	if c.EnableDedicatedInterconnect {
		c.VpcScEgressPolicies = append(c.VpcScEgressPolicies, accesscontextmanager.ServicePerimeterStatusEgressPolicyArgs{
			EgressFrom: accesscontextmanager.ServicePerimeterStatusEgressPolicyEgressFromArgs{
				IdentityType: pulumi.String("ANY_IDENTITY"),
			},
			EgressTo: accesscontextmanager.ServicePerimeterStatusEgressPolicyEgressToArgs{
				Resources: pulumi.StringArray{pulumi.String("*")},
				Operations: accesscontextmanager.ServicePerimeterStatusEgressPolicyEgressToOperationArray{
					&accesscontextmanager.ServicePerimeterStatusEgressPolicyEgressToOperationArgs{
						ServiceName: pulumi.String("compute.googleapis.com"),
						MethodSelectors: accesscontextmanager.ServicePerimeterStatusEgressPolicyEgressToOperationMethodSelectorArray{
							&accesscontextmanager.ServicePerimeterStatusEgressPolicyEgressToOperationMethodSelectorArgs{
								Method: pulumi.String("*"),
							},
						},
					},
				},
			},
		})
		c.VpcScEgressPoliciesDryRun = append(c.VpcScEgressPoliciesDryRun, accesscontextmanager.ServicePerimeterSpecEgressPolicyArgs{
			EgressFrom: accesscontextmanager.ServicePerimeterSpecEgressPolicyEgressFromArgs{
				IdentityType: pulumi.String("ANY_IDENTITY"),
			},
			EgressTo: accesscontextmanager.ServicePerimeterSpecEgressPolicyEgressToArgs{
				Resources: pulumi.StringArray{pulumi.String("*")},
				Operations: accesscontextmanager.ServicePerimeterSpecEgressPolicyEgressToOperationArray{
					&accesscontextmanager.ServicePerimeterSpecEgressPolicyEgressToOperationArgs{
						ServiceName: pulumi.String("compute.googleapis.com"),
						MethodSelectors: accesscontextmanager.ServicePerimeterSpecEgressPolicyEgressToOperationMethodSelectorArray{
							&accesscontextmanager.ServicePerimeterSpecEgressPolicyEgressToOperationMethodSelectorArgs{
								Method: pulumi.String("*"),
							},
						},
					},
				},
			},
		})
	}
	if len(c.TargetNameServers) == 0 {
		c.TargetNameServers = []string{"10.0.0.1"}
	}

	c.BgpAsn = 64514
	c.NatBgpAsn = 64514
	c.NatNumAddresses = 2

	return c
}
