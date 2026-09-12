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

// Package centralized_logging creates the org-wide centralized logging
// infrastructure (log sinks routed to Storage, Pub/Sub, and a project log
// bucket with a linked BigQuery dataset) plus the standalone billing-export
// dataset. It mirrors upstream terraform-example-foundation
// 1-org/modules/centralized-logging (invoked by 1-org log_sinks.tf). The thin
// stage root (main.go) resolves scalars/Outputs from stack config + upstream
// project outputs and calls New; all resource creation lives here.
package centralized_logging

import (
	logging "github.com/VitruvianSoftware/pulumi-library/go/pkg/centralized_logging"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/bigquery"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Args are the inputs to the centralized_logging module. It carries resolved
// scalars/Outputs (never *OrgConfig — the module cannot import the root
// package) matching the upstream module inputs plus the audit/billing project
// outputs from the org projects stage.
type Args struct {
	// Parent resource routing — cfg.ParentID / cfg.ParentType.
	ParentID   string
	ParentType string // "organization" or "folder"

	BillingAccount           string
	EnableBillingAccountSink bool

	// Storage sink options.
	LogExportStorageLocation     string
	LogExportStorageForceDestroy bool
	LogExportStorageVersioning   bool

	// Storage retention policy (resolved from cfg.LogExportStorageRetentionPolicy).
	RetentionEnabled bool
	RetentionLocked  bool
	RetentionDays    int

	// Project log bucket / linked dataset location.
	DefaultRegion string

	// Billing export BigQuery dataset location.
	BillingExportDatasetLocation string

	// Cross-stage project outputs from the org projects stage.
	AuditProjectID         pulumi.StringOutput
	BillingExportProjectID pulumi.StringOutput
	BillingExportApisReady pulumi.Resource // gates the billing dataset on the billing-export project APIs
}

// Result holds the outputs of the centralized logging deployment for
// downstream exports.
type Result struct {
	StorageBucketName pulumi.StringOutput
	PubSubTopicName   pulumi.StringOutput
	LogBucketName     pulumi.StringOutput            // upstream: logs_export_project_logbucket_name
	LinkedDatasetName pulumi.StringOutput            // upstream: logs_export_project_linked_dataset_name
	BillingSinkNames  map[string]pulumi.StringOutput // upstream: billing_sink_names
	// LastResource is the last resource created by the logging deployment,
	// used for dependency ordering (e.g., policies must wait for sinks).
	LastResource pulumi.Resource
}

// New creates the centralized logging infrastructure by delegating to the
// pkg/centralized_logging library component.
//
// This mirrors the Terraform foundation's log_sinks.tf which calls
// module "logs_export" (source = "../../modules/centralized-logging").
//
// The library component handles:
//   - Dynamic org/folder sink routing based on args.ParentType
//   - Destination resource creation (storage, pubsub, log bucket)
//   - IAM grants for each sink writer identity
//   - Billing account sinks (when enabled)
//   - Internal project sink (prevents the audit project from being a blind spot)
//
// The log filter covers all audit and network logs, matching the upstream.
func New(ctx *pulumi.Context, name string, args *Args) (*Result, error) {
	// Comprehensive log filter covering all audit and network logs
	// Matches upstream log_sinks.tf local.logs_filter
	logFilter := `logName: /logs/cloudaudit.googleapis.com%2Factivity OR
logName: /logs/cloudaudit.googleapis.com%2Fsystem_event OR
logName: /logs/cloudaudit.googleapis.com%2Fdata_access OR
logName: /logs/cloudaudit.googleapis.com%2Faccess_transparency OR
logName: /logs/cloudaudit.googleapis.com%2Fpolicy OR
logName: /logs/compute.googleapis.com%2Fvpc_flows OR
logName: /logs/compute.googleapis.com%2Ffirewall OR
logName: /logs/dns.googleapis.com%2Fdns_queries`

	// Delegate to the library component — this replaces ~250 lines of
	// inline sink orchestration with a single, tested, reusable call.
	cl, err := logging.NewCentralizedLogging(ctx, name, &logging.CentralizedLoggingArgs{
		Resources:                   map[string]string{"resource": args.ParentID},
		ResourceType:                args.ParentType, // "organization" or "folder"
		LoggingDestinationProjectID: args.AuditProjectID,
		BillingAccount:              args.BillingAccount,
		EnableBillingAccountSink:    args.EnableBillingAccountSink,

		StorageOptions: &logging.StorageOptions{
			LoggingSinkName:           "sk-c-logging-bkt",
			LoggingSinkFilter:         logFilter,
			Location:                  args.LogExportStorageLocation,
			ForceDestroy:              args.LogExportStorageForceDestroy,
			Versioning:                args.LogExportStorageVersioning,
			RetentionPolicyEnabled:    args.RetentionEnabled,
			RetentionPolicyIsLocked:   args.RetentionLocked,
			RetentionPolicyPeriodDays: args.RetentionDays,
		},

		PubSubOptions: &logging.PubSubOptions{
			LoggingSinkName:   "sk-c-logging-pub",
			LoggingSinkFilter: logFilter,
			CreateSubscriber:  true,
		},

		ProjectOptions: &logging.ProjectOptions{
			LoggingSinkName:          "sk-c-logging-prj",
			LoggingSinkFilter:        logFilter,
			LogBucketID:              "AggregatedLogs",
			LogBucketDescription:     "Project destination log bucket for aggregated logs",
			Location:                 args.DefaultRegion,
			EnableAnalytics:          true,
			LinkedDatasetID:          "ds_c_prj_aggregated_logs_analytics",
			LinkedDatasetDescription: "Project destination BigQuery Dataset for Logbucket analytics",
		},
	})
	if err != nil {
		return nil, err
	}

	// ====================================================================
	// Billing Export BigQuery Dataset
	// This lives outside the centralized-logging module in the upstream TF
	// (log_sinks.tf google_bigquery_dataset.billing_dataset). The actual
	// billing export must be configured manually in the Cloud Console.
	// ====================================================================
	bqOpts := []pulumi.ResourceOption{}
	if args.BillingExportApisReady != nil {
		bqOpts = append(bqOpts, pulumi.DependsOn([]pulumi.Resource{args.BillingExportApisReady}))
	}
	if _, err := bigquery.NewDataset(ctx, "billing-dataset", &bigquery.DatasetArgs{
		Project:      args.BillingExportProjectID,
		DatasetId:    pulumi.String("billing_data"),
		FriendlyName: pulumi.String("GCP Billing Data"),
		Location:     pulumi.String(args.BillingExportDatasetLocation),
	}, bqOpts...); err != nil {
		return nil, err
	}

	return &Result{
		StorageBucketName: cl.StorageBucketName,
		PubSubTopicName:   cl.PubSubTopicName,
		LogBucketName:     cl.ProjectLogBucketName,
		LinkedDatasetName: cl.LinkedDatasetName,
		BillingSinkNames:  cl.BillingSinkNames,
		LastResource:      cl.LastResource,
	}, nil
}
