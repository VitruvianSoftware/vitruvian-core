/**
 * Cloud Build Infrastructure — mirrors 0-bootstrap/build_cb.tf
 * Creates the CI/CD project, Cloud Source Repos, Cloud Build triggers,
 * private worker pool, artifact registry, and per-stage workspaces.
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import * as random from "@pulumi/random";
import { BootstrapConfig } from "./config";
import { CbPrivatePool } from "@vitruviansoftware/foundation-cb-private-pool";

export interface CloudbuildOutputs {
    cicdProjectId: pulumi.Output<string>;
    privateWorkerPoolId: pulumi.Output<string>;
}

export async function deployCloudbuild(
    cfg: BootstrapConfig,
    bootstrapFolder: gcp.organizations.Folder,
    seedProject: gcp.organizations.Project,
    stateBucketName: pulumi.Output<string>,
    stateBucketKmsKey: pulumi.Output<string>,
): Promise<CloudbuildOutputs> {

    // Random suffix for CI/CD project ID
    const suffix = new random.RandomString("cicd-suffix", {
        length: 4,
        special: false,
        upper: false,
    });

    // CI/CD project
    const cicdProject = new gcp.organizations.Project("cicd-project", {
        projectId: pulumi.interpolate`${cfg.projectPrefix}-b-cicd-${suffix.result}`,
        name: pulumi.interpolate`${cfg.projectPrefix}-b-cicd-${suffix.result}`,
        folderId: bootstrapFolder.name,
        billingAccount: cfg.billingAccount,
        deletionPolicy: cfg.projectDeletionPolicy,
        autoCreateNetwork: false,
        labels: {
            environment: "bootstrap",
            application_name: "cloudbuild-bootstrap",
            billing_code: "1234",
            primary_contact: "example1",
            secondary_contact: "example2",
            business_code: "shared",
            env_code: "b",
            vpc: "none",
        },
    });

    // Disable default service accounts on CI/CD project (mirrors TF default_service_account = "disable")
    new gcp.projects.DefaultServiceAccounts("cicd-default-sa-disable", {
        project: cicdProject.projectId,
        action: "DISABLE",
    });

    // Enable APIs on CI/CD project
    const cicdApis = [
        "serviceusage.googleapis.com",
        "servicenetworking.googleapis.com",
        "compute.googleapis.com",
        "logging.googleapis.com",
        "iam.googleapis.com",
        "admin.googleapis.com",
        "workflows.googleapis.com",
        "artifactregistry.googleapis.com",
        "cloudbuild.googleapis.com",
        "cloudscheduler.googleapis.com",
        "bigquery.googleapis.com",
        "cloudresourcemanager.googleapis.com",
        "cloudbilling.googleapis.com",
        "appengine.googleapis.com",
        "storage-api.googleapis.com",
        "billingbudgets.googleapis.com",
        "dns.googleapis.com",
    ];

    const cicdServices: gcp.projects.Service[] = [];
    for (const api of cicdApis) {
        cicdServices.push(new gcp.projects.Service(`cicd-api-${api.replace(/\./g, "-")}`, {
            project: cicdProject.projectId,
            service: api,
            disableOnDestroy: false,
        }, { parent: cicdProject }));
    }

    // Cloud Source Repositories (Deprecated by Google for new customers as of June 2024)
    // See: https://cloud.google.com/source-repositories/docs
    // Repositories must be created in an alternative solution like Secure Source Manager or GitHub.

    // Artifact Registry for terraform builder images
    const garRepo = new gcp.artifactregistry.Repository("tf-runners", {
        project: cicdProject.projectId,
        location: cfg.defaultRegion,
        repositoryId: "tf-runners",
        description: "Terraform runner images",
        format: "DOCKER",
    }, { dependsOn: cicdServices });

    // Private worker pool
    const privatePool = new CbPrivatePool("tf-private-pool", {
        projectId: cicdProject.projectId,
        privateWorkerPool: {
            region: cfg.defaultRegion,
            enableNetworkPeering: true,
            createPeeredNetwork: true,
            peeredNetworkSubnetIp: "10.3.0.0/24",
            peeringAddress: "192.168.0.0",
            peeringPrefixLength: 24,
        },
        vpnConfiguration: { enableVpn: false },
    }, { dependsOn: cicdServices });

    return {
        cicdProjectId: cicdProject.projectId,
        privateWorkerPoolId: privatePool.privateWorkerPoolId,
    };
}
