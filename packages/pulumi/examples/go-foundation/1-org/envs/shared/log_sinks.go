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

package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"foundation-1-org/modules/centralized_logging"
)

// deployLogSinks deploys Centralized Logging (org sinks → Storage, Pub/Sub,
// project Log Bucket, and optional billing-account sinks) by calling the
// centralized_logging module. This mirrors the Terraform foundation's
// log_sinks.tf, which invokes module "logs_export"
// (source = "../../modules/centralized-logging").
//
// Must run BEFORE policies so domain-restricted sharing waits for sinks (Gap 3).
func deployLogSinks(ctx *pulumi.Context, cfg *OrgConfig, proj *OrgProjects) (*centralized_logging.Result, error) {
	var retentionEnabled, retentionLocked bool
	var retentionDays int
	if cfg.LogExportStorageRetentionPolicy != nil {
		retentionEnabled = true
		retentionLocked = cfg.LogExportStorageRetentionPolicy.IsLocked
		retentionDays = cfg.LogExportStorageRetentionPolicy.RetentionPeriodDays
	}
	return centralized_logging.New(ctx, "logs-export", &centralized_logging.Args{
		ParentID:                     cfg.ParentID,
		ParentType:                   cfg.ParentType,
		BillingAccount:               cfg.BillingAccount,
		EnableBillingAccountSink:     cfg.EnableBillingAccountSink,
		LogExportStorageLocation:     cfg.LogExportStorageLocation,
		LogExportStorageForceDestroy: cfg.LogExportStorageForceDestroy,
		LogExportStorageVersioning:   cfg.LogExportStorageVersioning,
		RetentionEnabled:             retentionEnabled,
		RetentionLocked:              retentionLocked,
		RetentionDays:                retentionDays,
		DefaultRegion:                cfg.DefaultRegion,
		BillingExportDatasetLocation: cfg.BillingExportDatasetLocation,
		AuditProjectID:               proj.AuditLogsProjectID,
		BillingExportProjectID:       proj.BillingExportProjectID,
		BillingExportApisReady:       proj.BillingExportApisReady,
	})
}
