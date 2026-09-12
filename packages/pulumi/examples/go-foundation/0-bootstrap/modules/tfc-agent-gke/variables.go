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

// Mirrors: 0-bootstrap/modules/tfc-agent-gke/variables.tf in the TF
// foundation — the module's input surface and defaults. See the package doc
// in main.go for the TFC → Pulumi Cloud adaptation of the tfc_agent_*
// variables.

package tfcagentgke

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// TfcAgentGkeArgs mirrors upstream variables.tf. Fields upstream declares but
// never consumes (ProjectNumber, MachineType, Min/MaxNodeCount — Autopilot
// manages nodes) are kept for input parity and documented as unused.
type TfcAgentGkeArgs struct {
	// ProjectID hosts the agent cluster.
	ProjectID pulumi.StringInput
	// ProjectNumber is declared upstream but unused by the module body;
	// kept for input parity.
	ProjectNumber pulumi.StringInput
	// Region defaults to "us-central1".
	Region string
	// Zones is declared upstream but unused by the regional Autopilot
	// cluster; kept for input parity.
	Zones []string
	// NatBgpAsn defaults to 64514.
	NatBgpAsn int
	// NatEnabled defaults to true (nil = true, mirroring upstream).
	NatEnabled *bool
	// NatNumAddresses defaults to 2.
	NatNumAddresses int
	// IPRangePodsName defaults to "ip-range-pods".
	IPRangePodsName string
	// IPRangeServicesName defaults to "ip-range-scv".
	IPRangeServicesName string
	// IPRangePodsCidr defaults to "192.168.0.0/18".
	IPRangePodsCidr string
	// IPRangeServicesCider defaults to "192.168.64.0/18" ([sic] upstream
	// variable name is "ip_range_services_cider").
	IPRangeServicesCider string
	// NetworkName defaults to "tfc-agent-network".
	NetworkName string
	// SubnetIP defaults to "10.0.0.0/17".
	SubnetIP string
	// SubnetName defaults to "tfc-agent-subnet".
	SubnetName string
	// NetworkProjectID is the shared-VPC host project; defaults to ProjectID.
	NetworkProjectID pulumi.StringInput
	// MachineType is declared upstream but unused (Autopilot); kept for parity.
	MachineType string
	// MaxNodeCount is declared upstream but unused (Autopilot); kept for parity.
	MaxNodeCount int
	// MinNodeCount is declared upstream but unused (Autopilot); kept for parity.
	MinNodeCount int
	// CreateServiceAccount defaults to true (nil = true); when false,
	// ServiceAccountEmail and ServiceAccountID are required.
	CreateServiceAccount *bool
	// ServiceAccountEmail for the GKE nodes when CreateServiceAccount is false.
	ServiceAccountEmail pulumi.StringInput
	// ServiceAccountID for the GKE nodes when CreateServiceAccount is false.
	ServiceAccountID pulumi.StringInput
	// AgentK8sSecrets (upstream tfc_agent_k8s_secrets) defaults to
	// "tfc-agent-k8s-secrets".
	AgentK8sSecrets string
	// AgentAddress (upstream tfc_agent_address) — the Pulumi Cloud API
	// address. Default adapted to "https://api.pulumi.com" (upstream:
	// "https://app.terraform.io").
	AgentAddress string
	// AgentSingle (upstream tfc_agent_single) — no Pulumi analog; stored in
	// the secret for parity only.
	AgentSingle bool
	// AgentAutoUpdate (upstream tfc_agent_auto_update, default "minor") — no
	// Pulumi analog; stored in the secret for parity only.
	AgentAutoUpdate string
	// AgentNamePrefix defaults to "tfc-agent-k8s".
	AgentNamePrefix string
	// AgentImage — default adapted to "pulumi/pulumi-deployment-agent:latest"
	// (upstream: "hashicorp/tfc-agent:latest").
	AgentImage string
	// AgentMemoryRequest defaults to "2Gi".
	AgentMemoryRequest string
	// AgentCpuRequest defaults to "2".
	AgentCpuRequest string
	// AgentEphemeralStorage defaults to "1Gi".
	AgentEphemeralStorage string
	// AutopilotWardenVersion defaults to "2.7.41".
	AutopilotWardenVersion string
	// AgentToken (upstream tfc_agent_token) — the Pulumi Deployments agent
	// pool access token. Required. Sensitive.
	AgentToken pulumi.StringInput
	// AgentMinReplicas defaults to 1.
	AgentMinReplicas int
	// AgentMaxReplicas is declared upstream but only the minimum is consumed
	// (no HPA is created); kept for parity.
	AgentMaxReplicas int
	// FirewallEnableLogging defaults to true (nil = true).
	FirewallEnableLogging *bool
	// PrivateServiceConnectIP defaults to "10.10.64.5".
	PrivateServiceConnectIP string
	// DeployKubernetesResources gates the in-cluster Secret/Deployment
	// (defaults to true). ENGINE DIFFERENCE: upstream ships the kubernetes
	// provider block commented out and has you un-comment it after the first
	// apply (the cluster must exist before the provider can connect). Pulumi
	// cannot "comment out a provider" per-module, so set this to false for
	// the first apply and flip it to true once the cluster is reachable.
	DeployKubernetesResources *bool
}

func boolDefault(v *bool, def bool) bool {
	if v == nil {
		return def
	}
	return *v
}

// resolvedTfcAgentGkeArgs holds the module inputs after the upstream
// variables.tf defaults have been applied.
type resolvedTfcAgentGkeArgs struct {
	region                  string
	natBgpAsn               int
	natNumAddresses         int
	ipRangePodsName         string
	ipRangeServicesName     string
	ipRangePodsCidr         string
	ipRangeServicesCidr     string
	networkName             string
	subnetIP                string
	subnetName              string
	agentK8sSecrets         string
	agentAddress            string
	agentAutoUpdate         string
	agentNamePrefix         string
	agentImage              string
	agentMemoryRequest      string
	agentCpuRequest         string
	agentEphemeralStorage   string
	wardenVersion           string
	agentMinReplicas        int
	privateServiceConnectIP string
	createServiceAccount    bool
	natEnabled              bool
	firewallEnableLogging   bool
	deployK8sResources      bool
}

// resolveArgs applies the defaults mirroring upstream variables.tf.
func resolveArgs(args *TfcAgentGkeArgs) resolvedTfcAgentGkeArgs {
	region := args.Region
	if region == "" {
		region = "us-central1"
	}
	natBgpAsn := args.NatBgpAsn
	if natBgpAsn == 0 {
		natBgpAsn = 64514
	}
	natNumAddresses := args.NatNumAddresses
	if natNumAddresses == 0 {
		natNumAddresses = 2
	}
	ipRangePodsName := args.IPRangePodsName
	if ipRangePodsName == "" {
		ipRangePodsName = "ip-range-pods"
	}
	ipRangeServicesName := args.IPRangeServicesName
	if ipRangeServicesName == "" {
		ipRangeServicesName = "ip-range-scv"
	}
	ipRangePodsCidr := args.IPRangePodsCidr
	if ipRangePodsCidr == "" {
		ipRangePodsCidr = "192.168.0.0/18"
	}
	ipRangeServicesCidr := args.IPRangeServicesCider
	if ipRangeServicesCidr == "" {
		ipRangeServicesCidr = "192.168.64.0/18"
	}
	networkName := args.NetworkName
	if networkName == "" {
		networkName = "tfc-agent-network"
	}
	subnetIP := args.SubnetIP
	if subnetIP == "" {
		subnetIP = "10.0.0.0/17"
	}
	subnetName := args.SubnetName
	if subnetName == "" {
		subnetName = "tfc-agent-subnet"
	}
	agentK8sSecrets := args.AgentK8sSecrets
	if agentK8sSecrets == "" {
		agentK8sSecrets = "tfc-agent-k8s-secrets"
	}
	agentAddress := args.AgentAddress
	if agentAddress == "" {
		// ADAPTED default: Pulumi Cloud API (upstream: https://app.terraform.io).
		agentAddress = "https://api.pulumi.com"
	}
	agentAutoUpdate := args.AgentAutoUpdate
	if agentAutoUpdate == "" {
		agentAutoUpdate = "minor"
	}
	agentNamePrefix := args.AgentNamePrefix
	if agentNamePrefix == "" {
		agentNamePrefix = "tfc-agent-k8s"
	}
	agentImage := args.AgentImage
	if agentImage == "" {
		// ADAPTED default: the Pulumi Deployments self-hosted agent image
		// (upstream: hashicorp/tfc-agent:latest).
		agentImage = "pulumi/pulumi-deployment-agent:latest"
	}
	agentMemoryRequest := args.AgentMemoryRequest
	if agentMemoryRequest == "" {
		agentMemoryRequest = "2Gi"
	}
	agentCpuRequest := args.AgentCpuRequest
	if agentCpuRequest == "" {
		agentCpuRequest = "2"
	}
	agentEphemeralStorage := args.AgentEphemeralStorage
	if agentEphemeralStorage == "" {
		agentEphemeralStorage = "1Gi"
	}
	wardenVersion := args.AutopilotWardenVersion
	if wardenVersion == "" {
		wardenVersion = "2.7.41"
	}
	agentMinReplicas := args.AgentMinReplicas
	if agentMinReplicas == 0 {
		agentMinReplicas = 1
	}
	privateServiceConnectIP := args.PrivateServiceConnectIP
	if privateServiceConnectIP == "" {
		privateServiceConnectIP = "10.10.64.5"
	}

	return resolvedTfcAgentGkeArgs{
		region:                  region,
		natBgpAsn:               natBgpAsn,
		natNumAddresses:         natNumAddresses,
		ipRangePodsName:         ipRangePodsName,
		ipRangeServicesName:     ipRangeServicesName,
		ipRangePodsCidr:         ipRangePodsCidr,
		ipRangeServicesCidr:     ipRangeServicesCidr,
		networkName:             networkName,
		subnetIP:                subnetIP,
		subnetName:              subnetName,
		agentK8sSecrets:         agentK8sSecrets,
		agentAddress:            agentAddress,
		agentAutoUpdate:         agentAutoUpdate,
		agentNamePrefix:         agentNamePrefix,
		agentImage:              agentImage,
		agentMemoryRequest:      agentMemoryRequest,
		agentCpuRequest:         agentCpuRequest,
		agentEphemeralStorage:   agentEphemeralStorage,
		wardenVersion:           wardenVersion,
		agentMinReplicas:        agentMinReplicas,
		privateServiceConnectIP: privateServiceConnectIP,
		createServiceAccount:    boolDefault(args.CreateServiceAccount, true),
		natEnabled:              boolDefault(args.NatEnabled, true),
		firewallEnableLogging:   boolDefault(args.FirewallEnableLogging, true),
		deployK8sResources:      boolDefault(args.DeployKubernetesResources, true),
	}
}
