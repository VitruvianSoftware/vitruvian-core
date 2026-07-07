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

package main

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/tags"
	"github.com/pulumi/pulumi-random/sdk/v4/go/random"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// deployTags creates org-level tag keys and values for environment
// classification, and binds them to the common, network, and bootstrap folders.
// Tags enable fine-grained IAM conditions and resource organization across
// the foundation hierarchy.
// This mirrors the Terraform foundation's tags.tf.
//
// When CreateUniqueTagKey is true (recommended for parent folder deployments),
// a random suffix is appended to tag key names to avoid org-wide conflicts.
func deployTags(ctx *pulumi.Context, cfg *OrgConfig, folders *Folders, bootstrapRef *pulumi.StackReference) (pulumi.MapOutput, error) {
	// Tag keys are always created at the organization level, even when
	// deploying under a parent_folder. Matches upstream tags.tf which uses
	// "organizations/${local.org_id}" unconditionally.
	parent := "organizations/" + cfg.OrgID

	// Optional random suffix for unique tag keys (H14 / create_unique_tag_key)
	var keySuffix pulumi.StringInput = pulumi.String("environment")
	if cfg.CreateUniqueTagKey {
		suffix, err := random.NewRandomString(ctx, "tag-key-suffix", &random.RandomStringArgs{
			Length:  pulumi.Int(8),
			Special: pulumi.Bool(false),
			Upper:   pulumi.Bool(false),
		})
		if err != nil {
			return pulumi.MapOutput{}, err
		}
		keySuffix = suffix.Result.ApplyT(func(s string) string {
			return fmt.Sprintf("environment-%s", s)
		}).(pulumi.StringOutput)
	}

	// Environment tag key
	envTagKey, err := tags.NewTagKey(ctx, "environment-tag", &tags.TagKeyArgs{
		Parent:      pulumi.String(parent),
		ShortName:   keySuffix,
		Description: pulumi.String("Environment classification for foundation resources"),
	})
	if err != nil {
		return pulumi.MapOutput{}, err
	}

	// Tag values for each lifecycle stage
	// Note: upstream does NOT have a "common" value — Common folder is tagged "production"
	envValues := []string{"bootstrap", "development", "nonproduction", "production"}
	tagValueMap := make(map[string]*tags.TagValue)
	tagOutputMap := make(pulumi.Map)

	for _, env := range envValues {
		tv, err := tags.NewTagValue(ctx, "tag-value-"+env, &tags.TagValueArgs{
			Parent:      envTagKey.ID(),
			ShortName:   pulumi.String(env),
			Description: pulumi.String(env + " environment"),
		})
		if err != nil {
			return pulumi.MapOutput{}, err
		}
		tagValueMap[env] = tv
		tagOutputMap[fmt.Sprintf("environment_%s", env)] = tv.ID()
	}

	// ========================================================================
	// Folder Tag Bindings (D13)
	// Bind environment tags to foundation folders, mirroring TF tags.tf.
	// ========================================================================

	// Common folder → production tag (shared infra is production-grade)
	if _, err := tags.NewTagBinding(ctx, "tag-binding-common", &tags.TagBindingArgs{
		Parent: folders.Common.Name.ApplyT(func(name string) string {
			return fmt.Sprintf("//cloudresourcemanager.googleapis.com/%s", name)
		}).(pulumi.StringOutput),
		TagValue: tagValueMap["production"].ID(),
	}); err != nil {
		return pulumi.MapOutput{}, err
	}

	// Network folder → production tag
	if _, err := tags.NewTagBinding(ctx, "tag-binding-network", &tags.TagBindingArgs{
		Parent: folders.Network.Name.ApplyT(func(name string) string {
			return fmt.Sprintf("//cloudresourcemanager.googleapis.com/%s", name)
		}).(pulumi.StringOutput),
		TagValue: tagValueMap["production"].ID(),
	}); err != nil {
		return pulumi.MapOutput{}, err
	}

	// Bootstrap folder → bootstrap tag (unconditionally using bootstrapRef output)
	commonConfig := bootstrapRef.GetOutput(pulumi.String("common_config"))
	bootstrapParent := commonConfig.ApplyT(func(v interface{}) string {
		m := v.(map[string]interface{})
		return fmt.Sprintf("//cloudresourcemanager.googleapis.com/%v", m["bootstrap_folder_name"])
	}).(pulumi.StringOutput)

	if _, err := tags.NewTagBinding(ctx, "tag-binding-bootstrap", &tags.TagBindingArgs{
		Parent:   bootstrapParent,
		TagValue: tagValueMap["bootstrap"].ID(),
	}); err != nil {
		return pulumi.MapOutput{}, err
	}

	return tagOutputMap.ToMapOutput(), nil
}
