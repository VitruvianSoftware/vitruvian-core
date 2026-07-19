/*
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

package base_env

import (
	"fmt"

	libproject "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/kms"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/storage"
	"github.com/pulumi/pulumi-random/sdk/v4/go/random"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// CMEKResult holds outputs from the CMEK storage deployment.
type CMEKResult struct {
	BucketName  pulumi.StringOutput
	KeyringName pulumi.StringOutput
	// Keys is the list of crypto-key names in the keyring, surfaced so the stack
	// can export `keys` to match upstream's `output "keys" = keys(module.kms.keys)`
	// (consumed by 5-app-infra). We create a single key, so it is a one-element list.
	Keys pulumi.StringArrayOutput
}

// deployCMEKStorage creates a KMS keyring + crypto key in the env's KMS project
// and a CMEK-encrypted GCS bucket on the SVPC project, matching upstream's
// example_storage_cmek.tf.
//
// Upstream creates:
//   - a KMS keyring + rotation-period crypto key in the env KMS project (upstream
//     local.kms_project_id; here kmsProjectID, wired from 2-environments) — NOT the
//     SVPC project (the bucket, below, is what lands on the SVPC project)
//   - an IAM binding granting the GCS service account encrypter/decrypter on the key
//   - a CMEK-encrypted GCS bucket on the SVPC project
func deployCMEKStorage(
	ctx *pulumi.Context,
	args *Args,
	svpcProject *libproject.Project,
	kmsProjectID pulumi.StringOutput,
) (*CMEKResult, error) {
	projectID := svpcProject.Project.ProjectId

	// 1. KMS Keyring
	keyring, err := kms.NewKeyRing(ctx, "cmek-keyring", &kms.KeyRingArgs{
		Name:     pulumi.String(args.KeyringName),
		Location: pulumi.String(args.KMSLocation),
		Project:  kmsProjectID,
	})
	if err != nil {
		return nil, err
	}

	// 2. Crypto Key with rotation
	cryptoKey, err := kms.NewCryptoKey(ctx, "cmek-crypto-key", &kms.CryptoKeyArgs{
		Name:           pulumi.String(args.KeyName),
		KeyRing:        keyring.ID(),
		RotationPeriod: pulumi.String(args.KeyRotationPeriod),
		Purpose:        pulumi.String("ENCRYPT_DECRYPT"),
	}, pulumi.Parent(keyring))
	if err != nil {
		return nil, err
	}

	// 3. Grant the GCS service account permission to use the crypto key.
	// Look the agent up via the API (like upstream's data
	// google_storage_project_service_account) instead of hand-assembling
	// service-{number}@gs-project-accounts...: on a cold deploy the agent does not
	// exist until first use, and this provisioning lookup CREATES it — a Sprintf'd
	// email would race agent provisioning and fail the IAM grant.
	gcsSA := storage.GetProjectServiceAccountOutput(ctx, storage.GetProjectServiceAccountOutputArgs{
		Project: projectID,
	})
	gcsServiceAccount := gcsSA.EmailAddress().ApplyT(func(e string) string {
		return "serviceAccount:" + e
	}).(pulumi.StringOutput)

	gcsEncrypter, err := kms.NewCryptoKeyIAMMember(ctx, "cmek-gcs-encrypter", &kms.CryptoKeyIAMMemberArgs{
		CryptoKeyId: cryptoKey.ID(),
		Role:        pulumi.String("roles/cloudkms.cryptoKeyEncrypterDecrypter"),
		Member:      gcsServiceAccount,
	}, pulumi.Parent(cryptoKey))
	if err != nil {
		return nil, err
	}

	// 4. Random suffix for bucket name uniqueness (matches upstream random_string)
	bucketSuffix, err := random.NewRandomString(ctx, "cmek-bucket-suffix", &random.RandomStringArgs{
		Length:  pulumi.Int(5),
		Upper:   pulumi.Bool(false),
		Special: pulumi.Bool(false),
		Numeric: pulumi.Bool(true),
	})
	if err != nil {
		return nil, err
	}

	// 5. CMEK-encrypted GCS bucket
	bucketName := pulumi.All(projectID, bucketSuffix.Result).ApplyT(func(vals []interface{}) string {
		return fmt.Sprintf("%s-%s-cmek-encrypted-%s", args.GCSBucketPrefix, vals[0], vals[1])
	}).(pulumi.StringOutput)

	bucketArgs := &storage.BucketArgs{
		Project:                  projectID,
		Name:                     bucketName,
		Location:                 pulumi.String(args.GCSLocation),
		UniformBucketLevelAccess: pulumi.Bool(true),
		Encryption: &storage.BucketEncryptionArgs{
			DefaultKmsKeyName: cryptoKey.ID(),
		},
	}

	// Custom placement config for dual-region buckets (matches upstream)
	if len(args.GCSPlacementRegions) == 2 {
		bucketArgs.CustomPlacementConfig = &storage.BucketCustomPlacementConfigArgs{
			DataLocations: pulumi.ToStringArray(args.GCSPlacementRegions),
		}
	}

	// The bucket must wait for (a) the key, (b) the GCS-agent encrypter grant —
	// creating a CMEK bucket before the agent can use the key fails — and (c) the
	// SVPC project's API-propagation gate (storage API freshly enabled on cold
	// deploy).
	bucket, err := storage.NewBucket(ctx, "cmek-bucket", bucketArgs,
		pulumi.DependsOn([]pulumi.Resource{cryptoKey, gcsEncrypter, svpcProject.ApisReady}))
	if err != nil {
		return nil, err
	}

	return &CMEKResult{
		BucketName:  bucket.Name,
		KeyringName: keyring.Name,
		// One crypto key → the `keys` export is [keyName]. Mirrors upstream
		// `keys(module.kms.keys)`. Derived from the created key's Name output so it
		// stays correct if the key set grows.
		Keys: cryptoKey.Name.ApplyT(func(n string) []string {
			return []string{n}
		}).(pulumi.StringArrayOutput),
	}, nil
}
