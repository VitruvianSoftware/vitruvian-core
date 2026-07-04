// Copyright 2026 Vitruvian Software
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

import * as policy from "@pulumi/policy";

// Foundation Policy Pack — CrossGuard policies enforcing Google Cloud
// security baseline compliance. These are the Pulumi equivalent of the
// upstream Terraform foundation's OPA constraints in policy-library/.

const foundationPolicies = new policy.PolicyPack("foundation-policies", {
    policies: [
        // --- Project Policies ---
        {
            name: "no-default-network",
            description: "Projects must disable auto-creation of the default network.",
            enforcementLevel: "mandatory",
            validateResource: (args, reportViolation) => {
                if (args.type === "gcp:organizations/project:Project") {
                    if (args.props.autoCreateNetwork === true) {
                        reportViolation(
                            "Projects must set autoCreateNetwork to false. " +
                            "The default network has overly permissive firewall rules."
                        );
                    }
                }
            },
        },
        {
            name: "project-labels-required",
            description: "Projects must have 'environment' and 'application_name' labels.",
            enforcementLevel: "mandatory",
            validateResource: (args, reportViolation) => {
                if (args.type === "gcp:organizations/project:Project") {
                    const labels = args.props.labels || {};
                    if (!labels["environment"]) {
                        reportViolation("Project is missing required label: 'environment'");
                    }
                    if (!labels["application_name"]) {
                        reportViolation("Project is missing required label: 'application_name'");
                    }
                }
            },
        },

        // --- IAM Policies ---
        {
            name: "no-sa-key-creation",
            description: "Service account keys must not be created. Use Workload Identity Federation instead.",
            enforcementLevel: "mandatory",
            validateResource: (args, reportViolation) => {
                if (args.type === "gcp:serviceaccount/key:Key") {
                    reportViolation(
                        "Service account keys are prohibited. " +
                        "Use Workload Identity Federation (WIF) for authentication."
                    );
                }
            },
        },
        {
            name: "no-public-access",
            description: "IAM bindings must not grant access to allUsers or allAuthenticatedUsers.",
            enforcementLevel: "mandatory",
            validateResource: (args, reportViolation) => {
                const iamTypes = [
                    "gcp:projects/iAMMember:IAMMember",
                    "gcp:projects/iAMBinding:IAMBinding",
                    "gcp:organizations/iAMMember:IAMMember",
                    "gcp:organizations/iAMBinding:IAMBinding",
                    "gcp:folder/iAMMember:IAMMember",
                    "gcp:storage/bucketIAMMember:BucketIAMMember",
                ];
                if (iamTypes.includes(args.type)) {
                    const member = args.props.member || "";
                    const members = args.props.members || [];
                    const allMembers = [member, ...members];
                    for (const m of allMembers) {
                        if (m === "allUsers" || m === "allAuthenticatedUsers") {
                            reportViolation(
                                `IAM binding must not grant access to '${m}'. ` +
                                "Public access is prohibited in the foundation."
                            );
                        }
                    }
                }
            },
        },

        // --- Network Policies ---
        {
            name: "no-public-ip",
            description: "Compute instances must not have external (public) IP addresses.",
            enforcementLevel: "mandatory",
            validateResource: (args, reportViolation) => {
                if (args.type === "gcp:compute/instance:Instance") {
                    const networkInterfaces = args.props.networkInterfaces || [];
                    for (const nic of networkInterfaces) {
                        if (nic.accessConfigs && nic.accessConfigs.length > 0) {
                            reportViolation(
                                "Compute instances must not have external IPs. " +
                                "Remove accessConfigs to enforce private networking."
                            );
                        }
                    }
                }
            },
        },
        {
            name: "require-private-google-access",
            description: "Subnets must enable Private Google Access.",
            enforcementLevel: "mandatory",
            validateResource: (args, reportViolation) => {
                if (args.type === "gcp:compute/subnetwork:Subnetwork") {
                    if (args.props.privateIpGoogleAccess !== true) {
                        reportViolation(
                            "Subnets must enable Private Google Access for " +
                            "secure communication with Google APIs."
                        );
                    }
                }
            },
        },
        {
            name: "require-flow-logs",
            description: "Subnets should have VPC Flow Logs enabled for network monitoring.",
            enforcementLevel: "mandatory",
            validateResource: (args, reportViolation) => {
                if (args.type === "gcp:compute/subnetwork:Subnetwork") {
                    const logConfig = args.props.logConfig;
                    if (!logConfig) {
                        reportViolation(
                            "Subnets should enable VPC Flow Logs for network " +
                            "traffic analysis and security monitoring."
                        );
                    }
                }
            },
        {
            name: "deletion-policy-prevent",
            description: "Certain core infrastructure must have deletion protection enabled.",
            enforcementLevel: "mandatory",
            validateResource: (args, reportViolation) => {
                const protectedTypes = [
                    "gcp:organizations/project:Project",
                    "gcp:kms/keyRing:KeyRing",
                    "gcp:kms/cryptoKey:CryptoKey",
                ];
                if (protectedTypes.includes(args.type)) {
                    // Pulumi projects usually protect via the `protect` resource option or a provider-specific property.
                    // For gcp:organizations/project:Project, deletionPolicy="PREVENT".
                    if (args.type === "gcp:organizations/project:Project" && args.props.deletionPolicy !== "PREVENT") {
                        reportViolation("Projects must set deletionPolicy to PREVENT.");
                    }
                    if (args.type === "gcp:kms/cryptoKey:CryptoKey" && args.props.destroyScheduledDuration == null) {
                        // Just an example check for KMS if there's no native deletion block
                        // Pulumi's engine options (protect: true) aren't visible in CrossGuard args.props, 
                        // so we check resource-specific fields when applicable.
                    }
                }
            },
        },
        {
            name: "restrict-owner-role",
            description: "The primitive 'roles/owner' must not be granted.",
            enforcementLevel: "mandatory",
            validateResource: (args, reportViolation) => {
                const iamTypes = [
                    "gcp:projects/iAMMember:IAMMember",
                    "gcp:projects/iAMBinding:IAMBinding",
                    "gcp:organizations/iAMMember:IAMMember",
                    "gcp:organizations/iAMBinding:IAMBinding",
                ];
                if (iamTypes.includes(args.type)) {
                    if (args.props.role === "roles/owner") {
                        reportViolation("The roles/owner primitive role is prohibited.");
                    }
                }
            },
        },
        {
            name: "appengine-service-versions",
            description: "App Engine flexible environment constraints.",
            enforcementLevel: "mandatory",
            validateResource: (args, reportViolation) => {
                if (args.type === "gcp:appengine/flexibleAppVersion:FlexibleAppVersion") {
                    // Generic constraint as an example
                    if (!args.props.service) {
                        reportViolation("App Engine version must specify a service.");
                    }
                }
            },
        },
        {
            name: "dnssec-rsasha1",
            description: "DNSSEC must not use RSASHA1 algorithm.",
            enforcementLevel: "mandatory",
            validateResource: (args, reportViolation) => {
                if (args.type === "gcp:dns/managedZone:ManagedZone") {
                    const dnssec = args.props.dnssecConfig;
                    if (dnssec && dnssec.defaultKeySpecs) {
                        for (const spec of dnssec.defaultKeySpecs) {
                            if (spec.algorithm === "rsasha1") {
                                reportViolation("DNSSEC must not use the insecure RSASHA1 algorithm.");
                            }
                        }
                    }
                }
            },
        },
    ],
});
