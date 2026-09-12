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

// Package log_export provides a reusable LogExport component for creating
// GCP log sinks at organization, folder, project, or billing account level.
// Mirrors: terraform-google-modules/log-export/google
package log_export

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/logging"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// LogExportArgs configures a single log sink.
type LogExportArgs struct {
	DestinationURI       pulumi.StringInput
	Filter               pulumi.StringInput
	LogSinkName          pulumi.StringInput
	ParentResourceID     pulumi.StringInput
	ResourceType         string // "organization", "folder", "project", "billing_account"
	UniqueWriterIdentity bool
	IncludeChildren      bool
}

// LogExport is a component that creates a single GCP log sink.
type LogExport struct {
	pulumi.ResourceState
	WriterIdentity pulumi.StringOutput
	Sink           pulumi.Resource
}

// NewLogExport creates a log sink component.
func NewLogExport(ctx *pulumi.Context, name string, args *LogExportArgs, opts ...pulumi.ResourceOption) (*LogExport, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}

	component := &LogExport{}
	err := ctx.RegisterComponentResource("pkg:index:LogExport", name, component, opts...)
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
		sink, err := logging.NewProjectSink(ctx, name+"-sink", &logging.ProjectSinkArgs{
			Name:                 args.LogSinkName,
			Project:              args.ParentResourceID,
			Destination:          args.DestinationURI,
			Filter:               args.Filter,
			UniqueWriterIdentity: pulumi.Bool(args.UniqueWriterIdentity),
		}, childOpts...)
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
		return nil, fmt.Errorf("unsupported resource_type %q", args.ResourceType)
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"writerIdentity": component.WriterIdentity,
	})
	return component, nil
}
