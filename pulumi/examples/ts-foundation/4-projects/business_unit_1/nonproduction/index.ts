
import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { NetworkFirewallPolicy } from "@vitruviansoftware/foundation-network-firewall-policy";
import { deploySingleProject } from "../../modules/single_project";

export = async () => {
    const config = new pulumi.Config();
    const orgRef = new pulumi.StackReference("org");
    const envRef = new pulumi.StackReference("env-nonproduction");

    const orgId = config.require("org_id");
    const billingAccount = config.require("billing_account");
    const projectPrefix = config.get("project_prefix") || "prj";
    const folderPrefix = config.get("folder_prefix") || "fldr";
    const businessCode = config.get("business_code") || "bu1";
    const businessUnitName = config.get("business_unit_name") || "business_unit_1";
    const envCode = "n";

    // Environment folder from 2-environments
    const envFolder = envRef.getOutput("env_folder") as pulumi.Output<string>;

    // Network stack reference for Shared VPC host project ID
    const netRef = new pulumi.StackReference(`net-svpc-nonproduction`);
    const sharedVpcHostProjectId = orgRef.getOutput("shared_vpc_projects").apply(
        (p: Record<string, { project_id: string }>) => p["nonproduction"]?.project_id || ""
    );

    // BU folder under env
    const buFolder = new gcp.organizations.Folder("bu-folder", {
        displayName: `${folderPrefix}-nonproduction-${businessCode}`,
        parent: envFolder,
        deletionProtection: config.getBoolean("folder_deletion_protection") ?? true,
    });

    // Example Shared VPC project (attached to SVPC host — mirrors TF example_shared_vpc_project.tf)
    const sharedVpcProject = deploySingleProject("sample-svpc", {
        orgId: orgId,
        billingAccount: billingAccount,
        folderId: buFolder.name,
        environment: "nonproduction",
        projectPrefix: projectPrefix,
        projectSuffix: "sample-svpc",
        businessCode: businessCode,
        applicationName: `${businessCode}-sample-application`,
        billingCode: "1234",
        primaryContact: "example@example.com",
        secondaryContact: "example2@example.com",
        vpc: "svpc",
        activateApis: ["accesscontextmanager.googleapis.com"],
        projectDeletionPolicy: config.get("project_deletion_policy") || "PREVENT",
        sharedVpcHostProjectId: sharedVpcHostProjectId,
        saRoles: {
            [`${businessCode}-example-app`]: [
                "roles/compute.instanceAdmin.v1",
                "roles/iam.serviceAccountUser",
                "roles/iam.serviceAccountAdmin",
            ],
        },
    });

    // Example floating project (no VPC)
    const floatingProject = deploySingleProject("sample-floating", {
        orgId: orgId,
        billingAccount: billingAccount,
        folderId: buFolder.name,
        environment: "nonproduction",
        projectPrefix: projectPrefix,
        projectSuffix: "sample-float",
        businessCode: businessCode,
        applicationName: `${businessCode}-sample-floating`,
        billingCode: "1234",
        primaryContact: "example@example.com",
        secondaryContact: "example2@example.com",
        vpc: "none",
        projectDeletionPolicy: config.get("project_deletion_policy") || "PREVENT",
    });

    // ====================================================================
    // Example Peering Project (mirrors TF example_peering_project.tf)
    // ====================================================================
    const defaultRegion = config.get("default_region") || "us-central1";
    const firewallEnableLogging = config.getBoolean("firewall_enable_logging") ?? true;
    const peeringIapFwEnabled = config.getBoolean("peering_iap_fw_rules_enabled") ?? true;
    const optionalFwRulesEnabled = config.getBoolean("optional_fw_rules_enabled") ?? false;
    const windowsActivationEnabled = config.getBoolean("windows_activation_enabled") ?? false;

    const peeringProject = deploySingleProject("sample-peering", {
        orgId: orgId,
        billingAccount: billingAccount,
        folderId: buFolder.name,
        environment: "nonproduction",
        projectPrefix: projectPrefix,
        projectSuffix: "sample-peering",
        businessCode: businessCode,
        applicationName: `${businessCode}-sample-peering`,
        billingCode: "1234",
        primaryContact: "example@example.com",
        secondaryContact: "example2@example.com",
        vpc: "peering",
        activateApis: ["dns.googleapis.com"],
        projectDeletionPolicy: config.get("project_deletion_policy") || "PREVENT",
        saRoles: {
            [`${businessCode}-example-app`]: [
                "roles/compute.instanceAdmin.v1",
                "roles/iam.serviceAccountAdmin",
                "roles/iam.serviceAccountUser",
                "roles/resourcemanager.tagUser",
            ],
        },
    });

    // Peering network
    const vpcName = `vpc-${envCode}-peering-base`;
    const peeringNetwork = new gcp.compute.Network("peering-network", {
        name: vpcName,
        project: peeringProject.projectId,
        autoCreateSubnetworks: false,
        deleteDefaultRoutesOnCreate: true,
    });

    const peeringSubnet = new gcp.compute.Subnetwork("peering-subnet", {
        name: `sb-${envCode}-${businessCode}-peered-${defaultRegion}`,
        project: peeringProject.projectId,
        network: peeringNetwork.id,
        ipCidrRange: "10.3.64.0/21",
        region: defaultRegion,
        privateIpGoogleAccess: true,
        logConfig: {
            aggregationInterval: "INTERVAL_5_SEC",
            flowSampling: 0.5,
            metadata: "INCLUDE_ALL_METADATA",
        },
    });

    // DNS policy for peering network
    new gcp.dns.Policy("peering-dns-policy", {
        project: peeringProject.projectId,
        name: `dp-${envCode}-peering-base-default-policy`,
        enableInboundForwarding: true,
        enableLogging: true,
        networks: [{ networkUrl: peeringNetwork.selfLink }],
    });

    // VPC peering: peering network → Shared VPC host network
    const hostNetworkSelfLink = netRef.getOutput("network_self_link") as pulumi.Output<string>;
    const peeringToHost = new gcp.compute.NetworkPeering("peering-to-svpc", {
        name: `${businessCode}-${envCode}-peering-to-svpc`,
        network: peeringNetwork.selfLink,
        peerNetwork: hostNetworkSelfLink,
        exportCustomRoutes: true,
        importCustomRoutes: false,
    });

    new gcp.compute.NetworkPeering("svpc-to-peering", {
        name: `svpc-to-${businessCode}-${envCode}-peering-base`,
        network: hostNetworkSelfLink,
        peerNetwork: peeringNetwork.selfLink,
        exportCustomRoutes: true,
        importCustomRoutes: false,
    }, { dependsOn: [peeringToHost] });

    // ================================================================
    // Secure Tags for IAP SSH/RDP access (mirrors Go peering.go:118-163)
    // Uses GCE_FIREWALL-purpose tags for network firewall policy rules.
    // ================================================================
    let sshTagValueId: pulumi.Output<string> | undefined;
    let rdpTagValueId: pulumi.Output<string> | undefined;
    let sshTagKey: gcp.tags.TagKey | undefined;
    let sshTagValue: gcp.tags.TagValue | undefined;
    let rdpTagKey: gcp.tags.TagKey | undefined;
    let rdpTagValue: gcp.tags.TagValue | undefined;

    if (peeringIapFwEnabled) {
        // SSH tag key + value
        sshTagKey = new gcp.tags.TagKey("peering-ssh-tag-key", {
            shortName: "ssh-iap-access",
            parent: pulumi.interpolate`projects/${peeringProject.projectId}`,
            purpose: "GCE_FIREWALL",
            purposeData: {
                network: pulumi.interpolate`${peeringProject.projectId}/${vpcName}`,
            },
        }, { dependsOn: [peeringNetwork] });

        sshTagValue = new gcp.tags.TagValue("peering-ssh-tag-value", {
            shortName: "allow",
            parent: sshTagKey.id,
        });
        sshTagValueId = sshTagValue.id;

        // RDP tag key + value
        rdpTagKey = new gcp.tags.TagKey("peering-rdp-tag-key", {
            shortName: "rdp-iap-access",
            parent: pulumi.interpolate`projects/${peeringProject.projectId}`,
            purpose: "GCE_FIREWALL",
            purposeData: {
                network: pulumi.interpolate`${peeringProject.projectId}/${vpcName}`,
            },
        }, { dependsOn: [peeringNetwork] });

        rdpTagValue = new gcp.tags.TagValue("peering-rdp-tag-value", {
            shortName: "allow",
            parent: rdpTagKey.id,
        });
        rdpTagValueId = rdpTagValue.id;
    }

    // ================================================================
    // Network Firewall Policy for peering project
    // Replaces legacy gcp.compute.Firewall resources with modern
    // NetworkFirewallPolicy + rules. Mirrors Go peering.go:168-176.
    // ================================================================
    const peeringPolicyName = `fp-${envCode}-peering-project-firewalls`;

    const peeringRules: any[] = [
        {
            ruleName: `fw-${envCode}-peering-base-65530-e-n-all-all-tcp-udp`,
            description: "Lower priority rule to deny all egress traffic.",
            direction: "EGRESS",
            action: "deny",
            priority: 65530,
            ranges: ["0.0.0.0/0"],
            layer4Configs: [{ ipProtocol: "tcp" }, { ipProtocol: "udp" }],
            enableLogging: firewallEnableLogging,
        },
        {
            ruleName: `fw-${envCode}-peering-base-10000-e-a-allow-google-apis-all-tcp-443`,
            description: "Lower priority rule to allow private google apis on TCP port 443.",
            direction: "EGRESS",
            action: "allow",
            priority: 10000,
            ranges: ["199.36.153.8/30"],
            layer4Configs: [{ ipProtocol: "tcp", ports: ["443"] }],
            enableLogging: firewallEnableLogging,
        }
    ];

    if (peeringIapFwEnabled && sshTagValueId) {
        peeringRules.push({
            ruleName: `fw-${envCode}-peering-base-1000-i-a-all-allow-iap-ssh-tcp-22`,
            description: "Allow SSH via IAP for tagged instances.",
            direction: "INGRESS",
            action: "allow",
            priority: 1000,
            ranges: ["35.235.240.0/20"],
            layer4Configs: [{ ipProtocol: "tcp", ports: ["22"] }],
            targetSecureTags: [{ name: sshTagValueId }],
            enableLogging: true,
        });
        peeringRules.push({
            ruleName: `fw-${envCode}-peering-base-1001-i-a-all-allow-iap-rdp-tcp-3389`,
            description: "Allow RDP via IAP for tagged instances.",
            direction: "INGRESS",
            action: "allow",
            priority: 1001,
            ranges: ["35.235.240.0/20"],
            layer4Configs: [{ ipProtocol: "tcp", ports: ["3389"] }],
            targetSecureTags: [{ name: rdpTagValueId! }],
            enableLogging: true,
        });
    }

    if (windowsActivationEnabled) {
        peeringRules.push({
            ruleName: `fw-${envCode}-peering-base-0-e-a-allow-win-activation-all-tcp-1688`,
            description: "Allow access to kms.windows.googlecloud.com for Windows license activation.",
            direction: "EGRESS",
            action: "allow",
            priority: 0,
            ranges: ["35.190.247.13/32"],
            layer4Configs: [{ ipProtocol: "tcp", ports: ["1688"] }],
            enableLogging: firewallEnableLogging,
        });
    }

    if (optionalFwRulesEnabled) {
        peeringRules.push({
            ruleName: `fw-${envCode}-peering-base-1002-i-a-all-allow-lb-tcp-80-8080-443`,
            description: "Allow traffic for Internal & Global load balancing health check and load balancing IP ranges.",
            direction: "INGRESS",
            action: "allow",
            priority: 1002,
            ranges: ["35.191.0.0/16", "130.211.0.0/22", "209.85.152.0/22", "209.85.204.0/22"],
            layer4Configs: [{ ipProtocol: "tcp", ports: ["80", "8080", "443"] }],
            enableLogging: firewallEnableLogging,
        });
    }

    new NetworkFirewallPolicy("peering-fw-policy", {
        project: peeringProject.projectId,
        name: peeringPolicyName,
        description: `Firewall rules for Peering Network: ${vpcName}.`,
        network: pulumi.interpolate`projects/${peeringProject.projectId}/global/networks/${peeringNetwork.name}`,
        rules: peeringRules,
    }, { dependsOn: [peeringNetwork] });


    // Network SVPC Reference (for VPC-SC perimeter)
    const perimeterName = netRef.getOutput("service_perimeter_name") as pulumi.Output<string>;

    // Confidential Space Project
    const confidentialSpaceProject = deploySingleProject("confidential-space", {
        orgId: orgId,
        billingAccount: billingAccount,
        folderId: buFolder.name,
        environment: "nonproduction",
        projectPrefix: projectPrefix,
        projectSuffix: "conf-space",
        businessCode: businessCode,
        applicationName: `${businessCode}-confidential-space`,
        billingCode: "1234",
        primaryContact: "example@example.com",
        secondaryContact: "example2@example.com",
        vpc: "none",
        activateApis: [
            "confidentialcomputing.googleapis.com",
            "iamcredentials.googleapis.com",
        ],
        projectDeletionPolicy: config.get("project_deletion_policy") || "PREVENT",
    });

    // Attach to VPC-SC perimeter
    new gcp.accesscontextmanager.ServicePerimeterResource(`nonproduction-confidential-space-perimeter-attachment`, {
        perimeterName: perimeterName,
        resource: pulumi.interpolate`projects/${confidentialSpaceProject.projectNumber}`,
    });

    // Workload Identity SA for Confidential Space
    const workloadIdentitySa = new gcp.serviceaccount.Account(`nonproduction-confidential-space-sa`, {
        accountId: "confidential-space-sa",
        displayName: "Confidential Space Workload Identity SA",
        project: confidentialSpaceProject.projectId,
    });

    // CMEK Storage Example Project
    const cmekProject = deploySingleProject("cmek-example", {
        orgId: orgId,
        billingAccount: billingAccount,
        folderId: buFolder.name,
        environment: "nonproduction",
        projectPrefix: projectPrefix,
        projectSuffix: "cmek",
        businessCode: businessCode,
        applicationName: `${businessCode}-cmek`,
        billingCode: "1234",
        primaryContact: "example@example.com",
        secondaryContact: "example2@example.com",
        vpc: "none",
        activateApis: ["cloudkms.googleapis.com", "storage.googleapis.com"],
        projectDeletionPolicy: config.get("project_deletion_policy") || "PREVENT",
    });

    // Keyring and Key for CMEK Example
    const cmekKeyRing = new gcp.kms.KeyRing(`nonproduction-cmek-keyring`, {
        name: `${projectPrefix}-n-${businessCode}-cmek-keyring`,
        location: config.get("default_region") || "us-central1",
        project: cmekProject.projectId,
    });

    const cmekKey = new gcp.kms.CryptoKey(`nonproduction-cmek-key`, {
        name: `${projectPrefix}-n-${businessCode}-cmek-key`,
        keyRing: cmekKeyRing.id,
        rotationPeriod: "7776000s", // 90 days
        purpose: "ENCRYPT_DECRYPT",
    });

    // Storage SA KMS permissions
    const storageSa = cmekProject.projectNumber.apply(num => `serviceAccount:service-${num}@gs-project-accounts.iam.gserviceaccount.com`);
    new gcp.kms.CryptoKeyIAMMember(`nonproduction-cmek-key-binding`, {
        cryptoKeyId: cmekKey.id,
        role: "roles/cloudkms.cryptoKeyEncrypterDecrypter",
        member: storageSa,
    });

    // CMEK Encrypted Bucket
    new gcp.storage.Bucket(`nonproduction-cmek-bucket`, {
        name: pulumi.interpolate`${cmekProject.projectId}-cmek-bucket`,
        location: config.get("default_region") || "us-central1",
        project: cmekProject.projectId,
        encryption: {
            defaultKmsKeyName: cmekKey.id,
        },
        uniformBucketLevelAccess: true,
        forceDestroy: config.getBoolean("bucket_force_destroy") ?? false,
    }, { dependsOn: [cmekKey] });

    // Build IAP firewall tags map (matching upstream Go peering.go:188-197)
    let iapFirewallTags: pulumi.Output<Record<string, string>> = pulumi.output({} as Record<string, string>);
    if (peeringIapFwEnabled && sshTagKey && sshTagValue && rdpTagKey && rdpTagValue) {
        iapFirewallTags = pulumi.all([sshTagKey.id, sshTagValue.id, rdpTagKey.id, rdpTagValue.id])
            .apply(([sshKeyId, sshValId, rdpKeyId, rdpValId]) => ({
                [sshKeyId]: sshValId,
                [rdpKeyId]: rdpValId,
            }));
    }

    return {
        bu_folder: buFolder.name,
        shared_vpc_project_id: sharedVpcProject.projectId,
        floating_project_id: floatingProject.projectId,
        peering_project_id: peeringProject.projectId,
        peering_network: peeringNetwork.selfLink,
        peering_subnetwork_self_link: peeringSubnet.selfLink,
        iap_firewall_tags: iapFirewallTags,
        confidential_space_project_id: confidentialSpaceProject.projectId,
        confidential_space_project_number: confidentialSpaceProject.projectNumber,
        confidential_space_workload_sa: workloadIdentitySa.email,
        cmek_project_id: cmekProject.projectId,
        cmek_bucket: pulumi.interpolate`${cmekProject.projectId}-cmek-bucket`,
        cmek_keyring: cmekKeyRing.name,
        keys: [cmekKey.name],
        shared_vpc_project_number: sharedVpcProject.projectNumber,
        default_region: config.get("default_region") || "us-central1",
        subnets_self_links: [peeringSubnet.selfLink],
        restricted_enabled_apis: sharedVpcProject.enabledApis,
        vpc_service_control_perimeter_name: netRef.getOutput("service_perimeter_name"),
        access_context_manager_policy_id: netRef.getOutput("access_context_manager_policy_id"),
        peering_complete: peeringToHost.id.apply(_ => true),
    };
};
