/**
 * 5-app-infra/business_unit_1/development/index.ts
 * Mirrors: 5-app-infra/business_unit_1/development/main.tf
 * Deploys example compute instances into the BU project.
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { InstanceTemplate, ComputeInstance } from "@vitruviansoftware/foundation-instance-template";

export = async () => {
    const config = new pulumi.Config();
    const projectRef = new pulumi.StackReference("projects-bu1-development");

    const projectId = projectRef.getOutput("shared_vpc_project_id") as pulumi.Output<string>;
    const region = config.get("region") || "us-central1";
    const machineType = config.get("machine_type") || "f1-micro";
    const numInstances = config.getNumber("num_instances") || 1;
    const hostname = config.get("hostname") || "example-app";

    // Service account for the compute instance
    const sa = new gcp.serviceaccount.Account("example-app-sa", {
        project: projectId,
        accountId: "sa-example-app",
        displayName: "Example app service Account",
        createIgnoreAlreadyExists: true,
    });

    // Instance template
    const template = new InstanceTemplate("example-template", {
        projectId: projectId,
        namePrefix: "example-app",
        machineType: machineType,
        region: region,
        sourceImageFamily: "debian-12",
        sourceImageProject: "debian-cloud",
        diskSizeGb: 100,
        diskType: "pd-ssd",
        subnetwork: `projects/${config.get("shared_vpc_host_project") || ""}/regions/${region}/subnetworks/sb-d-svpc-${region}`,
        serviceAccount: {
            email: sa.email,
            scopes: ["compute-rw"],
        },
        metadata: {
            "block-project-ssh-keys": "true",
        },
    });

    // Compute instance
    const instance = new ComputeInstance("example-instance", {
        projectId: projectId,
        zone: `${region}-a`,
        instanceName: hostname,
        instanceTemplate: template.templateSelfLink,
        subnetwork: `projects/${config.get("shared_vpc_host_project") || ""}/regions/${region}/subnetworks/sb-d-svpc-${region}`,
        numInstances: numInstances,
    });

    // ====================================================================
    // Peering Compute Instance
    // ====================================================================
    const peeringProjectId = projectRef.getOutput("peering_project_id") as pulumi.Output<string>;
    const peeringSubnet = projectRef.getOutput("peering_subnetwork_self_link") as pulumi.Output<string>;
    const iapFirewallTags = projectRef.getOutput("iap_firewall_tags") as pulumi.Output<Record<string, string>>;

    const peeringSa = new gcp.serviceaccount.Account("peering-app-sa", {
        project: peeringProjectId,
        accountId: "sa-peering-app",
        displayName: "Peering app service Account",
        createIgnoreAlreadyExists: true,
    });

    const peeringTemplate = new InstanceTemplate("peering-template", {
        projectId: peeringProjectId,
        namePrefix: "peering-app",
        machineType: machineType,
        region: region,
        sourceImageFamily: "debian-12",
        sourceImageProject: "debian-cloud",
        diskSizeGb: 100,
        diskType: "pd-ssd",
        subnetwork: peeringSubnet,
        serviceAccount: {
            email: peeringSa.email,
            scopes: ["compute-rw"],
        },
        metadata: {
            "block-project-ssh-keys": "true",
        },
    });

    const peeringInstance = new ComputeInstance("peering-instance", {
        projectId: peeringProjectId,
        zone: `${region}-a`,
        instanceName: "peering-app",
        instanceTemplate: peeringTemplate.templateSelfLink,
        subnetwork: peeringSubnet,
        numInstances: 1,
        resourceManagerTags: iapFirewallTags,
    });

    // ====================================================================
    // Confidential Space Compute
    // ====================================================================
    const confSpaceProjectId = projectRef.getOutput("confidential_space_project_id") as pulumi.Output<string>;
    const confSpaceProjectNum = projectRef.getOutput("confidential_space_project_number") as pulumi.Output<string>;
    const confSpaceSaEmail = projectRef.getOutput("confidential_space_workload_sa") as pulumi.Output<string>;
    
    const wip = new gcp.iam.WorkloadIdentityPool("d-conf-space-pool", {
        workloadIdentityPoolId: "confidential-space-pool",
        disabled: false,
        project: confSpaceProjectId,
    });

    const attestationProvider = new gcp.iam.WorkloadIdentityPoolProvider("d-attestation-verifier", {
        workloadIdentityPoolId: wip.workloadIdentityPoolId,
        workloadIdentityPoolProviderId: "attestation-verifier",
        displayName: "attestation-verifier",
        description: "OIDC provider for confidential computing attestation",
        project: confSpaceProjectId,
        oidc: {
            issuerUri: "https://confidentialcomputing.googleapis.com/",
            allowedAudiences: ["https://sts.googleapis.com"],
        },
        attributeMapping: {
            "google.subject": '"gcpcs::" + assertion.submods.container.image_digest + "::" + assertion.submods.gce.project_number + "::" + assertion.submods.gce.instance_id',
            "attribute.image_digest": "assertion.submods.container.image_digest",
        },
        attributeCondition: pulumi.interpolate`assertion.submods.container.image_digest == "sha256:0000000000000000000000000000000000000000000000000000000000000000" && "${confSpaceSaEmail}" in assertion.google_service_accounts && assertion.swname == "CONFIDENTIAL_SPACE" && "STABLE" in assertion.submods.confidential_space.support_attributes`,
    });

    // Workload identity binding for the service account
    new gcp.serviceaccount.IAMMember("d-workload-identity-binding", {
        serviceAccountId: pulumi.interpolate`projects/${confSpaceProjectId}/serviceAccounts/${confSpaceSaEmail}`,
        role: "roles/iam.workloadIdentityUser",
        member: pulumi.interpolate`principalSet://iam.googleapis.com/projects/${confSpaceProjectNum}/locations/global/workloadIdentityPools/${wip.workloadIdentityPoolId}/*`,
    });

    const confTemplate = new InstanceTemplate("d-confidential-template", {
        projectId: confSpaceProjectId,
        namePrefix: "conf-space-app",
        machineType: "n2d-standard-2",
        region: region,
        sourceImageFamily: "confidential-space",
        sourceImageProject: "confidential-space-images",
        diskSizeGb: 20,
        diskType: "pd-ssd",
        subnetwork: `projects/${config.get("shared_vpc_host_project") || ""}/regions/${region}/subnetworks/sb-d-svpc-${region}`,
        enableConfidentialVm: true,
        metadata: {
            "tee-image-reference": `${region}-docker.pkg.dev/fake-project/tf-runners/confidential_space_image:latest`,
        },
        serviceAccount: {
            email: confSpaceSaEmail,
            scopes: ["cloud-platform"],
        },
    });

    const confInstance = new ComputeInstance("d-confidential-instance", {
        projectId: confSpaceProjectId,
        zone: `${region}-a`,
        instanceName: "conf-space-instance",
        instanceTemplate: confTemplate.templateSelfLink,
        subnetwork: `projects/${config.get("shared_vpc_host_project") || ""}/regions/${region}/subnetworks/sb-d-svpc-${region}`,
        numInstances: 1,
    });

    return {
        // Standard compute instance outputs
        project_id: projectId,
        region: region,
        instances_self_links: pulumi.all(instance.instances.map(i => i.selfLink)),
        instances_names: pulumi.all(instance.instances.map(i => i.name)),
        instances_zones: pulumi.all(instance.instances.map(i => i.zone)),
        instances_details: pulumi.all(instance.instances.map(i => pulumi.all([i.name, i.zone, i.selfLink]).apply(([name, zone, selfLink]) => ({ name, zone, selfLink })))),

        // Peering instances outputs
        peering_instances_self_links: pulumi.all(peeringInstance.instances.map(i => i.selfLink)),
        peering_instances_names: pulumi.all(peeringInstance.instances.map(i => i.name)),
        peering_instances_zones: pulumi.all(peeringInstance.instances.map(i => i.zone)),

        // Confidential Space outputs
        confidential_space_project_id: confSpaceProjectId,
        confidential_space_project_number: confSpaceProjectNum,
        workload_identity_pool_id: wip.workloadIdentityPoolId,
        workload_pool_provider_id: attestationProvider.workloadIdentityPoolProviderId,
        confidential_instances_self_links: pulumi.all(confInstance.instances.map(i => i.selfLink)),
        confidential_instances_names: pulumi.all(confInstance.instances.map(i => i.name)),
        confidential_instances_zones: pulumi.all(confInstance.instances.map(i => i.zone)),
        available_zones: [pulumi.interpolate`${region}-a`],
        confidential_available_zones: [pulumi.interpolate`${region}-a`],
    };
};
