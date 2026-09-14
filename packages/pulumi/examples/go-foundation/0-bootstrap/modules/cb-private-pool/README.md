# cb-private-pool

Pulumi Go port of the upstream terraform-example-foundation
[`0-bootstrap/modules/cb-private-pool`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/0-bootstrap/modules/cb-private-pool)
module: a Cloud Build private worker pool, optionally peered (via Private
Service Access) to a VPC network this module can create, and optionally
connected to on-prem through HA VPN.

The file layout mirrors upstream's file-per-concern split:

| File | Mirrors | Concern |
|------|---------|---------|
| `main.go` | `main.tf` | The Cloud Build private worker pool |
| `network.go` | `network.tf` | Optional peered network + PSA peering, routes, firewall |
| `vpn_ha.go` | `vpn_ha.tf` | Optional HA VPN to on-prem |
| `variables.go` | `variables.tf` | Inputs, defaults and validations |
| `outputs.go` | `outputs.tf` | Component outputs |

`versions.tf` has no per-module Go analog — provider pins live in the stage's
`go.mod` (engine adaptation).

## Usage

```go
pool, err := cbprivatepool.NewCbPrivatePool(ctx, "cb-private-pool", &cbprivatepool.CbPrivatePoolArgs{
	ProjectID: cicdProjectID,
	PrivateWorkerPool: cbprivatepool.PrivateWorkerPoolConfig{
		EnableNetworkPeering:  true,
		CreatePeeredNetwork:   true,
		PeeredNetworkSubnetIP: "10.3.0.0/24",
	},
})
```

## Inputs (`CbPrivatePoolArgs`)

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| ProjectID | ID of the project where the private pool will be created | `pulumi.StringInput` | n/a | yes |
| PrivateWorkerPool | Worker pool + peering settings, mirrors upstream `var.private_worker_pool` (see below) | `PrivateWorkerPoolConfig` | `{}` | no |
| VPNConfiguration | HA VPN to on-prem, mirrors upstream `var.vpn_configuration` (see below) | `VPNConfiguration` | `{}` | no |
| VPCFlowLogs | Flow-log settings for the peered subnet, mirrors upstream `var.vpc_flow_logs` (see below) | `VPCFlowLogsConfig` | `{}` | no |

### `PrivateWorkerPoolConfig`

| Field | Description | Default |
|-------|-------------|---------|
| Name | Name of the worker pool; a name with a random suffix is generated if not set | `""` |
| Region | Region of the private worker pool | `"us-central1"` |
| DiskSizeGb | Size of the disk attached to the worker, in GB | `100` |
| MachineType | Machine type of a worker | `"e2-medium"` |
| NoExternalIP | Create workers without any public address | `false` |
| EnableNetworkPeering | Enable network peering for the private worker pool | `false` |
| CreatePeeredNetwork | Create a network to establish the network peering | `false` |
| PeeredNetworkID | Existing network ID to peer with when CreatePeeredNetwork is false (its project must have the Service Networking API enabled) | `""` |
| PeeredNetworkSubnetIP | IP range for the subnet created in the peered network when CreatePeeredNetwork is true | `""` |
| PeeringAddress | Reserve a specific peering address (or beginning of the range); empty lets GCP choose | `""` |
| PeeringPrefixLength | Prefix length of the IP peering range | `24` |

### `VPNConfiguration`

| Field | Description | Default |
|-------|-------------|---------|
| EnableVPN | Create the VPN connection to on-prem; if true all other fields are required | `false` |
| OnPremPublicIPAddress0 / OnPremPublicIPAddress1 | The two on-prem public VPN addresses | `""` |
| RouterASN | BGP ASN for cloud routes | `64515` |
| BGPPeerASN | BGP ASN for peer cloud routes | `64513` |
| PSKSecretProjectID / PSKSecretName | Secret Manager location of the VPN pre-shared key | `""` |
| Tunnel0BGPPeerAddress / Tunnel0BGPSessionRange | BGP peer address + session range for tunnel 0 | `""` |
| Tunnel1BGPPeerAddress / Tunnel1BGPSessionRange | BGP peer address + session range for tunnel 1 | `""` |

### `VPCFlowLogsConfig`

| Field | Description | Default |
|-------|-------------|---------|
| AggregationInterval | Aggregation interval for collecting flow logs | `"INTERVAL_5_SEC"` |
| FlowSampling | Sampling rate of VPC flow logs in [0, 1] | `"0.5"` |
| Metadata | Whether metadata fields are added to the reported flow logs | `"INCLUDE_ALL_METADATA"` |
| MetadataFields | Metadata fields to report; only with `Metadata = "CUSTOM_METADATA"` | `[]` |
| FilterExpr | CEL export filter for which flow logs are reported | `"true"` |

## Outputs (`CbPrivatePool`)

| Name | Description |
|------|-------------|
| PrivateWorkerPoolID | Private worker pool ID (upstream `private_worker_pool_id`) |
| WorkerRangeID | The worker IP range ID; `""` when peering is disabled (upstream `worker_range_id`) |
| WorkerPeeredIPRange | The IP range of the peered service network (upstream `worker_peered_ip_range`) |
| PeeredNetworkID | The ID of the peered network (upstream `peered_network_id`) |
