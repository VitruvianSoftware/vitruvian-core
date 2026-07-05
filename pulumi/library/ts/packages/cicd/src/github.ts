import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { SAMappingEntry } from "./gitlab"; // Reuse the interface

export interface GitHubOIDCArgs {
    projectId: pulumi.Input<string>;
    poolId: pulumi.Input<string>;
    providerId: pulumi.Input<string>;
    attributeCondition: pulumi.Input<string>;
    saMapping: Record<string, SAMappingEntry>;
    issuerUri?: pulumi.Input<string>;
}

export class GitHubOIDC extends pulumi.ComponentResource {
    public readonly pool: gcp.iam.WorkloadIdentityPool;
    public readonly provider: gcp.iam.WorkloadIdentityPoolProvider;
    public readonly bindings: gcp.serviceaccount.IAMMember[] = [];

    constructor(name: string, args: GitHubOIDCArgs, opts?: pulumi.ComponentResourceOptions) {
        super("pkg:cicd:GitHubOIDC", name, args, opts);

        this.pool = new gcp.iam.WorkloadIdentityPool(`${name}-pool`, {
            project: args.projectId,
            workloadIdentityPoolId: args.poolId,
            disabled: false,
        }, { parent: this });

        this.provider = new gcp.iam.WorkloadIdentityPoolProvider(`${name}-provider`, {
            project: args.projectId,
            workloadIdentityPoolId: this.pool.workloadIdentityPoolId,
            workloadIdentityPoolProviderId: args.providerId,
            attributeCondition: args.attributeCondition,
            attributeMapping: {
                "google.subject": "assertion.sub",
                "attribute.actor": "assertion.actor",
                "attribute.aud": "assertion.aud",
                "attribute.repository": "assertion.repository",
            },
            oidc: {
                issuerUri: args.issuerUri ?? "https://token.actions.githubusercontent.com",
            },
        }, { parent: this.pool });

        for (const [key, entry] of Object.entries(args.saMapping)) {
            const member = pulumi.interpolate`principalSet://iam.googleapis.com/${this.pool.name}/${entry.attribute}`;
            this.bindings.push(new gcp.serviceaccount.IAMMember(`${name}-binding-${key}`, {
                serviceAccountId: entry.saName,
                role: "roles/iam.workloadIdentityUser",
                member: member,
            }, { parent: this.provider }));
        }

        this.registerOutputs({
            poolName: this.pool.name,
            providerName: this.provider.name,
        });
    }
}
