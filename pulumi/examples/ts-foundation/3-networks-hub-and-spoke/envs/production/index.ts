/**
 * 3-networks-hub-and-spoke/envs/production/index.ts
 * Per-environment spoke network — mirrors envs/production/main.tf
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { SharedVpc } from "../../modules/shared_vpc";

export = async () => {
    const config = new pulumi.Config();
    const orgRef = new pulumi.StackReference("org");
    const envRef = new pulumi.StackReference("env-production");

    const sharedVpcProjects = orgRef.getOutput("shared_vpc_projects") as pulumi.Output<Record<string, { project_id: string; project_number: string }>>;
    const envProjectId = sharedVpcProjects.apply(p => p["production"]?.project_id || "");
    const envProjectNumber = sharedVpcProjects.apply(p => p["production"]?.project_number || "");

    const defaultRegion = config.get("default_region") || "us-central1";
    const defaultRegion2 = config.get("default_region_2") || "us-west1";
    const envCode = "p";

    const spokeVpc = new SharedVpc("production-network", {
        projectId: envProjectId,
        environmentCode: envCode,
        orgId: config.require("org_id"),
        parent: config.require("parent"),
        defaultRegion: defaultRegion,
        defaultRegion2: defaultRegion2,
        mode: "spoke",
        natEnabled: true,
        dnsEnableInboundForwarding: true,
        dnsEnableLogging: true,
        pscAddress: "10.2.0.30",
        netHubProjectId: config.get("net_hub_project_id"),
        subnets: [
            {
                subnetName: `sb-${envCode}-svpc-spoke-${defaultRegion}`,
                subnetIp: "10.0.192.0/21",
                subnetRegion: defaultRegion,
                subnetPrivateAccess: true,
                subnetFlowLogs: true,
                description: "production spoke subnet in primary region",
            },
            {
                subnetName: `sb-${envCode}-svpc-spoke-${defaultRegion2}`,
                subnetIp: "10.1.192.0/21",
                subnetRegion: defaultRegion2,
                subnetPrivateAccess: true,
                subnetFlowLogs: true,
                description: "production spoke subnet in secondary region",
            },
        ],
    });


    // VPC Service Controls (mirrors TF base_env/service_control.tf)
    const policyId = orgRef.getOutput("access_context_manager_policy_id") as pulumi.Output<string>;
    const vpcScMembers = config.getObject<string[]>("vpc_sc_members") || [];
    const enforceVpcSc = config.getBoolean("enforce_vpc_sc") ?? true;

    const { VpcServiceControls, DEFAULT_RESTRICTED_SERVICES } = await import("@vitruviansoftware/foundation-vpc-service-controls");
    const vpcSc = new VpcServiceControls("vpc-sc-perimeter", {
        policyId: policyId,
        prefix: `p_spoke`,
        members: vpcScMembers,
        membersDryRun: vpcScMembers,
        projectNumbers: [envProjectNumber],
        restrictedServices: DEFAULT_RESTRICTED_SERVICES,
        enforce: enforceVpcSc,
    });

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
        service_perimeter_name: vpcSc.perimeter.name,
    };
};
