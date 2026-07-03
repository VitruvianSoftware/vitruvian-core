/**
 * 3-networks-svpc/envs/nonproduction/index.ts
 * SVPC network for nonproduction — mirrors envs/nonproduction/main.tf
 */

import * as pulumi from "@pulumi/pulumi";
import { SharedVpc } from "../../modules/shared_vpc";
import { VpcServiceControls, DEFAULT_RESTRICTED_SERVICES } from "@vitruviansoftware/foundation-vpc-service-controls";

export = async () => {
    const config = new pulumi.Config();
    const orgRef = new pulumi.StackReference("org");

    const sharedVpcProjects = orgRef.getOutput("shared_vpc_projects") as pulumi.Output<Record<string, { project_id: string; project_number: string }>>;
    const envProjectId = sharedVpcProjects.apply(p => p["nonproduction"]?.project_id || "");

    const defaultRegion = config.get("default_region") || "us-central1";
    const defaultRegion2 = config.get("default_region_2") || "us-west1";

    const vpcFlowLogs = config.getObject<any>("vpc_flow_logs") || {
        aggregation_interval: "INTERVAL_5_SEC",
        flow_sampling: 0.5,
        metadata: "INCLUDE_ALL_METADATA",
    };
    const dnsEnableLogging = config.getBoolean("dns_enable_logging") ?? true;
    const firewallEnableLogging = config.getBoolean("firewall_policies_enable_logging") ?? true;


    const svpc = new SharedVpc("nonproduction-network", {
        projectId: envProjectId,
        environmentCode: "n",
        orgId: config.require("org_id"),
        parent: config.require("parent"),
        defaultRegion: defaultRegion,
        defaultRegion2: defaultRegion2,
        mode: null,
        natEnabled: true,
        dnsEnableInboundForwarding: true,
        dnsEnableLogging: dnsEnableLogging,
        firewallEnableLogging: firewallEnableLogging,
        pscAddress: "10.2.0.20",
        subnets: [
            {
                subnetName: `sb-n-svpc-${defaultRegion}`,
                subnetIp: "10.0.128.0/21",
                subnetRegion: defaultRegion,
                subnetPrivateAccess: true,
                subnetFlowLogs: true,
                subnetFlowLogsInterval: vpcFlowLogs.aggregation_interval,
                subnetFlowLogsSampling: vpcFlowLogs.flow_sampling,
                subnetFlowLogsMetadata: vpcFlowLogs.metadata,
                description: "nonproduction SVPC subnet in primary region",
            },
            {
                subnetName: `sb-n-svpc-${defaultRegion2}`,
                subnetIp: "10.1.128.0/21",
                subnetRegion: defaultRegion2,
                subnetPrivateAccess: true,
                subnetFlowLogs: true,
                subnetFlowLogsInterval: vpcFlowLogs.aggregation_interval,
                subnetFlowLogsSampling: vpcFlowLogs.flow_sampling,
                subnetFlowLogsMetadata: vpcFlowLogs.metadata,
                description: "nonproduction SVPC subnet in secondary region",
            },
        ],
    });


    // VPC Service Controls Perimeter (mirrors Go foundation's section 10)
    const policyId = orgRef.getOutput("access_context_manager_policy_id") as pulumi.Output<string>;
    let perimeterName: pulumi.Output<string> | undefined;

    const vpcScMembers = config.getObject<string[]>("vpc_sc_members") || [];
    const enforceVpcSc = config.getBoolean("enforce_vpc_sc") ?? true;
    
    // In SVPC, the host project is the one we are protecting initially
    const envProjectNumber = sharedVpcProjects.apply(p => p["nonproduction"]?.project_number || "");
    const additionalVpcScProjects = config.getObject<string[]>("vpc_sc_project_numbers") || [];
    const allProjectNumbers = [envProjectNumber, ...additionalVpcScProjects];

    const vpcSc = new VpcServiceControls("vpc-sc-perimeter", {
        policyId: policyId,
        prefix: "n_svpc",
        members: vpcScMembers,
        membersDryRun: vpcScMembers,
        projectNumbers: allProjectNumbers,
        restrictedServices: DEFAULT_RESTRICTED_SERVICES,
        enforce: enforceVpcSc,
    });

    perimeterName = vpcSc.perimeter.name;

    const targetNameServerAddresses = config.getObject<string[]>("target_name_server_addresses") || ["10.0.0.1"];

    return {
        target_name_server_addresses: targetNameServerAddresses,
        access_context_manager_policy_id: policyId,
        shared_vpc_host_project_id: envProjectId,
        network_name: svpc.networkName,
        network_self_link: svpc.networkSelfLink,
        subnets_names: svpc.subnetsNames,
        subnets_ips: svpc.subnetsIps,
        subnets_self_links: svpc.subnetsSelfLinks,
        subnets_secondary_ranges: svpc.subnetsSecondaryRanges,
        access_level_name: vpcSc.accessLevel.name,
        access_level_name_dry_run: vpcSc.accessLevelDryRun.name,
        enforce_vpcsc: enforceVpcSc,
        service_perimeter_name: perimeterName,
    };
};
