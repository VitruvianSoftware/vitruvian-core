import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export type CloudBuildSourceType = "CSR" | "GITHUB" | "GITLAB";

export interface CloudBuildTriggerConfig {
    repoOwner: string;
    repoName: string;
    serviceAccount: string;
    planFilename?: string;
    applyFilename?: string;
    applyBranchPattern?: string;
}

export interface CloudBuildArgs {
    projectId: pulumi.Input<string>;
    region: pulumi.Input<string>;
    sourceType?: CloudBuildSourceType;
    sourceRepos?: string[];
    artifactRegistryId?: string;
    triggers: Record<string, CloudBuildTriggerConfig>;
    artifactRegistryReaders: pulumi.Input<string>[];
}

export class CloudBuild extends pulumi.ComponentResource {
    public readonly sourceRepos: Record<string, gcp.sourcerepo.Repository> = {};
    public readonly artifactRegistry: gcp.artifactregistry.Repository;
    public readonly planTriggers: Record<string, gcp.cloudbuild.Trigger> = {};
    public readonly applyTriggers: Record<string, gcp.cloudbuild.Trigger> = {};

    constructor(name: string, args: CloudBuildArgs, opts?: pulumi.ComponentResourceOptions) {
        super("pkg:cicd:CloudBuild", name, args, opts);

        const sourceType = args.sourceType ?? "GITHUB";

        // 1. CSR
        if (sourceType === "CSR") {
            for (const repoName of args.sourceRepos ?? []) {
                this.sourceRepos[repoName] = new gcp.sourcerepo.Repository(`${name}-csr-${repoName}`, {
                    project: args.projectId,
                    name: repoName,
                }, { parent: this });
            }
        }

        // 2. Artifact Registry
        const arId = args.artifactRegistryId ?? "pulumi-builders";
        this.artifactRegistry = new gcp.artifactregistry.Repository(`${name}-ar`, {
            project: args.projectId,
            repositoryId: arId,
            location: args.region,
            format: "DOCKER",
            description: "Builder images for Cloud Build pipelines. Managed by Pulumi.",
        }, { parent: this });

        let i = 0;
        for (const member of args.artifactRegistryReaders) {
            new gcp.artifactregistry.RepositoryIamMember(`${name}-ar-reader-${i++}`, {
                project: args.projectId,
                location: args.region,
                repository: this.artifactRegistry.repositoryId,
                role: "roles/artifactregistry.reader",
                member: member,
            }, { parent: this.artifactRegistry });
        }

        // 3. Triggers
        for (const [key, cfg] of Object.entries(args.triggers)) {
            const planFilename = cfg.planFilename ?? "cloudbuild-pulumi-plan.yaml";
            const applyFilename = cfg.applyFilename ?? "cloudbuild-pulumi-apply.yaml";
            const applyBranch = cfg.applyBranchPattern ?? "^main$";

            let planArgs: gcp.cloudbuild.TriggerArgs = {
                project: args.projectId,
                name: `plan-${key}`,
                description: `Pulumi preview for ${key} stage. Managed by Pulumi.`,
                filename: planFilename,
                location: args.region,
                serviceAccount: cfg.serviceAccount,
            };

            let applyArgs: gcp.cloudbuild.TriggerArgs = {
                project: args.projectId,
                name: `apply-${key}`,
                description: `Pulumi up for ${key} stage. Managed by Pulumi.`,
                filename: applyFilename,
                location: args.region,
                serviceAccount: cfg.serviceAccount,
            };

            if (sourceType === "GITHUB") {
                planArgs.github = {
                    owner: cfg.repoOwner,
                    name: cfg.repoName,
                    push: { branch: ".*" }
                };
                applyArgs.github = {
                    owner: cfg.repoOwner,
                    name: cfg.repoName,
                    push: { branch: applyBranch }
                };
            } else if (sourceType === "GITLAB") {
                const gitlabURI = `https://gitlab.com/${cfg.repoOwner}/${cfg.repoName}`;
                planArgs.sourceToBuild = {
                    uri: gitlabURI,
                    ref: "refs/heads/main",
                    repoType: "GITLAB"
                };
                planArgs.gitFileSource = {
                    path: planFilename,
                    uri: gitlabURI,
                    revision: "refs/heads/main",
                    repoType: "GITLAB"
                };
                applyArgs.sourceToBuild = {
                    uri: gitlabURI,
                    ref: "refs/heads/main",
                    repoType: "GITLAB"
                };
                applyArgs.gitFileSource = {
                    path: applyFilename,
                    uri: gitlabURI,
                    revision: "refs/heads/main",
                    repoType: "GITLAB"
                };
            } else { // CSR
                planArgs.triggerTemplate = {
                    projectId: args.projectId,
                    repoName: cfg.repoName,
                    branchName: ".*"
                };
                applyArgs.triggerTemplate = {
                    projectId: args.projectId,
                    repoName: cfg.repoName,
                    branchName: applyBranch
                };
            }

            this.planTriggers[key] = new gcp.cloudbuild.Trigger(`${name}-plan-${key}`, planArgs, { parent: this });
            this.applyTriggers[key] = new gcp.cloudbuild.Trigger(`${name}-apply-${key}`, applyArgs, { parent: this });
        }

        this.registerOutputs({
            artifactRegistryName: this.artifactRegistry.name,
        });
    }
}
