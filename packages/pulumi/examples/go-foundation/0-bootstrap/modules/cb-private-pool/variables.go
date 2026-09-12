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

// Mirrors: 0-bootstrap/modules/cb-private-pool/variables.tf in the TF
// foundation — the module's input surface, defaults and validation rules.

package cbprivatepool

import (
	"fmt"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// PrivateWorkerPoolConfig mirrors upstream var.private_worker_pool.
type PrivateWorkerPoolConfig struct {
	// Name of the worker pool. A name with a random suffix is generated if not set.
	Name string
	// Region of the private worker pool. Defaults to "us-central1".
	Region string
	// DiskSizeGb of the disk attached to the worker. Defaults to 100.
	DiskSizeGb int
	// MachineType of a worker. Defaults to "e2-medium".
	MachineType string
	// NoExternalIP creates workers without any public address when true.
	NoExternalIP bool
	// EnableNetworkPeering enables configuration of network peering for the
	// private worker pool.
	EnableNetworkPeering bool
	// CreatePeeredNetwork creates a network to establish the network peering.
	CreatePeeredNetwork bool
	// PeeredNetworkID is the ID of the existing network to configure peering
	// for when CreatePeeredNetwork is false. The project containing the
	// network must have the Service Networking API enabled.
	PeeredNetworkID string
	// PeeredNetworkSubnetIP is the IP range for the subnet created in the
	// peered network when CreatePeeredNetwork is true.
	PeeredNetworkSubnetIP string
	// PeeringAddress optionally reserves a specific peering address (or the
	// beginning of the range). Leave empty to let GCP choose a valid one.
	PeeringAddress string
	// PeeringPrefixLength is the prefix length of the IP peering range.
	// Defaults to 24.
	PeeringPrefixLength int
}

// VPNConfiguration mirrors upstream var.vpn_configuration (HA VPN to on-prem).
type VPNConfiguration struct {
	EnableVPN              bool
	OnPremPublicIPAddress0 string
	OnPremPublicIPAddress1 string
	// RouterASN defaults to 64515.
	RouterASN int
	// BGPPeerASN defaults to 64513.
	BGPPeerASN             int
	PSKSecretProjectID     string
	PSKSecretName          string
	Tunnel0BGPPeerAddress  string
	Tunnel0BGPSessionRange string
	Tunnel1BGPPeerAddress  string
	Tunnel1BGPSessionRange string
}

// VPCFlowLogsConfig mirrors upstream var.vpc_flow_logs.
type VPCFlowLogsConfig struct {
	// AggregationInterval defaults to "INTERVAL_5_SEC".
	AggregationInterval string
	// FlowSampling defaults to "0.5".
	FlowSampling string
	// Metadata defaults to "INCLUDE_ALL_METADATA".
	Metadata string
	// MetadataFields can only be specified when Metadata is CUSTOM_METADATA.
	MetadataFields []string
	// FilterExpr defaults to "true".
	FilterExpr string
}

// CbPrivatePoolArgs mirrors upstream variables.tf.
type CbPrivatePoolArgs struct {
	// ProjectID is the project where the private pool will be created.
	ProjectID pulumi.StringInput
	// PrivateWorkerPool mirrors var.private_worker_pool.
	PrivateWorkerPool PrivateWorkerPoolConfig
	// VPNConfiguration mirrors var.vpn_configuration.
	VPNConfiguration VPNConfiguration
	// VPCFlowLogs mirrors var.vpc_flow_logs.
	VPCFlowLogs VPCFlowLogsConfig
}

// resolveAndValidate applies the upstream optional() defaults and variable
// validation rules, returning resolved copies of the module inputs.
func resolveAndValidate(args *CbPrivatePoolArgs) (PrivateWorkerPoolConfig, VPNConfiguration, VPCFlowLogsConfig, error) {
	pw := args.PrivateWorkerPool
	vpn := args.VPNConfiguration
	fl := args.VPCFlowLogs

	// Defaults mirroring upstream optional() defaults.
	if pw.Region == "" {
		pw.Region = "us-central1"
	}
	if pw.DiskSizeGb == 0 {
		pw.DiskSizeGb = 100
	}
	if pw.MachineType == "" {
		pw.MachineType = "e2-medium"
	}
	if pw.PeeringPrefixLength == 0 {
		pw.PeeringPrefixLength = 24
	}
	if vpn.RouterASN == 0 {
		vpn.RouterASN = 64515
	}
	if vpn.BGPPeerASN == 0 {
		vpn.BGPPeerASN = 64513
	}
	if fl.AggregationInterval == "" {
		fl.AggregationInterval = "INTERVAL_5_SEC"
	}
	if fl.FlowSampling == "" {
		fl.FlowSampling = "0.5"
	}
	if fl.Metadata == "" {
		fl.Metadata = "INCLUDE_ALL_METADATA"
	}
	if fl.FilterExpr == "" {
		fl.FilterExpr = "true"
	}

	// Mirrors upstream var.private_worker_pool validation.
	if pw.EnableNetworkPeering &&
		!(pw.CreatePeeredNetwork && pw.PeeredNetworkSubnetIP != "") &&
		!(!pw.CreatePeeredNetwork && pw.PeeredNetworkID != "") {
		return pw, vpn, fl, fmt.Errorf("if network peering is enabled, the peered network must be created by the module using the provided peered network subnet ip or a valid network ID is required")
	}
	// Mirrors upstream var.vpn_configuration validation.
	if vpn.EnableVPN &&
		(vpn.OnPremPublicIPAddress0 == "" || vpn.OnPremPublicIPAddress1 == "" ||
			vpn.PSKSecretProjectID == "" || vpn.PSKSecretName == "" ||
			vpn.Tunnel0BGPPeerAddress == "" || vpn.Tunnel0BGPSessionRange == "" ||
			vpn.Tunnel1BGPPeerAddress == "" || vpn.Tunnel1BGPSessionRange == "") {
		return pw, vpn, fl, fmt.Errorf("if VPN configuration is enabled, all values are required")
	}

	return pw, vpn, fl, nil
}
