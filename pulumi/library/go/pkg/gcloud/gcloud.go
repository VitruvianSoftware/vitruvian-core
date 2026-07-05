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

// Package gcloud provides a utility component for running gcloud CLI commands.
// Mirrors: terraform-google-modules/gcloud/google (local-exec provisioner pattern)
// In Pulumi, this uses the Command resource instead of local-exec.
package gcloud

import (
	"fmt"
	"strings"

	"github.com/pulumi/pulumi-command/sdk/go/command/local"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type GcloudArgs struct {
	Commands         []string
	Environment      map[string]string
	ServiceAccountKeyFile string
	ProjectID        string
	CreateCmdBody    string
	DestroyCmdBody   string
}

type Gcloud struct {
	pulumi.ResourceState
}

func NewGcloud(ctx *pulumi.Context, name string, args *GcloudArgs, opts ...pulumi.ResourceOption) (*Gcloud, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}
	component := &Gcloud{}
	err := ctx.RegisterComponentResource("pkg:index:Gcloud", name, component, opts...)
	if err != nil {
		return nil, err
	}

	cmdStr := strings.Join(args.Commands, " && ")
	if args.CreateCmdBody != "" {
		cmdStr = args.CreateCmdBody
	}

	envMap := pulumi.StringMap{}
	for k, v := range args.Environment {
		envMap[k] = pulumi.String(v)
	}

	_, err = local.NewCommand(ctx, name+"-cmd", &local.CommandArgs{
		Create:      pulumi.String(cmdStr),
		Environment: envMap,
	}, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{})
	return component, nil
}
