/**
 * 3-networks-svpc/envs/production/index.ts
 * SVPC network for production — mirrors envs/production/main.tf
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { SharedVpc } from "../../modules/shared_vpc";
import { VpcServiceControls, DEFAULT_RESTRICTED_SERVICES } from "@vitruviansoftware/foundation-vpc-service-controls";
import * as time from "@pulumiverse/time";

export = async () => {
    const config = new pulumi.Config();
    const orgRef = new pulumi.StackReference("org");

    const sharedVpcProjects = orgRef.getOutput("shared_vpc_projects") as pulumi.Output<Record<string, { project_id: string; project_number: string }>>;
    const envProjectId = sharedVpcProjects.apply(p => p["production"]?.project_id || "");

    const defaultRegion = config.get("default_region") || "us-central1";
    const defaultRegion2 = config.get("default_region_2") || "us-west1";

    const vpcFlowLogs = config.getObject<any>("vpc_flow_logs") || {
        aggregation_interval: "INTERVAL_5_SEC",
        flow_sampling: 0.5,
        metadata: "INCLUDE_ALL_METADATA",
    };
    const dnsEnableLogging = config.getBoolean("dns_enable_logging") ?? true;
    const firewallEnableLogging = config.getBoolean("firewall_policies_enable_logging") ?? true;

    const targetNameServerAddresses = config.getObject<string[]>("target_name_server_addresses") || ["10.0.0.1"];
    const domain = config.get("domain") || "example.com.";

    const svpc = new SharedVpc("production-network", {
        projectId: envProjectId,
        environmentCode: "p",
        orgId: config.require("org_id"),
        parent: config.require("parent"),
        defaultRegion: defaultRegion,
        defaultRegion2: defaultRegion2,
        mode: null,
        natEnabled: true,
        dnsEnableInboundForwarding: true,
        dnsEnableLogging: dnsEnableLogging,
        firewallEnableLogging: firewallEnableLogging,
        domain: domain,
        targetNameServerAddresses: targetNameServerAddresses,
        pscAddress: "10.2.0.30",
        subnets: [
            {
                subnetName: `sb-p-svpc-${defaultRegion}`,
                subnetIp: "10.0.192.0/21",
                subnetRegion: defaultRegion,
                subnetPrivateAccess: true,
                subnetFlowLogs: true,
                subnetFlowLogsInterval: vpcFlowLogs.aggregation_interval,
                subnetFlowLogsSampling: vpcFlowLogs.flow_sampling,
                subnetFlowLogsMetadata: vpcFlowLogs.metadata,
                description: "production SVPC subnet in primary region",
            },
            {
                subnetName: `sb-p-svpc-${defaultRegion2}`,
                subnetIp: "10.1.192.0/21",
                subnetRegion: defaultRegion2,
                subnetPrivateAccess: true,
                subnetFlowLogs: true,
                subnetFlowLogsInterval: vpcFlowLogs.aggregation_interval,
                subnetFlowLogsSampling: vpcFlowLogs.flow_sampling,
                subnetFlowLogsMetadata: vpcFlowLogs.metadata,
                description: "production SVPC subnet in secondary region",
            },
        ],
    });

    // VPC Service Controls Perimeter (was missing — mirrors Go foundation's section 10)
    const policyId = orgRef.getOutput("access_context_manager_policy_id") as pulumi.Output<string>;
    let perimeterName: pulumi.Output<string> | undefined;

    const vpcScMembers = config.getObject<string[]>("vpc_sc_members") || [];
    const enforceVpcSc = config.getBoolean("enforce_vpc_sc") ?? true;
    
    // In SVPC, the host project is the one we are protecting initially
    const envProjectNumber = sharedVpcProjects.apply(p => p["production"]?.project_number || "");
    const additionalVpcScProjects = config.getObject<string[]>("vpc_sc_project_numbers") || [];
    const allProjectNumbers = [envProjectNumber, ...additionalVpcScProjects];

    const vpcScIngressPolicies = config.getObject<gcp.types.input.accesscontextmanager.ServicePerimeterStatusIngressPolicy[]>("vpc_sc_ingress_policies") || [];
    const vpcScEgressPolicies = config.getObject<gcp.types.input.accesscontextmanager.ServicePerimeterStatusEgressPolicy[]>("vpc_sc_egress_policies") || [];
    const vpcScIngressPoliciesDryRun = config.getObject<gcp.types.input.accesscontextmanager.ServicePerimeterSpecIngressPolicy[]>("vpc_sc_ingress_policies_dry_run") || [];
    const vpcScEgressPoliciesDryRun = config.getObject<gcp.types.input.accesscontextmanager.ServicePerimeterSpecEgressPolicy[]>("vpc_sc_egress_policies_dry_run") || [];

    const enableDedicatedInterconnect = config.getBoolean("enable_dedicated_interconnect") ?? false;
    
    // Automatic egress policy for dedicated interconnect
    if (enableDedicatedInterconnect) {
        vpcScEgressPolicies.push({
            egressFrom: {
                identities: [],
                identityType: "ANY_IDENTITY",
            },
            egressTo: {
                resources: ["*"],
                operations: [{
                    serviceName: "compute.googleapis.com",
                    methodSelectors: [{
                        method: "*",
                    }],
                }],
            },
        });
        vpcScEgressPoliciesDryRun.push({
            egressFrom: {
                identities: [],
                identityType: "ANY_IDENTITY",
            },
            egressTo: {
                resources: ["*"],
                operations: [{
                    serviceName: "compute.googleapis.com",
                    methodSelectors: [{
                        method: "*",
                    }],
                }],
            },
        });
    }

    const vpcSc = new VpcServiceControls("vpc-sc-perimeter", {
        policyId: policyId,
        prefix: "p_svpc",
        members: vpcScMembers,
        membersDryRun: vpcScMembers,
        projectNumbers: allProjectNumbers,
        restrictedServices: DEFAULT_RESTRICTED_SERVICES,
        enforce: enforceVpcSc,
        ingressPolicies: vpcScIngressPolicies,
        egressPolicies: vpcScEgressPolicies,
        ingressPoliciesDryRun: vpcScIngressPoliciesDryRun,
        egressPoliciesDryRun: vpcScEgressPoliciesDryRun,
    });

    // 60-second propagation wait for VPC-SC
    const vpcScSleep = new time.Sleep("vpc-sc-propagation-wait", {
        createDuration: "60s",
    }, { dependsOn: vpcSc.perimeter });

    perimeterName = vpcScSleep.id.apply(() => vpcSc.perimeter.name);

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

