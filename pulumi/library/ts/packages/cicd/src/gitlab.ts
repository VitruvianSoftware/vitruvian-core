import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface SAMappingEntry {
  saName: pulumi.Input<string>;
  attribute: string;
}

export interface GitLabOIDCArgs {
  projectId: pulumi.Input<string>;
  poolId: pulumi.Input<string>;
  providerId: pulumi.Input<string>;
  attributeCondition: pulumi.Input<string>;
  saMapping: Record<string, SAMappingEntry>;
  issuerUri?: pulumi.Input<string>;
}

export class GitLabOIDC extends pulumi.ComponentResource {
  public readonly pool: gcp.iam.WorkloadIdentityPool;
  public readonly provider: gcp.iam.WorkloadIdentityPoolProvider;
  public readonly bindings: gcp.serviceaccount.IAMMember[] = [];

  constructor(
    name: string,
    args: GitLabOIDCArgs,
    opts?: pulumi.ComponentResourceOptions,
  ) {
    super("pkg:cicd:GitLabOIDC", name, args, opts);

    this.pool = new gcp.iam.WorkloadIdentityPool(
      `${name}-pool`,
      {
        project: args.projectId,
        workloadIdentityPoolId: args.poolId,
        disabled: false,
      },
      { parent: this },
    );

    this.provider = new gcp.iam.WorkloadIdentityPoolProvider(
      `${name}-provider`,
      {
        project: args.projectId,
        workloadIdentityPoolId: this.pool.workloadIdentityPoolId,
        workloadIdentityPoolProviderId: args.providerId,
        attributeCondition: args.attributeCondition,
        attributeMapping: {
          "google.subject": "assertion.sub",
          "attribute.sub": "assertion.sub",
          "attribute.iss": "assertion.iss",
          "attribute.aud": "assertion.aud",
          "attribute.exp": "assertion.exp",
          "attribute.nbf": "assertion.nbf",
          "attribute.iat": "assertion.iat",
          "attribute.jti": "assertion.jti",
          "attribute.namespace_id": "assertion.namespace_id",
          "attribute.namespace_path": "assertion.namespace_path",
          "attribute.project_id": "assertion.project_id",
          "attribute.project_path": "assertion.project_path",
          "attribute.user_id": "assertion.user_id",
          "attribute.user_login": "assertion.user_login",
          "attribute.user_email": "assertion.user_email",
        },
        oidc: {
          issuerUri: args.issuerUri ?? "https://gitlab.com",
        },
      },
      { parent: this.pool },
    );

    for (const [key, entry] of Object.entries(args.saMapping)) {
      const member = pulumi.interpolate`principalSet://iam.googleapis.com/${this.pool.name}/${entry.attribute}`;
      this.bindings.push(
        new gcp.serviceaccount.IAMMember(
          `${name}-binding-${key}`,
          {
            serviceAccountId: entry.saName,
            role: "roles/iam.workloadIdentityUser",
            member: member,
          },
          { parent: this.provider },
        ),
      );
    }

    this.registerOutputs({
      poolName: this.pool.name,
      providerName: this.provider.name,
    });
  }
}
