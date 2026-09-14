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

// Org-stage service accounts. This mirrors the Terraform foundation's
// 1-org/envs/shared/sa.tf, which creates only the cai-monitoring-builder
// service account (the stage pipeline SAs themselves live in 0-bootstrap).

package main

import (
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// deployCAIMonitoringBuilderSA creates the dedicated service account used by
// Cloud Build to provision the CAI monitoring Cloud Function (G4+G5).
// Its role bindings are granted in iam.go, mirroring the upstream
// sa.tf + iam.tf split for google_service_account.cai_monitoring_builder.
func deployCAIMonitoringBuilderSA(ctx *pulumi.Context, cfg *OrgConfig, proj *OrgProjects) error {
	if !cfg.EnableSCCResources {
		return nil
	}
	_, err := serviceaccount.NewAccount(ctx, "cai-monitoring-builder", &serviceaccount.AccountArgs{
		Project:     proj.SCCProjectID,
		AccountId:   pulumi.String("cai-monitoring-builder"),
		Description: pulumi.String("Service account for Cloud Build to provision CAI monitoring Cloud Functions"),
	})
	return err
}
