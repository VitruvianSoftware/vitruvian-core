/**
 * 3-networks-hub-and-spoke/envs/shared/index.ts
 * Hub network deployment — mirrors envs/shared/net-hubs.tf, hierarchical_firewall.tf
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { SharedVpc } from "../../modules/shared_vpc";
import { HierarchicalFirewallPolicy } from "@vitruviansoftware/foundation-hierarchical-firewall-policy";

export = async () => {
    const config = new pulumi.Config();
    const orgRef = new pulumi.StackReference("org");

    const networkFolderName = orgRef.getOutput("network_folder_name") as pulumi.Output<string>;
    const netHubProjectId = orgRef.getOutput("net_hub_project_id") as pulumi.Output<string>;

    const defaultRegion = config.get("default_region") || "us-central1";
    const defaultRegion2 = config.get("default_region_2") || "us-west1";

    // Hub VPC
    const hubVpc = new SharedVpc("hub-network", {
        projectId: netHubProjectId,
        environmentCode: "c",
        orgId: config.require("org_id"),
        parent: config.require("parent"),
        defaultRegion: defaultRegion,
        defaultRegion2: defaultRegion2,
        mode: "hub",
        natEnabled: true,
        dnsEnableInboundForwarding: true,
        dnsEnableLogging: true,
        pscAddress: "10.2.0.30",
        subnets: [
            {
                subnetName: `sb-c-svpc-hub-${defaultRegion}`,
                subnetIp: "10.0.0.0/24",
                subnetRegion: defaultRegion,
                subnetPrivateAccess: true,
                subnetFlowLogs: true,
                description: "Hub subnet in primary region",
            },
            {
                subnetName: `sb-c-svpc-hub-${defaultRegion2}`,
                subnetIp: "10.1.0.0/24",
                subnetRegion: defaultRegion2,
                subnetPrivateAccess: true,
                subnetFlowLogs: true,
                description: "Hub subnet in secondary region",
            },
        ],
    });

    // Hierarchical firewall policy
    const orgId = config.require("org_id");
    const parentFolder = config.get("parent_folder") || "";
    const parentNode = parentFolder !== "" ? `folders/${parentFolder}` : `organizations/${orgId}`;

    const fwPolicy = new HierarchicalFirewallPolicy("org-firewall-policy", {
        parentNode: parentNode,
        name: "fw-policy-foundation",
        description: "Foundation hierarchical firewall policy",
        rules: [
            {
                description: "Allow private RFC1918 ingress",
                direction: "INGRESS",
                action: "allow",
                priority: 100,
                ranges: ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"],
                enableLogging: true,
                layer4Configs: [{ ipProtocol: "all" }],
            },
            {
                description: "Allow GCP health check ranges",
                direction: "INGRESS",
                action: "allow",
                priority: 200,
                ranges: ["35.191.0.0/16", "130.211.0.0/22", "209.85.152.0/22", "209.85.204.0/22"],
                enableLogging: true,
                layer4Configs: [{ ipProtocol: "tcp" }],
            },
            {
                description: "Allow IAP for SSH/RDP",
                direction: "INGRESS",
                action: "allow",
                priority: 300,
                ranges: ["35.235.240.0/20"],
                enableLogging: true,
                layer4Configs: [
                    { ipProtocol: "tcp", ports: ["22", "3389"] },
                ],
            },
            {
                description: "Deny all other ingress",
                direction: "INGRESS",
                action: "deny",
                priority: 65534,
                ranges: ["0.0.0.0/0"],
                enableLogging: true,
                layer4Configs: [{ ipProtocol: "all" }],
            },
        ],
        targetFolders: [networkFolderName],
    });

    return {
        shared_vpc_host_project_id: netHubProjectId,
        network_name: hubVpc.networkName,
        network_id: hubVpc.networkId,
        network_self_link: hubVpc.networkSelfLink,
        dns_policy: hubVpc.dnsPolicy,
        hierarchical_fw: fwPolicy.policyId,
    };
};
