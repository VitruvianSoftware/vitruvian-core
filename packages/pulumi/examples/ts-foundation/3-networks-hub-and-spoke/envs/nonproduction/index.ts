/**
 * 3-networks-hub-and-spoke/envs/nonproduction/index.ts
 * Per-environment spoke network — mirrors envs/nonproduction/main.tf
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { SharedVpc } from "../../modules/shared_vpc";
import * as time from "@pulumiverse/time";

export = async () => {
  const config = new pulumi.Config();
  const orgRef = new pulumi.StackReference("org");
  const envRef = new pulumi.StackReference("env-nonproduction");

  const sharedVpcProjects = orgRef.getOutput(
    "shared_vpc_projects",
  ) as pulumi.Output<
    Record<string, { project_id: string; project_number: string }>
  >;
  const envProjectId = sharedVpcProjects.apply(
    (p) => p["nonproduction"]?.project_id || "",
  );
  const envProjectNumber = sharedVpcProjects.apply(
    (p) => p["nonproduction"]?.project_number || "",
  );

  const defaultRegion = config.get("default_region") || "us-central1";
  const defaultRegion2 = config.get("default_region_2") || "us-west1";
  const envCode = "n";

  const vpcFlowLogs = config.getObject<any>("vpc_flow_logs") || {
    aggregation_interval: "INTERVAL_5_SEC",
    flow_sampling: 0.5,
    metadata: "INCLUDE_ALL_METADATA",
  };
  const dnsEnableLogging = config.getBoolean("dns_enable_logging") ?? true;
  const firewallEnableLogging =
    config.getBoolean("firewall_policies_enable_logging") ?? true;
  const domain = config.get("domain") || "example.com.";

  const spokeVpc = new SharedVpc("nonproduction-network", {
    projectId: envProjectId,
    environmentCode: envCode,
    orgId: config.require("org_id"),
    parent: config.require("parent"),
    defaultRegion: defaultRegion,
    defaultRegion2: defaultRegion2,
    mode: "spoke",
    natEnabled: true,
    dnsEnableInboundForwarding: true,
    dnsEnableLogging: dnsEnableLogging,
    firewallEnableLogging: firewallEnableLogging,
    domain: domain,
    dnsHubProjectId: sharedVpcProjects.apply(
      (p) => p["production"]?.project_id || "",
    ),
    pscAddress: "10.2.0.20",
    netHubProjectId: config.get("net_hub_project_id"),
    netHubNetworkSelfLink: pulumi.interpolate`projects/${config.get("net_hub_project_id")}/global/networks/vpc-c-svpc-hub`,
    subnets: [
      {
        subnetName: `sb-${envCode}-svpc-spoke-${defaultRegion}`,
        subnetIp: "10.0.128.0/21",
        subnetRegion: defaultRegion,
        subnetPrivateAccess: true,
        subnetFlowLogs: true,
        subnetFlowLogsInterval: vpcFlowLogs.aggregation_interval,
        subnetFlowLogsSampling: vpcFlowLogs.flow_sampling,
        subnetFlowLogsMetadata: vpcFlowLogs.metadata,
        description: "nonproduction spoke subnet in primary region",
      },
      {
        subnetName: `sb-${envCode}-svpc-spoke-${defaultRegion2}`,
        subnetIp: "10.1.128.0/21",
        subnetRegion: defaultRegion2,
        subnetPrivateAccess: true,
        subnetFlowLogs: true,
        subnetFlowLogsInterval: vpcFlowLogs.aggregation_interval,
        subnetFlowLogsSampling: vpcFlowLogs.flow_sampling,
        subnetFlowLogsMetadata: vpcFlowLogs.metadata,
        description: "nonproduction spoke subnet in secondary region",
      },
    ],
  });

  // VPC Service Controls (mirrors TF base_env/service_control.tf)
  const policyId = orgRef.getOutput(
    "access_context_manager_policy_id",
  ) as pulumi.Output<string>;
  const vpcScMembers = config.getObject<string[]>("vpc_sc_members") || [];
  const enforceVpcSc = config.getBoolean("enforce_vpc_sc") ?? true;

  const { VpcServiceControls, DEFAULT_RESTRICTED_SERVICES } =
    await import("@vitruviansoftware/foundation-vpc-service-controls");

  const vpcScIngressPolicies =
    config.getObject<
      gcp.types.input.accesscontextmanager.ServicePerimeterStatusIngressPolicy[]
    >("vpc_sc_ingress_policies") || [];
  const vpcScEgressPolicies =
    config.getObject<
      gcp.types.input.accesscontextmanager.ServicePerimeterStatusEgressPolicy[]
    >("vpc_sc_egress_policies") || [];
  const vpcScIngressPoliciesDryRun =
    config.getObject<
      gcp.types.input.accesscontextmanager.ServicePerimeterSpecIngressPolicy[]
    >("vpc_sc_ingress_policies_dry_run") || [];
  const vpcScEgressPoliciesDryRun =
    config.getObject<
      gcp.types.input.accesscontextmanager.ServicePerimeterSpecEgressPolicy[]
    >("vpc_sc_egress_policies_dry_run") || [];

  const vpcSc = new VpcServiceControls("vpc-sc-perimeter", {
    policyId: policyId,
    prefix: `n_spoke`,
    members: vpcScMembers,
    membersDryRun: vpcScMembers,
    projectNumbers: [envProjectNumber],
    restrictedServices: DEFAULT_RESTRICTED_SERVICES,
    enforce: enforceVpcSc,
    ingressPolicies: vpcScIngressPolicies,
    egressPolicies: vpcScEgressPolicies,
    ingressPoliciesDryRun: vpcScIngressPoliciesDryRun,
    egressPoliciesDryRun: vpcScEgressPoliciesDryRun,
  });

  // 60-second propagation wait for VPC-SC
  const vpcScSleep = new time.Sleep(
    "vpc-sc-propagation-wait",
    {
      createDuration: "60s",
    },
    { dependsOn: vpcSc.perimeter },
  );

  return {
    access_context_manager_policy_id: policyId,
    shared_vpc_host_project_id: envProjectId,
    network_id: spokeVpc.networkId,
    network_name: spokeVpc.networkName,
    network_self_link: spokeVpc.networkSelfLink,
    subnets_names: spokeVpc.subnetsNames,
    subnets_ips: spokeVpc.subnetsIps,
    subnets_self_links: spokeVpc.subnetsSelfLinks,
    subnets_secondary_ranges: spokeVpc.subnetsSecondaryRanges,
    access_level_name: vpcSc.accessLevel.name,
    access_level_name_dry_run: vpcSc.accessLevelDryRun.name,
    enforce_vpcsc: enforceVpcSc,
    service_perimeter_name: vpcScSleep.id.apply(() => vpcSc.perimeter.name),
  };
};
