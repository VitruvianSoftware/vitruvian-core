/**
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * GitHub Actions CI/CD Infrastructure — mirrors Go's build_github_actions.go
 * and Go's projects.go (deployCICDProject).
 *
 * Split into two phases matching Go's architecture:
 *   Phase 1: deployCICDProject — creates the CI/CD project, APIs, Artifact Registry, private pool
 *   Phase 2: deployGitHubActionsWIF — creates WIF pool/provider/bindings and GitHub secrets
 *
 * This is the default CI/CD approach for the Pulumi foundation.
 * Cloud Build is available as build_cb.ts.example.
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import * as random from "@pulumi/random";
import * as github from "@pulumi/github";
import { BootstrapConfig } from "./config";
import { GranularSAs } from "./sa";
import { CbPrivatePool } from "@vitruviansoftware/foundation-cb-private-pool";

export interface CICDProjectOutputs {
    cicdProjectId: pulumi.Output<string>;
    privateWorkerPoolId: pulumi.Output<string>;
}

export interface WIFOutputs {
    wifPoolName: pulumi.Output<string>;
    wifProviderName: pulumi.Output<string>;
}

/**
 * Phase 1: Deploy the CI/CD project.
 * Mirrors Go's deployCICDProject in projects.go.
 */
export async function deployCICDProject(
    cfg: BootstrapConfig,
    bootstrapFolder: gcp.organizations.Folder,
): Promise<CICDProjectOutputs> {

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

    // Disable default service accounts on CI/CD project
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

    // Artifact Registry for terraform builder images
    new gcp.artifactregistry.Repository("tf-runners", {
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

/**
 * Phase 2: Deploy GitHub Actions WIF.
 * Mirrors Go's deployGitHubActionsBuild in build_github_actions.go.
 * Called AFTER service accounts exist.
 */
export async function deployGitHubActionsWIF(
    cfg: BootstrapConfig,
    cicdProjectId: pulumi.Output<string>,
    stateBucketName: pulumi.Output<string>,
    projectsStateBucketName: pulumi.Output<string>,
    saOutputs: GranularSAs,
): Promise<WIFOutputs> {

    let wifPoolName = pulumi.output("");
    let wifProviderName = pulumi.output("");

    // If github_owner is not set, skip WIF provisioning.
    // The user can still use key-based auth (GOOGLE_CREDENTIALS).
    if (!cfg.githubOwner) {
        return { wifPoolName, wifProviderName };
    }

    const attributeCondition = cfg.attributeCondition
        || `assertion.repository_owner=='${cfg.githubOwner}'`;

    const stageRepos: Record<string, string> = {
        bootstrap: cfg.githubRepoBootstrap || "",
        org: cfg.githubRepoOrg || "",
        env: cfg.githubRepoEnv || "",
        net: cfg.githubRepoNet || "",
        proj: cfg.githubRepoProj || "",
    };

    const wifPool = new gcp.iam.WorkloadIdentityPool("foundation-wif-pool", {
        workloadIdentityPoolId: "foundation-pool",
        project: cicdProjectId,
        description: "GitHub Actions WIF pool",
    });

    const wifProvider = new gcp.iam.WorkloadIdentityPoolProvider("foundation-gh-provider", {
        workloadIdentityPoolId: wifPool.workloadIdentityPoolId,
        workloadIdentityPoolProviderId: "foundation-gh-provider",
        project: cicdProjectId,
        attributeMapping: {
            "google.subject": "assertion.sub",
            "attribute.actor": "assertion.actor",
            "attribute.repository": "assertion.repository",
            "attribute.repository_owner": "assertion.repository_owner",
        },
        attributeCondition: attributeCondition,
        oidc: {
            issuerUri: "https://token.actions.githubusercontent.com",
        },
    });

    for (const [key, sa] of Object.entries(saOutputs.serviceAccounts)) {
        const repo = stageRepos[key] || "";
        const attr = (repo === "" || repo === "*")
            ? `attribute.repository/${cfg.githubOwner}`
            : `attribute.repository/${cfg.githubOwner}/${repo}`;

        new gcp.serviceaccount.IAMMember(`gh-oidc-binding-${key}`, {
            serviceAccountId: sa.name,
            role: "roles/iam.workloadIdentityUser",
            member: pulumi.interpolate`principalSet://iam.googleapis.com/${wifPool.name}/${attr}`,
        });
    }

    wifPoolName = wifPool.name;
    wifProviderName = wifProvider.name;

    // ====================================================================
    // GitHub Actions Secrets
    // Automatically provision secrets in each stage repo so the pipeline
    // templates work out of the box with zero manual setup.
    // Mirrors: github_actions_secret "secrets" in build_github.tf.example
    //
    // Secrets created per repo:
    //   WIF_PROVIDER_NAME     — full WIF provider resource name for auth
    //   SERVICE_ACCOUNT_EMAIL — per-stage SA email for impersonation
    //   PROJECT_ID            — CI/CD project ID
    //   PULUMI_BACKEND_URL    — Backend GCS bucket URL
    // ====================================================================
    for (const [key, sa] of Object.entries(saOutputs.serviceAccounts)) {
        const repo = stageRepos[key];
        if (!repo || repo === "*") continue;

        // Determine the appropriate state bucket for the stage
        const backendBucket = key === "proj" ? projectsStateBucketName : stateBucketName;
        const backendURL = backendBucket.apply(name => `gs://${name}`);

        // WIF_PROVIDER_NAME
        new github.ActionsSecret(`gh-secret-${key}-wif-provider`, {
            repository: repo,
            secretName: "WIF_PROVIDER_NAME",
            plaintextValue: wifProvider.name,
        });

        // SERVICE_ACCOUNT_EMAIL
        new github.ActionsSecret(`gh-secret-${key}-sa-email`, {
            repository: repo,
            secretName: "SERVICE_ACCOUNT_EMAIL",
            plaintextValue: sa.email,
        });

        // PROJECT_ID
        new github.ActionsSecret(`gh-secret-${key}-project-id`, {
            repository: repo,
            secretName: "PROJECT_ID",
            plaintextValue: cicdProjectId,
        });

        // PULUMI_BACKEND_URL
        new github.ActionsSecret(`gh-secret-${key}-backend`, {
            repository: repo,
            secretName: "PULUMI_BACKEND_URL",
            plaintextValue: backendURL,
        });
    }

    return { wifPoolName, wifProviderName };
}
