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

// Package cloud_run provides a Cloud Run v2 service component.
//
// It wraps a single cloudrunv2.Service with sensible defaults (autoscaling,
// resource limits, ingress) and first-class support for secret-backed
// environment variables sourced from Secret Manager. IAM (e.g. the public
// allUsers invoker binding) is deliberately left to the caller so this
// primitive stays composable — mirrors the pkg/cloud_functions split.
package cloud_run

import (
	"fmt"
	"sort"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/cloudrunv2"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// SecretEnv is a container environment variable whose value is sourced from a
// Secret Manager secret in the same project.
type SecretEnv struct {
	Name       string             // container env var name
	SecretName pulumi.StringInput // Secret Manager secret id (short name, same project)
	Version    string             // secret version; "latest" when empty
}

// CloudRunArgs configures a Cloud Run v2 service.
type CloudRunArgs struct {
	ProjectID           pulumi.StringInput
	Region              string
	Name                string
	Image               pulumi.StringInput // digest ref: <region>-docker.pkg.dev/<proj>/<repo>/<img>@sha256:...
	ServiceAccountEmail pulumi.StringInput
	Env                 map[string]string // plain env vars
	SecretEnv           []SecretEnv       // secret-backed env vars
	Ingress             string            // default "INGRESS_TRAFFIC_ALL"
	Port                int               // default 8080
	MinInstances        int               // default 0
	MaxInstances        int               // default 2
	CpuLimit            string            // default "1"
	MemoryLimit         string            // default "512Mi"
	Labels              map[string]string
}

// CloudRun is the component wrapping the Cloud Run service.
type CloudRun struct {
	pulumi.ResourceState
	Service *cloudrunv2.Service
}

// NewCloudRun creates a Cloud Run v2 service as a child of a component resource.
func NewCloudRun(ctx *pulumi.Context, name string, args *CloudRunArgs, opts ...pulumi.ResourceOption) (*CloudRun, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}
	if args.Region == "" {
		return nil, fmt.Errorf("Region is required")
	}
	if args.Name == "" {
		return nil, fmt.Errorf("Name is required")
	}

	component := &CloudRun{}
	if err := ctx.RegisterComponentResource("pkg:index:CloudRun", name, component, opts...); err != nil {
		return nil, err
	}

	ingress := args.Ingress
	if ingress == "" {
		ingress = "INGRESS_TRAFFIC_ALL"
	}
	port := args.Port
	if port == 0 {
		port = 8080
	}
	maxInstances := args.MaxInstances
	if maxInstances == 0 {
		maxInstances = 2
	}
	cpu := args.CpuLimit
	if cpu == "" {
		cpu = "1"
	}
	memory := args.MemoryLimit
	if memory == "" {
		memory = "512Mi"
	}

	// Deterministic env var ordering: Cloud Run env is an ordered array, so a
	// non-deterministic map range would churn the diff on every preview.
	var envs cloudrunv2.ServiceTemplateContainerEnvArray
	plainKeys := make([]string, 0, len(args.Env))
	for k := range args.Env {
		plainKeys = append(plainKeys, k)
	}
	sort.Strings(plainKeys)
	for _, k := range plainKeys {
		envs = append(envs, &cloudrunv2.ServiceTemplateContainerEnvArgs{
			Name:  pulumi.String(k),
			Value: pulumi.String(args.Env[k]),
		})
	}
	for _, se := range args.SecretEnv {
		version := se.Version
		if version == "" {
			version = "latest"
		}
		envs = append(envs, &cloudrunv2.ServiceTemplateContainerEnvArgs{
			Name: pulumi.String(se.Name),
			ValueSource: &cloudrunv2.ServiceTemplateContainerEnvValueSourceArgs{
				SecretKeyRef: &cloudrunv2.ServiceTemplateContainerEnvValueSourceSecretKeyRefArgs{
					Secret:  se.SecretName,
					Version: pulumi.String(version),
				},
			},
		})
	}

	svcArgs := &cloudrunv2.ServiceArgs{
		Project:  args.ProjectID,
		Location: pulumi.String(args.Region),
		Name:     pulumi.String(args.Name),
		Ingress:  pulumi.String(ingress),
		Template: &cloudrunv2.ServiceTemplateArgs{
			ServiceAccount: args.ServiceAccountEmail,
			Scaling: &cloudrunv2.ServiceTemplateScalingArgs{
				MinInstanceCount: pulumi.Int(args.MinInstances),
				MaxInstanceCount: pulumi.Int(maxInstances),
			},
			Containers: cloudrunv2.ServiceTemplateContainerArray{
				&cloudrunv2.ServiceTemplateContainerArgs{
					Image: args.Image,
					Ports: &cloudrunv2.ServiceTemplateContainerPortsArgs{
						ContainerPort: pulumi.Int(port),
					},
					Envs: envs,
					Resources: &cloudrunv2.ServiceTemplateContainerResourcesArgs{
						Limits: pulumi.StringMap{
							"cpu":    pulumi.String(cpu),
							"memory": pulumi.String(memory),
						},
					},
				},
			},
		},
	}

	if len(args.Labels) > 0 {
		labels := pulumi.StringMap{}
		for k, v := range args.Labels {
			labels[k] = pulumi.String(v)
		}
		svcArgs.Labels = labels
	}

	svc, err := cloudrunv2.NewService(ctx, name, svcArgs, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.Service = svc

	if err := ctx.RegisterResourceOutputs(component, pulumi.Map{
		"serviceName": svc.Name,
		"serviceUri":  svc.Uri,
	}); err != nil {
		return nil, err
	}
	return component, nil
}
