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

	libsecurity "github.com/VitruvianSoftware/pulumi-library/go/pkg/cai_monitoring"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// caiRolesToMonitor defines the IAM roles that trigger SCC findings when
// granted to new members. These are high-privilege roles that should be
// closely monitored. Matches the upstream default roles_to_monitor variable.
var caiRolesToMonitor = []string{
	"roles/owner",
	"roles/editor",
	"roles/resourcemanager.organizationAdmin",
	"roles/iam.serviceAccountTokenCreator",
}

// CAIMonitoringOutputs holds resource names for downstream exports.
// Mirrors upstream outputs: cai_monitoring_artifact_registry, cai_monitoring_asset_feed,
// cai_monitoring_bucket, cai_monitoring_topic.
type CAIMonitoringOutputs struct {
	ArtifactRegistryName pulumi.StringOutput
	AssetFeedName        pulumi.StringOutput
	BucketName           pulumi.StringOutput
	TopicName            pulumi.StringOutput
}

// deployCAIMonitoring deploys the Cloud Asset Inventory monitoring
// infrastructure using the pkg/security library component.
//
// This replaces ~250 lines of inline resource orchestration with a single
// reusable component call. The component mirrors the upstream Terraform
// foundation's 1-org/modules/cai-monitoring module.
//
// The CAI monitoring pipeline works as follows:
//  1. A Cloud Asset Organization Feed watches for IAM policy changes
//  2. Changes are published to a Pub/Sub topic
//  3. A Cloud Function (v2) is triggered by the Pub/Sub messages
//  4. The function checks for IAM bindings with monitored roles
//  5. Violations are reported as SCC findings via the SCC Source
func deployCAIMonitoring(ctx *pulumi.Context, cfg *OrgConfig, sccProjectID pulumi.StringOutput) (*CAIMonitoringOutputs, error) {
	// The builder SA (cai-monitoring-builder) was created in iam.go section 11.
	// It's used as the build_service_account for Cloud Build.
	builderSAEmail := sccProjectID.ApplyT(func(id string) string {
		return fmt.Sprintf("projects/%s/serviceAccounts/cai-monitoring-builder@%s.iam.gserviceaccount.com", id, id)
	}).(pulumi.StringOutput)

	cai, err := libsecurity.NewCAIMonitoring(ctx, "cai-monitoring", &libsecurity.CAIMonitoringArgs{
		OrgID:               pulumi.String(cfg.OrgID),
		ProjectID:           sccProjectID,
		Location:            cfg.DefaultRegion,
		BuildServiceAccount: builderSAEmail,
		FunctionSourcePath:  "./cai-monitoring-function",
		RolesToMonitor:      caiRolesToMonitor,
	})
	if err != nil {
		return nil, err
	}

	return &CAIMonitoringOutputs{
		ArtifactRegistryName: cai.ArtifactRegistryName,
		AssetFeedName:        cai.AssetFeedName,
		BucketName:           cai.BucketName,
		TopicName:            cai.TopicName,
	}, nil
}
