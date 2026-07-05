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

// Package cloud_functions provides a Cloud Functions v2 component with
// event trigger support.
// Mirrors: terraform-google-modules/event-function/google
package cloud_functions

import (
	"fmt"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/cloudfunctionsv2"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type CloudFunctionArgs struct {
	ProjectID         pulumi.StringInput
	Region            string
	Name              string
	Description       string
	Runtime           string
	EntryPoint        string
	SourceBucket      pulumi.StringInput
	SourceObject      pulumi.StringInput
	EventTriggerType  string
	EventTriggerResource pulumi.StringInput
	ServiceAccountEmail  pulumi.StringInput
	AvailableMemory   string
	Timeout           int
	Labels            map[string]string
}

type CloudFunction struct {
	pulumi.ResourceState
	Function *cloudfunctionsv2.Function
}

func NewCloudFunction(ctx *pulumi.Context, name string, args *CloudFunctionArgs, opts ...pulumi.ResourceOption) (*CloudFunction, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}
	component := &CloudFunction{}
	err := ctx.RegisterComponentResource("pkg:index:CloudFunction", name, component, opts...)
	if err != nil {
		return nil, err
	}

	runtime := args.Runtime
	if runtime == "" {
		runtime = "python310"
	}
	memory := args.AvailableMemory
	if memory == "" {
		memory = "256M"
	}
	timeout := args.Timeout
	if timeout == 0 {
		timeout = 60
	}

	fnArgs := &cloudfunctionsv2.FunctionArgs{
		Project:     args.ProjectID,
		Location:    pulumi.String(args.Region),
		Name:        pulumi.String(args.Name),
		Description: pulumi.String(args.Description),
		BuildConfig: &cloudfunctionsv2.FunctionBuildConfigArgs{
			Runtime:    pulumi.String(runtime),
			EntryPoint: pulumi.String(args.EntryPoint),
			Source: &cloudfunctionsv2.FunctionBuildConfigSourceArgs{
				StorageSource: &cloudfunctionsv2.FunctionBuildConfigSourceStorageSourceArgs{
					Bucket: args.SourceBucket,
					Object: args.SourceObject,
				},
			},
		},
		ServiceConfig: &cloudfunctionsv2.FunctionServiceConfigArgs{
			AvailableMemory:            pulumi.String(memory),
			TimeoutSeconds:             pulumi.Int(timeout),
			ServiceAccountEmail:        args.ServiceAccountEmail,
		},
	}

	if len(args.Labels) > 0 {
		labels := pulumi.StringMap{}
		for k, v := range args.Labels {
			labels[k] = pulumi.String(v)
		}
		fnArgs.Labels = labels
	}

	if args.EventTriggerType != "" {
		fnArgs.EventTrigger = &cloudfunctionsv2.FunctionEventTriggerArgs{
			EventType:   pulumi.String(args.EventTriggerType),
			TriggerRegion: pulumi.String(args.Region),
		}
	}

	fn, err := cloudfunctionsv2.NewFunction(ctx, name, fnArgs, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.Function = fn

	ctx.RegisterResourceOutputs(component, pulumi.Map{"functionName": fn.Name})
	return component, nil
}
