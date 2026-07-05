/**
 * KMS Module
 * Mirrors: terraform-google-modules/kms/google
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface KmsArgs {
    projectId: pulumi.Input<string>;
    location: string;
    keyringName: string;
    keys: string[];
    preventDestroy?: boolean;
    keyRotationPeriod?: string;
    keyAlgorithm?: string;
    keyProtectionLevel?: string;
}

export class Kms extends pulumi.ComponentResource {
    public readonly keyring: gcp.kms.KeyRing;
    public readonly keys: Record<string, gcp.kms.CryptoKey>;

    constructor(name: string, args: KmsArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:Kms", name, args, opts);

        this.keyring = new gcp.kms.KeyRing(`${name}-keyring`, {
            name: args.keyringName,
            project: args.projectId,
            location: args.location,
        }, { parent: this });

        this.keys = {};
        for (const keyName of args.keys) {
            this.keys[keyName] = new gcp.kms.CryptoKey(`${name}-key-${keyName}`, {
                name: keyName,
                keyRing: this.keyring.id,
                rotationPeriod: args.keyRotationPeriod ?? "7776000s", // 90 days
                versionTemplate: {
                    algorithm: args.keyAlgorithm ?? "GOOGLE_SYMMETRIC_ENCRYPTION",
                    protectionLevel: args.keyProtectionLevel ?? "SOFTWARE",
                },
            }, { parent: this, protect: args.preventDestroy ?? true });
        }

        this.registerOutputs({
            keyringId: this.keyring.id,
        });
    }
}
