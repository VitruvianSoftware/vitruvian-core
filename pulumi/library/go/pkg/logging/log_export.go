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

// Package logging provides reusable components for centralized log export
// infrastructure. It mirrors the upstream Terraform modules:
//   - terraform-google-modules/log-export/google (LogExport)
//   - modules/centralized-logging (CentralizedLogging)
package logging

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/logging"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// LogExportArgs configures a single log sink.
//
// This mirrors the terraform-google-modules/log-export/google module.
// The ResourceType determines which GCP sink resource is created:
//   - "organization" → logging.OrganizationSink
//   - "folder"       → logging.FolderSink
//   - "project"      → logging.ProjectSink
//   - "billing_account" → logging.BillingAccountSink
type LogExportArgs struct {
	// DestinationURI is the full URI of the log destination.
	// Examples:
	//   storage.googleapis.com/my-bucket
	//   pubsub.googleapis.com/projects/p/topics/t
	//   logging.googleapis.com/projects/p/locations/l/buckets/b
	DestinationURI pulumi.StringInput

	// Filter is the log filter expression. Empty string exports all logs.
	Filter pulumi.StringInput

	// LogSinkName is the display name of the sink in GCP.
	LogSinkName pulumi.StringInput

	// ParentResourceID is the numeric ID of the parent (org ID, folder ID,
	// project ID, or billing account ID).
	ParentResourceID pulumi.StringInput

	// ResourceType must be one of: "organization", "folder", "project",
	// "billing_account".
	ResourceType string

	// UniqueWriterIdentity when true, creates a unique writer identity for
	// the sink (required for cross-project destinations).
	UniqueWriterIdentity bool

	// IncludeChildren when true, the sink captures logs from child resources
	// (only applicable for organization and folder sinks).
	IncludeChildren bool
}

// LogExport is a component that creates a single log sink.
type LogExport struct {
	pulumi.ResourceState

	// WriterIdentity is the service account identity that the sink uses to
	// write logs to the destination. Grant this identity appropriate IAM
	// roles on the destination resource.
	WriterIdentity pulumi.StringOutput

	// Sink is the underlying sink resource (one of OrganizationSink,
	// FolderSink, ProjectSink, or BillingAccountSink).
	Sink pulumi.Resource
}

// NewLogExport creates a log sink component.
//
// The ResourceType in args determines which GCP sink resource is provisioned.
// This mirrors the terraform-google-modules/log-export/google module's
// behavior of routing based on parent_resource_type.
func NewLogExport(ctx *pulumi.Context, name string, args *LogExportArgs, opts ...pulumi.ResourceOption) (*LogExport, error) {
	if args == nil {
		return nil, fmt.Errorf("args cannot be nil")
	}

	component := &LogExport{}
	err := ctx.RegisterComponentResource("pkg:logging:LogExport", name, component, opts...)
	if err != nil {
		return nil, err
	}

	childOpts := []pulumi.ResourceOption{pulumi.Parent(component)}

	switch args.ResourceType {
	case "organization":
		sink, err := logging.NewOrganizationSink(ctx, name+"-sink", &logging.OrganizationSinkArgs{
			Name:            args.LogSinkName,
			OrgId:           args.ParentResourceID,
			Destination:     args.DestinationURI,
			Filter:          args.Filter,
			IncludeChildren: pulumi.Bool(args.IncludeChildren),
		}, childOpts...)
		if err != nil {
			return nil, err
		}
		component.WriterIdentity = sink.WriterIdentity
		component.Sink = sink

	case "folder":
		sink, err := logging.NewFolderSink(ctx, name+"-sink", &logging.FolderSinkArgs{
			Name:            args.LogSinkName,
			Folder:          args.ParentResourceID,
			Destination:     args.DestinationURI,
			Filter:          args.Filter,
			IncludeChildren: pulumi.Bool(args.IncludeChildren),
		}, childOpts...)
		if err != nil {
			return nil, err
		}
		component.WriterIdentity = sink.WriterIdentity
		component.Sink = sink

	case "project":
		sinkArgs := &logging.ProjectSinkArgs{
			Name:                 args.LogSinkName,
			Project:              args.ParentResourceID,
			Destination:          args.DestinationURI,
			Filter:               args.Filter,
			UniqueWriterIdentity: pulumi.Bool(args.UniqueWriterIdentity),
		}
		sink, err := logging.NewProjectSink(ctx, name+"-sink", sinkArgs, childOpts...)
		if err != nil {
			return nil, err
		}
		component.WriterIdentity = sink.WriterIdentity
		component.Sink = sink

	case "billing_account":
		sink, err := logging.NewBillingAccountSink(ctx, name+"-sink", &logging.BillingAccountSinkArgs{
			Name:           args.LogSinkName,
			BillingAccount: args.ParentResourceID,
			Destination:    args.DestinationURI,
			Filter:         args.Filter,
		}, childOpts...)
		if err != nil {
			return nil, err
		}
		component.WriterIdentity = sink.WriterIdentity
		component.Sink = sink

	default:
		return nil, fmt.Errorf("unsupported resource_type %q: must be organization, folder, project, or billing_account", args.ResourceType)
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"writerIdentity": component.WriterIdentity,
	})
	return component, nil
}
