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

package app

import (
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/cloudrunv2"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// CloudRunAppArgs configures a Cloud Run v2 service deployment.
type CloudRunAppArgs struct {
	ProjectID      pulumi.StringInput
	Name           pulumi.StringInput
	Image          pulumi.StringInput
	Region         pulumi.StringInput
	ServiceAccount pulumi.StringPtrInput // SA email for the service identity
	Ingress        pulumi.StringPtrInput // default: INGRESS_TRAFFIC_ALL
	EnvVars        map[string]pulumi.StringInput
}

// CloudRunApp wraps a Cloud Run v2 Service as a ComponentResource.
type CloudRunApp struct {
	pulumi.ResourceState
	Service *cloudrunv2.Service
}

func NewCloudRunApp(ctx *pulumi.Context, name string, args *CloudRunAppArgs, opts ...pulumi.ResourceOption) (*CloudRunApp, error) {
	component := &CloudRunApp{}
	err := ctx.RegisterComponentResource("pkg:index:CloudRunApp", name, component, opts...)
	if err != nil {
		return nil, err
	}

	// Build environment variables array
	var envs cloudrunv2.ServiceTemplateContainerEnvArray
	for k, v := range args.EnvVars {
		envs = append(envs, &cloudrunv2.ServiceTemplateContainerEnvArgs{
			Name:  pulumi.String(k),
			Value: v,
		})
	}

	// Build the container spec
	container := &cloudrunv2.ServiceTemplateContainerArgs{
		Image: args.Image,
		Envs:  envs,
	}

	// Build the template
	templateArgs := &cloudrunv2.ServiceTemplateArgs{
		Containers: cloudrunv2.ServiceTemplateContainerArray{container},
	}
	if args.ServiceAccount != nil {
		templateArgs.ServiceAccount = args.ServiceAccount
	}

	// Determine ingress setting
	ingress := args.Ingress
	if ingress == nil {
		ingress = pulumi.StringPtr("INGRESS_TRAFFIC_ALL")
	}

	svc, err := cloudrunv2.NewService(ctx, name, &cloudrunv2.ServiceArgs{
		Name:     args.Name,
		Project:  args.ProjectID,
		Location: args.Region,
		Ingress:  ingress,
		Template: templateArgs,
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}

	component.Service = svc

	ctx.RegisterResourceOutputs(component, pulumi.Map{
		"serviceUri": svc.Uri,
	})

	return component, nil
}
