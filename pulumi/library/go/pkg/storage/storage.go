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

// Package storage provides reusable Cloud Storage components, mirroring the
// terraform-google-modules/cloud-storage/google module suite.
//
// SimpleBucket corresponds to the //modules/simple_bucket submodule and
// creates a GCS bucket with foundation-grade defaults (uniform bucket-level
// access, public access prevention, optional KMS encryption).
package storage

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/storage"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// SimpleBucketArgs configures a basic Cloud Storage bucket, matching the
// terraform-google-modules/cloud-storage/google//modules/simple_bucket module.
type SimpleBucketArgs struct {
	// Name is the globally unique bucket name.
	Name pulumi.StringInput
	// ProjectID is the GCP project to create the bucket in.
	ProjectID pulumi.StringInput
	// Location is the GCS location (region or multi-region).
	Location pulumi.StringInput
	// ForceDestroy allows bucket deletion even when non-empty.
	ForceDestroy pulumi.BoolInput
	// Encryption configures optional KMS encryption for the bucket.
	Encryption *storage.BucketEncryptionArgs
	// Versioning enables object versioning on the bucket.
	Versioning *bool
	// Labels are key-value labels applied to the bucket.
	Labels pulumi.StringMapInput
}

// SimpleBucket represents a Cloud Storage bucket with standard defaults.
type SimpleBucket struct {
	pulumi.ResourceState
	Bucket *storage.Bucket
}

// NewSimpleBucket creates a new SimpleBucket component resource.
func NewSimpleBucket(ctx *pulumi.Context, name string, args *SimpleBucketArgs, opts ...pulumi.ResourceOption) (*SimpleBucket, error) {
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}
	component := &SimpleBucket{}
	err := ctx.RegisterComponentResource("pkg:storage:SimpleBucket", name, component, opts...)
	if err != nil {
		return nil, err
	}

	bucketArgs := &storage.BucketArgs{
		Name:                     args.Name,
		Project:                  args.ProjectID,
		Location:                 args.Location,
		ForceDestroy:             args.ForceDestroy,
		UniformBucketLevelAccess: pulumi.Bool(true),
		PublicAccessPrevention:   pulumi.String("enforced"),
		Labels:                   args.Labels,
	}

	if args.Encryption != nil {
		bucketArgs.Encryption = args.Encryption
	}

	// Default versioning to false if not specified, matching TF simple_bucket
	if args.Versioning != nil && *args.Versioning {
		bucketArgs.Versioning = &storage.BucketVersioningArgs{
			Enabled: pulumi.Bool(true),
		}
	}

	bucket, err := storage.NewBucket(ctx, name+"-bucket", bucketArgs, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}

	component.Bucket = bucket

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"name": bucket.Name,
		"url":  bucket.Url,
	})

	return component, nil
}
