# tfc-agent-gke — self-hosted deployment agent on GKE

Pulumi Go port of the upstream terraform-example-foundation
[`0-bootstrap/modules/tfc-agent-gke`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/0-bootstrap/modules/tfc-agent-gke)
module, which handles the opinionated creation of the infrastructure
necessary to run CI agents on a private Autopilot Google Kubernetes Engine
(GKE) cluster.

This includes:

- VPC (with tag-routed internet egress)
- GKE Private Cluster with Autopilot
- Kubernetes Secret
- Kubernetes Deployment
- Kubernetes Fleet Hub membership
- Cloud NAT
- Private Service Connect for Google APIs

## ADAPTATION — Terraform Cloud → Pulumi Cloud (documented divergence)

Upstream runs a *Terraform Cloud* agent (`hashicorp/tfc-agent`) so TFC
"agent" execution mode can reach private infrastructure. Our foundation port
uses *Pulumi Cloud* as its backend, so this module keeps the upstream name,
inputs and resource shape for structural parity, but runs the Pulumi
Deployments **self-hosted deployment agent**
(`pulumi/pulumi-deployment-agent`) instead:

- `AgentAddress` (upstream `tfc_agent_address`, default
  `https://app.terraform.io`) → the Pulumi Cloud API address, default
  `https://api.pulumi.com`, injected as `PULUMI_API` (upstream:
  `TFC_ADDRESS`).
- `AgentToken` (upstream `tfc_agent_token`, a TFC agent-pool token) → a
  Pulumi Deployments agent pool access token, injected as
  `PULUMI_AGENT_TOKEN` (upstream: `TFC_AGENT_TOKEN`).
- `AgentImage` (upstream `hashicorp/tfc-agent:latest`) →
  `pulumi/pulumi-deployment-agent:latest`.
- `AgentSingle` / `AgentAutoUpdate` / agent name env: the Pulumi deployment
  agent has NO analog for `TFC_AGENT_SINGLE`, `TFC_AGENT_AUTO_UPDATE` or
  `TFC_AGENT_NAME`. For parity the values are still stored in the Kubernetes
  secret under the upstream key names, but they are NOT injected into the
  container (documented stub).

The file layout mirrors upstream's file-per-concern split: `main.go`
(`main.tf`), `variables.go` (`variables.tf`), `outputs.go` (`outputs.tf`).
`versions.tf` has no per-module Go analog — provider pins live in the stage's
`go.mod` (engine adaptation).

## Usage

```go
agent, err := tfcagentgke.NewTfcAgentGke(ctx, "tfc-agent-gke", &tfcagentgke.TfcAgentGkeArgs{
	ProjectID:  cicdProjectID,
	AgentToken: agentPoolToken, // Pulumi Deployments agent pool access token
	// ENGINE DIFFERENCE: set false on the first apply, flip to true once
	// the cluster exists (upstream has you un-comment its kubernetes
	// provider block after the first apply).
	DeployKubernetesResources: pulumi.BoolRef(false),
})
```

## Inputs (`TfcAgentGkeArgs`)

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| ProjectID | Project ID to deploy the agent cluster in | `pulumi.StringInput` | n/a | yes |
| ProjectNumber | Declared upstream but unused by the module body; kept for input parity | `pulumi.StringInput` | n/a | no |
| Region | Region used when deploying resources | `string` | `"us-central1"` | no |
| Zones | Declared upstream but unused by the regional Autopilot cluster; kept for parity | `[]string` | `[]` | no |
| NatBgpAsn | BGP ASN for NAT cloud routes | `int` | `64514` | no |
| NatEnabled | Deploy Cloud NAT (nil = true) | `*bool` | `true` | no |
| NatNumAddresses | Number of external NAT addresses | `int` | `2` | no |
| IPRangePodsName | The secondary IP range name for pods | `string` | `"ip-range-pods"` | no |
| IPRangeServicesName | The secondary IP range name for services | `string` | `"ip-range-scv"` | no |
| IPRangePodsCidr | The secondary IP range CIDR for pods | `string` | `"192.168.0.0/18"` | no |
| IPRangeServicesCider | The secondary IP range CIDR for services (`[sic]` upstream name) | `string` | `"192.168.64.0/18"` | no |
| NetworkName | Name for the VPC network | `string` | `"tfc-agent-network"` | no |
| SubnetIP | IP range for the subnet | `string` | `"10.0.0.0/17"` | no |
| SubnetName | Name for the subnet | `string` | `"tfc-agent-subnet"` | no |
| NetworkProjectID | Shared-VPC host project; defaults to ProjectID | `pulumi.StringInput` | ProjectID | no |
| MachineType | Declared upstream but unused (Autopilot); kept for parity | `string` | — | no |
| MaxNodeCount / MinNodeCount | Declared upstream but unused (Autopilot); kept for parity | `int` | — | no |
| CreateServiceAccount | Create a node SA (nil = true); when false, ServiceAccountEmail + ServiceAccountID are required | `*bool` | `true` | no |
| ServiceAccountEmail | Node SA email when CreateServiceAccount is false | `pulumi.StringInput` | — | no |
| ServiceAccountID | Node SA ID when CreateServiceAccount is false | `pulumi.StringInput` | — | no |
| AgentK8sSecrets | Name of the k8s secret configuring the agent | `string` | `"tfc-agent-k8s-secrets"` | no |
| AgentAddress | Pulumi Cloud API address (ADAPTED; upstream `tfc_agent_address`) | `string` | `"https://api.pulumi.com"` | no |
| AgentSingle | No Pulumi analog; stored in the secret for parity only | `bool` | `false` | no |
| AgentAutoUpdate | No Pulumi analog; stored in the secret for parity only | `string` | `"minor"` | no |
| AgentNamePrefix | Prefix used to identify the agent | `string` | `"tfc-agent-k8s"` | no |
| AgentImage | Agent image (ADAPTED; upstream `hashicorp/tfc-agent:latest`) | `string` | `"pulumi/pulumi-deployment-agent:latest"` | no |
| AgentMemoryRequest | Memory request for the agent container | `string` | `"2Gi"` | no |
| AgentCpuRequest | CPU request for the agent container | `string` | `"2"` | no |
| AgentEphemeralStorage | Ephemeral storage for the agent container | `string` | `"1Gi"` | no |
| AutopilotWardenVersion | Autopilot GKE IO Warden version annotation | `string` | `"2.7.41"` | no |
| AgentToken | Pulumi Deployments agent pool access token (ADAPTED; upstream `tfc_agent_token`). Sensitive | `pulumi.StringInput` | n/a | yes |
| AgentMinReplicas | Agent deployment replicas | `int` | `1` | no |
| AgentMaxReplicas | Declared upstream but only the minimum is consumed (no HPA); kept for parity | `int` | — | no |
| FirewallEnableLogging | Enable logging on the private-API egress firewall (nil = true) | `*bool` | `true` | no |
| PrivateServiceConnectIP | Internal IP for Private Service Connect | `string` | `"10.10.64.5"` | no |
| DeployKubernetesResources | Gate the in-cluster Secret/Deployment (nil = true); see ENGINE DIFFERENCE above | `*bool` | `true` | no |

## Outputs (`TfcAgentGke`)

| Name | Description |
|------|-------------|
| ClusterName | GKE cluster name (upstream `cluster_name`) |
| HubClusterMembershipID | The ID of the fleet cluster membership (upstream `hub_cluster_membership_id`) |
| KubernetesEndpoint | The GKE cluster endpoint, sensitive (upstream `kubernetes_endpoint`) |
| ServiceAccount | The default service account used for agent nodes (upstream `service_account`) |

## Requirements

Before this module can be used on a project, you must ensure that the
following APIs are activated on it:

```text
"iam.googleapis.com",
"cloudresourcemanager.googleapis.com",
"containerregistry.googleapis.com",
"container.googleapis.com",
"storage-component.googleapis.com",
"logging.googleapis.com",
"monitoring.googleapis.com"
```
