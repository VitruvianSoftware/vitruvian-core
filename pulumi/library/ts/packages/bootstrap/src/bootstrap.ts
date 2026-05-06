import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import * as random from "@pulumi/random";
import { ProjectFactory } from "@vitruviansoftware/foundation-project-factory";

export interface BootstrapArgs {
  orgId: string;
  folderId?: pulumi.Input<string>;
  billingAccount: string;
  projectPrefix: string;
  defaultRegion: string;
  defaultRegionKms?: string;
  defaultRegionGcs?: string;
  projectLabels?: pulumi.Input<Record<string, string>>;
  activateApis?: string[];
  randomSuffix?: boolean;
  deletionPolicy?: string;
  defaultServiceAccount?: string;

  // State Bucket
  bucketPrefix?: string;
  stateBucketName?: string;
  bucketForceDestroy?: boolean;
  bucketLabels?: pulumi.Input<Record<string, string>>;

  // KMS
  encryptStateBucket?: boolean;
  keyRotationPeriod?: string;
  keyProtectionLevel?: string;
  kmsPreventDestroy?: boolean;

  stateBucketIamMembers?: pulumi.Input<string>[];
}

export class Bootstrap extends pulumi.ComponentResource {
  public readonly seedProject: ProjectFactory;
  public readonly seedProjectId: pulumi.Output<string>;
  public readonly stateBucketName: pulumi.Output<string>;
  public readonly kmsKeyId?: pulumi.Output<string>;
  public readonly kmsKeyRingId?: pulumi.Output<string>;

  constructor(name: string, args: BootstrapArgs, opts?: pulumi.ComponentResourceOptions) {
    super("pkg:index:Bootstrap", name, args, opts);

    const deletionPolicy = args.deletionPolicy ?? "PREVENT";
    const defaultSA = args.defaultServiceAccount ?? "disable";
    const encryptBucket = args.encryptStateBucket ?? true;
    const keyRotation = args.keyRotationPeriod ?? "7776000s"; // 90 days
    const keyProtection = args.keyProtectionLevel ?? "SOFTWARE";
    const kmsPreventDestroy = args.kmsPreventDestroy ?? true;
    const kmsRegion = args.defaultRegionKms ?? args.defaultRegion;
    const gcsRegion = args.defaultRegionGcs ?? args.defaultRegion;

    let activateApis = args.activateApis ?? [];
    if (encryptBucket && !activateApis.includes("cloudkms.googleapis.com")) {
      activateApis.push("cloudkms.googleapis.com");
    }

    // 1. Seed Project
    this.seedProject = new ProjectFactory(`${name}-seed`, {
      name: `${args.projectPrefix}-b-seed`,
      orgId: args.orgId,
      folderId: args.folderId ?? "",
      billingAccount: args.billingAccount,
      randomProjectId: args.randomSuffix ?? false,
      deletionPolicy: deletionPolicy,
      labels: args.projectLabels as Record<string, string>,
      activateApis: activateApis,
      defaultServiceAccount: defaultSA,
    }, { parent: this });

    this.seedProjectId = this.seedProject.projectId;

    new gcp.resourcemanager.Lien(`${name}-seed-lien`, {
      origin: "bootstrap",
      parent: pulumi.interpolate`projects/${this.seedProject.projectNumber}`,
      reason: "Bootstrap seed project is protected",
      restrictions: ["resourcemanager.projects.delete"],
    }, { parent: this });

    // 2. Org Policy
    new gcp.projects.OrganizationPolicy(`${name}-cross-project-sa`, {
      project: this.seedProjectId,
      constraint: "iam.disableCrossProjectServiceAccountUsage",
      booleanPolicy: {
        enforced: false,
      },
    }, { parent: this });

    // 3. KMS Key Ring + Crypto Key
    let cryptoKeyId: pulumi.Output<string> | undefined;
    let kmsBinding: gcp.kms.CryptoKeyIAMMember | undefined;

    if (encryptBucket) {
      const keyRing = new gcp.kms.KeyRing(`${name}-keyring`, {
        project: this.seedProjectId,
        name: `${args.projectPrefix}-keyring`,
        location: kmsRegion,
      }, { parent: this, protect: kmsPreventDestroy });

      this.kmsKeyRingId = keyRing.id;

      const cryptoKey = new gcp.kms.CryptoKey(`${name}-key`, {
        name: `${args.projectPrefix}-key`,
        keyRing: keyRing.id,
        rotationPeriod: keyRotation,
        versionTemplate: {
          protectionLevel: keyProtection,
          algorithm: "GOOGLE_SYMMETRIC_ENCRYPTION",
        },
      }, { parent: this, protect: kmsPreventDestroy });

      cryptoKeyId = cryptoKey.id;
      this.kmsKeyId = cryptoKeyId;

      const sa = gcp.storage.getProjectServiceAccountOutput({
        project: this.seedProjectId,
      });

      const storageSA = pulumi.interpolate`serviceAccount:${sa.emailAddress}`;

      kmsBinding = new gcp.kms.CryptoKeyIAMMember(`${name}-kms-sa`, {
        cryptoKeyId: cryptoKeyId,
        role: "roles/cloudkms.cryptoKeyEncrypterDecrypter",
        member: storageSA,
      }, { parent: this });
    }

    // 4. State Bucket
    let baseBucketName = args.stateBucketName;
    if (!baseBucketName) {
      if (args.bucketPrefix) {
        baseBucketName = `${args.bucketPrefix}-${args.projectPrefix}-b-seed-tfstate`;
      } else {
        baseBucketName = `${args.projectPrefix}-b-seed-tfstate`;
      }
    }

    let finalBucketName: pulumi.Output<string>;
    if (args.randomSuffix) {
      const suffix = new random.RandomId(`${name}-bucket-suffix`, {
        byteLength: 2,
      }, { parent: this });
      finalBucketName = pulumi.interpolate`${baseBucketName}-${suffix.hex}`;
    } else {
      finalBucketName = pulumi.output(baseBucketName);
    }

    const bucketOpts: pulumi.CustomResourceOptions = { parent: this };
    if (encryptBucket && kmsBinding) {
      bucketOpts.dependsOn = [kmsBinding];
    }

    const stateBucket = new gcp.storage.Bucket(`${name}-state-bucket`, {
      project: this.seedProjectId,
      name: finalBucketName,
      location: gcsRegion,
      uniformBucketLevelAccess: true,
      forceDestroy: args.bucketForceDestroy ?? false,
      labels: args.bucketLabels,
      versioning: {
        enabled: true,
      },
      encryption: encryptBucket && cryptoKeyId ? {
        defaultKmsKeyName: cryptoKeyId,
      } : undefined,
    }, bucketOpts);

    this.stateBucketName = stateBucket.name;

    // 5. State Bucket IAM
    if (args.stateBucketIamMembers) {
      args.stateBucketIamMembers.forEach((member, i) => {
        new gcp.storage.BucketIAMMember(`${name}-bucket-iam-${i}`, {
          bucket: stateBucket.name,
          role: "roles/storage.admin",
          member: member,
        }, { parent: this });
      });
    }

    this.registerOutputs({
      seedProjectId: this.seedProjectId,
      stateBucketName: this.stateBucketName,
    });
  }
}
