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
	// RevisionName, when set, names the created revision. Blue-green promotion
	// needs stable, referenceable revision names (the deploy pipeline pins the
	// stable revision and tags the new one as a candidate).
	RevisionName string
	// Traffics, when set, controls how traffic is split across revisions. When
	// empty, Cloud Run defaults to 100% on the latest revision.
	Traffics []TrafficTarget
}

// TrafficTarget is one entry in a Cloud Run service's traffic split — the unit
// of blue-green promotion (e.g. 100% to the stable revision, 0% to a tagged
// "candidate" revision that a smoke test hits before promotion).
type TrafficTarget struct {
	Revision string // target revision name; ignored when Latest is true
	Latest   bool   // route to the latest ready revision instead of a named one
	Percent  int    // percent of traffic (0-100)
	Tag      string // optional traffic tag (e.g. "candidate") — yields a taggable URL
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

	tmpl := &cloudrunv2.ServiceTemplateArgs{
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
	}
	if args.RevisionName != "" {
		tmpl.Revision = pulumi.String(args.RevisionName)
	}

	svcArgs := &cloudrunv2.ServiceArgs{
		Project:  args.ProjectID,
		Location: pulumi.String(args.Region),
		Name:     pulumi.String(args.Name),
		Ingress:  pulumi.String(ingress),
		Template: tmpl,
	}

	// Blue-green traffic split. Each target is either a named revision or the
	// latest ready revision, with a percent and an optional tag.
	if len(args.Traffics) > 0 {
		var traffics cloudrunv2.ServiceTrafficArray
		for _, t := range args.Traffics {
			ta := &cloudrunv2.ServiceTrafficArgs{
				Percent: pulumi.Int(t.Percent),
			}
			if t.Latest {
				ta.Type = pulumi.String("TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST")
			} else {
				ta.Type = pulumi.String("TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION")
				ta.Revision = pulumi.String(t.Revision)
			}
			if t.Tag != "" {
				ta.Tag = pulumi.String(t.Tag)
			}
			traffics = append(traffics, ta)
		}
		svcArgs.Traffics = traffics
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
