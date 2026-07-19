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
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"foundation-org/modules/centralized_logging"
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
	// Cold-deploy gate: every child of the logging component (bucket,
	// topic, log bucket, sinks) must wait for the audit-logs project's
	// freshly-enabled APIs to propagate; belt-and-braces also gate on the
	// billing-export project's APIs (the billing dataset lives there).
	var loggingApiDeps []pulumi.Resource
	if proj.AuditLogsApisReady != nil {
		loggingApiDeps = append(loggingApiDeps, proj.AuditLogsApisReady)
	}
	if proj.BillingExportApisReady != nil {
		loggingApiDeps = append(loggingApiDeps, proj.BillingExportApisReady)
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
		Dependencies:                 loggingApiDeps,
	})
}
