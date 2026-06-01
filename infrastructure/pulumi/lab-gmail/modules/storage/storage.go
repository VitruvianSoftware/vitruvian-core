// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package storage

import (
	"github.com/pulumi/pulumi-gcp/sdk/v7/go/gcp/storage"
	"github.com/pulumi/pulumi-random/sdk/v4/go/random"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// CreateBucketArgs defines the arguments for creating a storage bucket.
type CreateBucketArgs struct {
	ProjectID string
	NamePrefix string
	Location  string
}

// CreateBucket creates a new Google Cloud Storage bucket.
func CreateBucket(ctx *pulumi.Context, name string, args *CreateBucketArgs) (*storage.Bucket, error) {
	// Generate a random suffix for the bucket name to ensure global uniqueness.
	bktSuffix, err := random.NewRandomString(ctx, name+"-suffix", &random.RandomStringArgs{
		Length:  pulumi.Int(4),
		Special: pulumi.Bool(false),
		Upper:   pulumi.Bool(false),
		Numeric: pulumi.Bool(true),
		Lower:   pulumi.Bool(true),
		OverrideSpecial: pulumi.String(""), // No special characters for bucket names
	})
	if err != nil {
		return nil, err
	}

	bucketName := pulumi.Sprintf("%s-%s", args.NamePrefix, bktSuffix.Result)

	bucket, err := storage.NewBucket(ctx, name, &storage.BucketArgs{
		Project:  pulumi.String(args.ProjectID),
		Name:     bucketName,
		Location: pulumi.String(args.Location),
	})
	if err != nil {
		return nil, err
	}

	ctx.Export(name+"Name", bucket.Name)

	return bucket, nil
}
