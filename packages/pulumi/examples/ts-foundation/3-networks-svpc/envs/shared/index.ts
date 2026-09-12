/**
 * 3-networks-svpc/envs/shared/index.ts
 * Shared resources for SVPC — hierarchical firewall policy
 */

import * as pulumi from "@pulumi/pulumi";
import { HierarchicalFirewallPolicy } from "@vitruviansoftware/foundation-hierarchical-firewall-policy";

export = async () => {
  const config = new pulumi.Config();
  const orgRef = new pulumi.StackReference("org");

  const networkFolderName = orgRef.getOutput(
    "network_folder_name",
  ) as pulumi.Output<string>;
  const orgId = config.require("org_id");
  const parentFolder = config.get("parent_folder") || "";
  const parentNode =
    parentFolder !== "" ? `folders/${parentFolder}` : `organizations/${orgId}`;

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
        ranges: [
          "35.191.0.0/16",
          "130.211.0.0/22",
          "209.85.152.0/22",
          "209.85.204.0/22",
        ],
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
        layer4Configs: [{ ipProtocol: "tcp", ports: ["22", "3389"] }],
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
    hierarchical_fw: fwPolicy.policyId,
  };
};
