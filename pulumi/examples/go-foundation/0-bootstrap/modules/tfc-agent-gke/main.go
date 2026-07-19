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

// Package tfcagentgke mirrors the upstream terraform-example-foundation
// 0-bootstrap/modules/tfc-agent-gke module.
//
// ADAPTATION — Terraform Cloud → Pulumi Cloud (documented divergence):
// upstream runs a *Terraform Cloud* agent (hashicorp/tfc-agent) on a private
// GKE Autopilot cluster so TFC "agent" execution mode can reach private
// infrastructure. Our foundation port uses *Pulumi Cloud* as its backend, so
// this module keeps the upstream name, inputs and resource shape for
// structural parity, but runs the Pulumi Deployments **self-hosted
// deployment agent** (pulumi/pulumi-deployment-agent) instead:
//
//   - AgentAddress (upstream tfc_agent_address, default https://app.terraform.io)
//     → the Pulumi Cloud API address, default https://api.pulumi.com,
//     injected as PULUMI_API (upstream: TFC_ADDRESS).
//   - AgentToken (upstream tfc_agent_token, a TFC agent-pool token)
//     → a Pulumi Deployments agent pool access token, injected as
//     PULUMI_AGENT_TOKEN (upstream: TFC_AGENT_TOKEN).
//   - AgentImage (upstream hashicorp/tfc-agent:latest)
//     → pulumi/pulumi-deployment-agent:latest.
//   - AgentSingle / AgentAutoUpdate / agent name env: the Pulumi deployment
//     agent has NO analog for TFC_AGENT_SINGLE, TFC_AGENT_AUTO_UPDATE or
//     TFC_AGENT_NAME. For parity the values are still stored in the
//     Kubernetes secret under the upstream key names, but they are NOT
//     injected into the container (documented stub, see the Deployment
//     resource below).
//
// Everything else (VPC + tag-routed internet egress, private Autopilot GKE
// cluster, Cloud NAT, Private Service Connect for Google APIs, DNS policy,
// fleet membership, container-engine service-identity IAM) is a faithful
// port of the upstream module's GCP resources.
package tfcagentgke

import (
	"fmt"
	"strconv"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/container"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/dns"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/gkehub"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	kubernetes "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes"
	appsv1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/apps/v1"
	corev1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/core/v1"
	metav1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/meta/v1"
	"github.com/pulumi/pulumi-random/sdk/v4/go/random"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const (
	// vpcName mirrors upstream local.vpc_name.
	vpcName = "b-tfc-runner"
	// networkTag mirrors the upstream "tfc-runner-vm" network tag.
	networkTag = "tfc-runner-vm"
)

// NewTfcAgentGke provisions the network, private Autopilot GKE cluster, NAT,
// Private Service Connect, fleet membership and the (Pulumi) deployment agent
// workload, mirroring upstream main.tf.
func NewTfcAgentGke(ctx *pulumi.Context, name string, args *TfcAgentGkeArgs, opts ...pulumi.ResourceOption) (*TfcAgentGke, error) {
	// Defaults mirroring upstream variables.tf (see variables.go).
	d := resolveArgs(args)

	var resource TfcAgentGke
	err := ctx.RegisterComponentResource("modules:tfc-agent-gke:TfcAgentGke", name, &resource, opts...)
	if err != nil {
		return nil, err
	}

	// Mirrors: random_string.suffix + local.tfc_agent_name.
	suffix, err := random.NewRandomString(ctx, fmt.Sprintf("%s-suffix", name), &random.RandomStringArgs{
		Length:  pulumi.Int(4),
		Special: pulumi.Bool(false),
		Upper:   pulumi.Bool(false),
	}, pulumi.Parent(&resource))
	if err != nil {
		return nil, err
	}
	agentName := pulumi.Sprintf("%s-%s", d.agentNamePrefix, suffix.Result)

	// ------------------------------------------------------------------
	// Network — mirrors module.network (terraform-google-modules/network),
	// ported as raw resources: VPC without default routes, a tag-based
	// default-internet egress route, and one subnet with secondary ranges
	// for pods and services.
	// ------------------------------------------------------------------
	network, err := compute.NewNetwork(ctx, fmt.Sprintf("%s-network", name), &compute.NetworkArgs{
		Project:                     args.ProjectID,
		Name:                        pulumi.String(d.networkName),
		AutoCreateSubnetworks:       pulumi.Bool(false),
		DeleteDefaultRoutesOnCreate: pulumi.Bool(true),
	}, pulumi.Parent(&resource))
	if err != nil {
		return nil, err
	}

	_, err = compute.NewRoute(ctx, fmt.Sprintf("%s-egress-internet", name), &compute.RouteArgs{
		Project:        args.ProjectID,
		Name:           pulumi.Sprintf("rt-%s-1000-egress-internet-default", vpcName),
		Description:    pulumi.String("Tag based route through IGW to access internet"),
		Network:        network.Name,
		DestRange:      pulumi.String("0.0.0.0/0"),
		Tags:           pulumi.StringArray{pulumi.String(networkTag)},
		NextHopGateway: pulumi.String("default-internet-gateway"),
		Priority:       pulumi.Int(1000),
	}, pulumi.Parent(&resource))
	if err != nil {
		return nil, err
	}

	subnet, err := compute.NewSubnetwork(ctx, fmt.Sprintf("%s-subnet", name), &compute.SubnetworkArgs{
		Project:               args.ProjectID,
		Name:                  pulumi.String(d.subnetName),
		Description:           pulumi.String("Subnet for Terraform Cloud Runner"),
		IpCidrRange:           pulumi.String(d.subnetIP),
		Region:                pulumi.String(d.region),
		Network:               network.ID(),
		PrivateIpGoogleAccess: pulumi.Bool(true),
		LogConfig:             &compute.SubnetworkLogConfigArgs{},
		SecondaryIpRanges: compute.SubnetworkSecondaryIpRangeArray{
			&compute.SubnetworkSecondaryIpRangeArgs{
				RangeName:   pulumi.String(d.ipRangePodsName),
				IpCidrRange: pulumi.String(d.ipRangePodsCidr),
			},
			&compute.SubnetworkSecondaryIpRangeArgs{
				RangeName:   pulumi.String(d.ipRangeServicesName),
				IpCidrRange: pulumi.String(d.ipRangeServicesCidr),
			},
		},
	}, pulumi.Parent(&resource))
	if err != nil {
		return nil, err
	}

	// ------------------------------------------------------------------
	// IAM — mirrors google_service_account.tfc_agent_service_account.
	// ------------------------------------------------------------------
	var serviceAccountEmail pulumi.StringInput
	var serviceAccountID pulumi.StringInput
	if d.createServiceAccount {
		agentSA, err := serviceaccount.NewAccount(ctx, fmt.Sprintf("%s-service-account", name), &serviceaccount.AccountArgs{
			Project:                   args.ProjectID,
			AccountId:                 pulumi.String("tfc-agent-gke"),
			DisplayName:               pulumi.String("Deployment agent GKE Service Account"),
			CreateIgnoreAlreadyExists: pulumi.Bool(true),
		}, pulumi.Parent(&resource))
		if err != nil {
			return nil, err
		}
		serviceAccountEmail = agentSA.Email
		serviceAccountID = agentSA.ID().ToStringOutput().ApplyT(func(id string) string { return id }).(pulumi.StringOutput)
	} else {
		if args.ServiceAccountEmail == nil || args.ServiceAccountID == nil {
			return nil, fmt.Errorf("ServiceAccountEmail and ServiceAccountID are required when CreateServiceAccount is false")
		}
		serviceAccountEmail = args.ServiceAccountEmail
		serviceAccountID = args.ServiceAccountID
	}

	// ------------------------------------------------------------------
	// GKE — mirrors module.tfc_agent_cluster
	// (terraform-google-modules/kubernetes-engine//beta-autopilot-private-cluster),
	// ported as a raw private regional Autopilot cluster.
	// ------------------------------------------------------------------
	networkProjectID := args.NetworkProjectID
	if networkProjectID == nil {
		networkProjectID = args.ProjectID
	}
	cluster, err := container.NewCluster(ctx, fmt.Sprintf("%s-cluster", name), &container.ClusterArgs{
		Project:         args.ProjectID,
		Name:            agentName,
		Location:        pulumi.String(d.region),
		Network:         pulumi.Sprintf("projects/%s/global/networks/%s", networkProjectID, network.Name),
		Subnetwork:      subnet.SelfLink,
		EnableAutopilot: pulumi.Bool(true),
		IpAllocationPolicy: &container.ClusterIpAllocationPolicyArgs{
			ClusterSecondaryRangeName:  pulumi.String(d.ipRangePodsName),
			ServicesSecondaryRangeName: pulumi.String(d.ipRangeServicesName),
		},
		PrivateClusterConfig: &container.ClusterPrivateClusterConfigArgs{
			EnablePrivateEndpoint: pulumi.Bool(true),
			EnablePrivateNodes:    pulumi.Bool(true),
			MasterIpv4CidrBlock:   pulumi.String("172.16.0.0/28"),
		},
		MasterAuthorizedNetworksConfig: &container.ClusterMasterAuthorizedNetworksConfigArgs{
			CidrBlocks: container.ClusterMasterAuthorizedNetworksConfigCidrBlockArray{
				&container.ClusterMasterAuthorizedNetworksConfigCidrBlockArgs{
					CidrBlock:   pulumi.String("10.60.0.0/17"),
					DisplayName: pulumi.String("VPC"),
				},
			},
		},
		VerticalPodAutoscaling: &container.ClusterVerticalPodAutoscalingArgs{
			Enabled: pulumi.Bool(true),
		},
		ClusterAutoscaling: &container.ClusterClusterAutoscalingArgs{
			AutoProvisioningDefaults: &container.ClusterClusterAutoscalingAutoProvisioningDefaultsArgs{
				ServiceAccount: serviceAccountEmail,
				OauthScopes: pulumi.StringArray{
					pulumi.String("https://www.googleapis.com/auth/cloud-platform"),
				},
			},
		},
		// Mirrors: network_tags = ["tfc-runner-vm"] — on Autopilot, node
		// network tags are applied via node_pool_auto_config.
		NodePoolAutoConfig: &container.ClusterNodePoolAutoConfigArgs{
			NetworkTags: &container.ClusterNodePoolAutoConfigNetworkTagsArgs{
				Tags: pulumi.StringArray{pulumi.String(networkTag)},
			},
		},
	}, pulumi.Parent(&resource), pulumi.DependsOn([]pulumi.Resource{network, subnet}))
	if err != nil {
		return nil, err
	}

	// ------------------------------------------------------------------
	// K8S resources for configuring the agent — mirrors
	// kubernetes_secret.tfc_agent_secrets + kubernetes_deployment.
	// The kubernetes provider connects to the cluster via a generated
	// kubeconfig (exec-auth via gke-gcloud-auth-plugin), the Pulumi
	// equivalent of upstream's kubernetes provider block.
	// ------------------------------------------------------------------
	if d.deployK8sResources {
		kubeconfig := pulumi.All(cluster.Name, cluster.Endpoint, cluster.MasterAuth.ClusterCaCertificate().Elem()).ApplyT(
			func(vs []interface{}) string {
				name := vs[0].(string)
				endpoint := vs[1].(string)
				ca := vs[2].(string)
				return fmt.Sprintf(`apiVersion: v1
kind: Config
clusters:
- name: %[1]s
  cluster:
    server: https://%[2]s
    certificate-authority-data: %[3]s
contexts:
- name: %[1]s
  context:
    cluster: %[1]s
    user: %[1]s
current-context: %[1]s
users:
- name: %[1]s
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: gke-gcloud-auth-plugin
      installHint: Install gke-gcloud-auth-plugin for kubectl by following
        https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_plugin
      provideClusterInfo: true
`, name, endpoint, ca)
			},
		).(pulumi.StringOutput)

		k8sProvider, err := kubernetes.NewProvider(ctx, fmt.Sprintf("%s-k8s", name), &kubernetes.ProviderArgs{
			Kubeconfig: kubeconfig,
		}, pulumi.Parent(&resource))
		if err != nil {
			return nil, err
		}

		// Mirrors: kubernetes_secret.tfc_agent_secrets. The upstream key
		// names are preserved for structural parity; see the package doc
		// comment for the TFC→Pulumi mapping.
		secret, err := corev1.NewSecret(ctx, fmt.Sprintf("%s-agent-secrets", name), &corev1.SecretArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Name: pulumi.String(d.agentK8sSecrets),
			},
			StringData: pulumi.StringMap{
				"tfc_agent_address":     pulumi.String(d.agentAddress),
				"tfc_agent_token":       pulumi.ToOutput(args.AgentToken).ApplyT(func(v interface{}) string { s, _ := v.(string); return s }).(pulumi.StringOutput),
				"tfc_agent_single":      pulumi.String(strconv.FormatBool(args.AgentSingle)),
				"tfc_agent_auto_update": pulumi.String(d.agentAutoUpdate),
				"tfc_agent_name":        agentName,
			},
		}, pulumi.Parent(&resource), pulumi.Provider(k8sProvider))
		if err != nil {
			return nil, err
		}

		// Mirrors: kubernetes_deployment.tfc_agent_deployment, including the
		// pre-seeded Autopilot resource-adjustment annotation.
		resourceAdjustment := pulumi.Sprintf(
			`{"input":{"containers":[{"name":"%[1]s","requests":{"cpu":"%[2]s","memory":"%[3]s","ephemeral-storage":"%[4]s"}}]},"modified":true,"output":{"containers":[{"limits":{"cpu":"%[2]s","ephemeral-storage":"%[4]s","memory":"%[3]s"},"name":"%[1]s","requests":{"cpu":"%[2]s","ephemeral-storage":"%[4]s","memory":"%[3]s"}}]}}`,
			agentName, d.agentCpuRequest, d.agentMemoryRequest, d.agentEphemeralStorage,
		)

		resourceList := pulumi.StringMap{
			"memory":            pulumi.String(d.agentMemoryRequest),
			"cpu":               pulumi.String(d.agentCpuRequest),
			"ephemeral-storage": pulumi.String(d.agentEphemeralStorage),
		}

		_, err = appsv1.NewDeployment(ctx, fmt.Sprintf("%s-agent-deployment", name), &appsv1.DeploymentArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Name: pulumi.Sprintf("%s-deployment", agentName),
				Annotations: pulumi.StringMap{
					"autopilot.gke.io/resource-adjustment": resourceAdjustment,
					"autopilot.gke.io/warden-version":      pulumi.String(d.wardenVersion),
				},
			},
			Spec: &appsv1.DeploymentSpecArgs{
				Replicas: pulumi.Int(d.agentMinReplicas),
				Selector: &metav1.LabelSelectorArgs{
					MatchLabels: pulumi.StringMap{"app": agentName},
				},
				Template: &corev1.PodTemplateSpecArgs{
					Metadata: &metav1.ObjectMetaArgs{
						Labels: pulumi.StringMap{"app": agentName},
					},
					Spec: &corev1.PodSpecArgs{
						Containers: corev1.ContainerArray{
							&corev1.ContainerArgs{
								Name:  agentName,
								Image: pulumi.String(d.agentImage),
								Env: corev1.EnvVarArray{
									// ADAPTED: PULUMI_API ← upstream TFC_ADDRESS.
									&corev1.EnvVarArgs{
										Name: pulumi.String("PULUMI_API"),
										ValueFrom: &corev1.EnvVarSourceArgs{
											SecretKeyRef: &corev1.SecretKeySelectorArgs{
												Name: secret.Metadata.Name(),
												Key:  pulumi.String("tfc_agent_address"),
											},
										},
									},
									// ADAPTED: PULUMI_AGENT_TOKEN ← upstream TFC_AGENT_TOKEN.
									&corev1.EnvVarArgs{
										Name: pulumi.String("PULUMI_AGENT_TOKEN"),
										ValueFrom: &corev1.EnvVarSourceArgs{
											SecretKeyRef: &corev1.SecretKeySelectorArgs{
												Name: secret.Metadata.Name(),
												Key:  pulumi.String("tfc_agent_token"),
											},
										},
									},
									// STUB (documented): upstream also injects
									// TFC_AGENT_NAME, TFC_AGENT_SINGLE and
									// TFC_AGENT_AUTO_UPDATE. The Pulumi
									// deployment agent has no equivalent
									// settings, so those secret keys exist for
									// parity but are intentionally not
									// injected here.
								},
								// https://developer.hashicorp.com/terraform/cloud-docs/agents/requirements
								Resources: &corev1.ResourceRequirementsArgs{
									Requests: resourceList,
								},
								SecurityContext: &corev1.SecurityContextArgs{
									AllowPrivilegeEscalation: pulumi.Bool(false),
									Privileged:               pulumi.Bool(false),
									ReadOnlyRootFilesystem:   pulumi.Bool(false),
									RunAsNonRoot:             pulumi.Bool(false),
									Capabilities: &corev1.CapabilitiesArgs{
										Drop: pulumi.StringArray{pulumi.String("NET_RAW")},
									},
								},
							},
						},
						SecurityContext: &corev1.PodSecurityContextArgs{
							RunAsNonRoot: pulumi.Bool(false),
							SeccompProfile: &corev1.SeccompProfileArgs{
								Type: pulumi.String("RuntimeDefault"),
							},
						},
						Tolerations: corev1.TolerationArray{
							&corev1.TolerationArgs{
								Effect:   pulumi.String("NoSchedule"),
								Key:      pulumi.String("kubernetes.io/arch"),
								Operator: pulumi.String("Equal"),
								Value:    pulumi.String("amd64"),
							},
						},
					},
				},
			},
		}, pulumi.Parent(&resource), pulumi.Provider(k8sProvider))
		if err != nil {
			return nil, err
		}
	}

	// ------------------------------------------------------------------
	// NAT — mirrors google_compute_router.nat, google_compute_address.
	// nat_external_addresses and google_compute_router_nat.egress.
	// ------------------------------------------------------------------
	if d.natEnabled {
		natRouter, err := compute.NewRouter(ctx, fmt.Sprintf("%s-nat-router", name), &compute.RouterArgs{
			Project: args.ProjectID,
			Name:    pulumi.Sprintf("cr-%s-%s-nat-router", vpcName, d.region),
			Region:  pulumi.String(d.region),
			Network: network.SelfLink,
			Bgp: &compute.RouterBgpArgs{
				Asn: pulumi.Int(d.natBgpAsn),
			},
		}, pulumi.Parent(&resource))
		if err != nil {
			return nil, err
		}

		natIPs := pulumi.StringArray{}
		for i := 0; i < d.natNumAddresses; i++ {
			addr, err := compute.NewAddress(ctx, fmt.Sprintf("%s-nat-address-%d", name, i), &compute.AddressArgs{
				Project: args.ProjectID,
				Name:    pulumi.Sprintf("ca-%s-%s-%d", vpcName, d.region, i),
				Region:  pulumi.String(d.region),
			}, pulumi.Parent(&resource))
			if err != nil {
				return nil, err
			}
			natIPs = append(natIPs, addr.SelfLink)
		}

		_, err = compute.NewRouterNat(ctx, fmt.Sprintf("%s-nat-egress", name), &compute.RouterNatArgs{
			Project:                       args.ProjectID,
			Name:                          pulumi.Sprintf("rn-%s-%s-egress", vpcName, d.region),
			Router:                        natRouter.Name,
			Region:                        pulumi.String(d.region),
			NatIpAllocateOption:           pulumi.String("MANUAL_ONLY"),
			NatIps:                        natIPs,
			SourceSubnetworkIpRangesToNat: pulumi.String("ALL_SUBNETWORKS_ALL_IP_RANGES"),
			LogConfig: &compute.RouterNatLogConfigArgs{
				Filter: pulumi.String("TRANSLATIONS_ONLY"),
				Enable: pulumi.Bool(true),
			},
		}, pulumi.Parent(&resource))
		if err != nil {
			return nil, err
		}
	}

	// ------------------------------------------------------------------
	// Private Google APIs egress — mirrors
	// google_compute_firewall.allow_private_api_egress.
	// ------------------------------------------------------------------
	firewallArgs := &compute.FirewallArgs{
		Project:   args.ProjectID,
		Name:      pulumi.Sprintf("fw-%s-65430-e-a-allow-google-apis-all-tcp-443", vpcName),
		Network:   network.Name,
		Direction: pulumi.String("EGRESS"),
		Priority:  pulumi.Int(65430),
		Allows: compute.FirewallAllowArray{
			&compute.FirewallAllowArgs{
				Protocol: pulumi.String("tcp"),
				Ports:    pulumi.StringArray{pulumi.String("443")},
			},
		},
		DestinationRanges: pulumi.StringArray{pulumi.String(d.privateServiceConnectIP)},
		TargetTags:        pulumi.StringArray{pulumi.String(networkTag)},
	}
	if d.firewallEnableLogging {
		firewallArgs.LogConfig = &compute.FirewallLogConfigArgs{
			Metadata: pulumi.String("INCLUDE_ALL_METADATA"),
		}
	}
	_, err = compute.NewFirewall(ctx, fmt.Sprintf("%s-allow-private-api-egress", name), firewallArgs, pulumi.Parent(&resource))
	if err != nil {
		return nil, err
	}

	// ------------------------------------------------------------------
	// Private Service Connect — mirrors module.private_service_connect
	// (terraform-google-modules/network//modules/private-service-connect
	// with forwarding_rule_target = "all-apis"), ported as raw resources:
	// a global internal address + PSC forwarding rule for all Google APIs
	// and private DNS zones (googleapis.com, gcr.io, pkg.dev) pointing at it.
	// ------------------------------------------------------------------
	pscAddress, err := compute.NewGlobalAddress(ctx, fmt.Sprintf("%s-psc-address", name), &compute.GlobalAddressArgs{
		Project:     args.ProjectID,
		Name:        pulumi.Sprintf("csa-%s", vpcName),
		Purpose:     pulumi.String("PRIVATE_SERVICE_CONNECT"),
		AddressType: pulumi.String("INTERNAL"),
		Address:     pulumi.String(d.privateServiceConnectIP),
		Network:     network.SelfLink,
	}, pulumi.Parent(&resource))
	if err != nil {
		return nil, err
	}

	// PSC forwarding-rule names are restricted to 1-20 lowercase letters and
	// digits, hence the compacted name.
	_, err = compute.NewGlobalForwardingRule(ctx, fmt.Sprintf("%s-psc-forwarding-rule", name), &compute.GlobalForwardingRuleArgs{
		Project:             args.ProjectID,
		Name:                pulumi.String("gfrbtfcrunner"),
		Target:              pulumi.String("all-apis"),
		Network:             network.SelfLink,
		IpAddress:           pscAddress.ID(),
		LoadBalancingScheme: pulumi.String(""),
	}, pulumi.Parent(&resource))
	if err != nil {
		return nil, err
	}

	pscZones := []struct {
		zone   string
		domain string
	}{
		{"googleapis", "googleapis.com."},
		{"gcr", "gcr.io."},
		{"pkg-dev", "pkg.dev."},
	}
	for _, z := range pscZones {
		managedZone, err := dns.NewManagedZone(ctx, fmt.Sprintf("%s-psc-zone-%s", name, z.zone), &dns.ManagedZoneArgs{
			Project:     args.ProjectID,
			Name:        pulumi.Sprintf("dz-%s-%s", vpcName, z.zone),
			DnsName:     pulumi.String(z.domain),
			Description: pulumi.Sprintf("Private DNS zone routing %s to Private Service Connect", z.domain),
			Visibility:  pulumi.String("private"),
			PrivateVisibilityConfig: &dns.ManagedZonePrivateVisibilityConfigArgs{
				Networks: dns.ManagedZonePrivateVisibilityConfigNetworkArray{
					&dns.ManagedZonePrivateVisibilityConfigNetworkArgs{
						NetworkUrl: network.SelfLink,
					},
				},
			},
		}, pulumi.Parent(&resource))
		if err != nil {
			return nil, err
		}

		_, err = dns.NewRecordSet(ctx, fmt.Sprintf("%s-psc-a-%s", name, z.zone), &dns.RecordSetArgs{
			Project:     args.ProjectID,
			ManagedZone: managedZone.Name,
			Name:        pulumi.String(z.domain),
			Type:        pulumi.String("A"),
			Ttl:         pulumi.Int(300),
			Rrdatas:     pulumi.StringArray{pulumi.String(d.privateServiceConnectIP)},
		}, pulumi.Parent(&resource))
		if err != nil {
			return nil, err
		}

		_, err = dns.NewRecordSet(ctx, fmt.Sprintf("%s-psc-cname-%s", name, z.zone), &dns.RecordSetArgs{
			Project:     args.ProjectID,
			ManagedZone: managedZone.Name,
			Name:        pulumi.Sprintf("*.%s", z.domain),
			Type:        pulumi.String("CNAME"),
			Ttl:         pulumi.Int(300),
			Rrdatas:     pulumi.StringArray{pulumi.String(z.domain)},
		}, pulumi.Parent(&resource))
		if err != nil {
			return nil, err
		}
	}

	// Mirrors: google_dns_policy.default_policy.
	_, err = dns.NewPolicy(ctx, fmt.Sprintf("%s-default-policy", name), &dns.PolicyArgs{
		Project:                 args.ProjectID,
		Name:                    pulumi.Sprintf("dp-%s-default-policy", vpcName),
		EnableInboundForwarding: pulumi.Bool(true),
		EnableLogging:           pulumi.Bool(true),
		Networks: dns.PolicyNetworkArray{
			&dns.PolicyNetworkArgs{NetworkUrl: network.SelfLink},
		},
	}, pulumi.Parent(&resource))
	if err != nil {
		return nil, err
	}

	// ------------------------------------------------------------------
	// Fleet membership — mirrors module.hub
	// (terraform-google-modules/kubernetes-engine//modules/fleet-membership).
	// ------------------------------------------------------------------
	membership, err := gkehub.NewMembership(ctx, fmt.Sprintf("%s-hub", name), &gkehub.MembershipArgs{
		Project:      args.ProjectID,
		MembershipId: pulumi.Sprintf("%s-membership", agentName),
		Location:     pulumi.String(d.region),
		Endpoint: &gkehub.MembershipEndpointArgs{
			GkeCluster: &gkehub.MembershipEndpointGkeClusterArgs{
				ResourceLink: pulumi.Sprintf("//container.googleapis.com/%s", cluster.ID()),
			},
		},
	}, pulumi.Parent(&resource))
	if err != nil {
		return nil, err
	}

	// Mirrors: google_project_service_identity.container_engine_sa +
	// google_service_account_iam_member.container_engine_sa_impersonate_permissions.
	containerEngineSA, err := projects.NewServiceIdentity(ctx, fmt.Sprintf("%s-container-engine-sa", name), &projects.ServiceIdentityArgs{
		Project: args.ProjectID,
		Service: pulumi.String("container.googleapis.com"),
	}, pulumi.Parent(&resource))
	if err != nil {
		return nil, err
	}
	_, err = serviceaccount.NewIAMMember(ctx, fmt.Sprintf("%s-container-engine-sa-impersonate", name), &serviceaccount.IAMMemberArgs{
		ServiceAccountId: serviceAccountID,
		Role:             pulumi.String("roles/iam.serviceAccountUser"),
		Member:           pulumi.Sprintf("serviceAccount:%s", containerEngineSA.Email),
	}, pulumi.Parent(&resource))
	if err != nil {
		return nil, err
	}

	resource.KubernetesEndpoint = cluster.Endpoint
	resource.ServiceAccount = pulumi.ToOutput(serviceAccountEmail).ApplyT(func(v interface{}) string {
		s, _ := v.(string)
		return s
	}).(pulumi.StringOutput)
	resource.ClusterName = cluster.Name
	resource.HubClusterMembershipID = membership.MembershipId

	return &resource, nil
}
