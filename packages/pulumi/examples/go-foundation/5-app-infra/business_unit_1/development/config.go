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

// config.go mirrors upstream
// 5-app-infra/business_unit_1/development/variables.tf — the leaf's stack
// configuration surface (engine adaptation: Pulumi stack config instead of
// tfvars). The environment identity is NOT configured here; it is pinned by
// main.go (pinnedEnv/pinnedEnvCode), matching upstream's hardcoded locals.

package main

import (
	"fmt"
	"strings"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// AppInfraConfig holds configuration for this environment leaf of the
// app-infra stage. The environment identity is pinned by the leaf (pinnedEnv /
// pinnedEnvCode), not read from config.
type AppInfraConfig struct {
	Env                     string
	EnvCode                 string
	BusinessCode            string
	Region                  string
	ProjectsStackName       string
	ProjectsSharedStackName string
	ConfidentialImageDigest string
	ServerlessImageDigest   string
}

func loadAppInfraConfig(ctx *pulumi.Context) *AppInfraConfig {
	conf := config.New(ctx, "")
	c := &AppInfraConfig{
		Env:                     pinnedEnv,
		EnvCode:                 pinnedEnvCode,
		BusinessCode:            conf.Get("business_code"),
		Region:                  conf.Get("region"),
		ProjectsStackName:       conf.Get("projects_stack_name"),
		ProjectsSharedStackName: conf.Get("projects_shared_stack_name"),
		ConfidentialImageDigest: conf.Get("confidential_image_digest"),
		ServerlessImageDigest:   conf.Get("serverless_image_digest"),
	}

	if c.BusinessCode == "" {
		c.BusinessCode = "bu1"
	}
	// The projects reference targets this environment's 4-projects env leaf
	// stack; the shared reference defaults to the sibling business_unit_1/shared
	// leaf, derived by name substitution.
	if c.ProjectsStackName == "" {
		c.ProjectsStackName = fmt.Sprintf("organization/vitruvian/foundation-projects-%s-%s/production", c.BusinessCode, pinnedEnv)
	}
	if c.ProjectsSharedStackName == "" {
		c.ProjectsSharedStackName = strings.Replace(c.ProjectsStackName,
			fmt.Sprintf("foundation-projects-%s-%s", c.BusinessCode, pinnedEnv),
			fmt.Sprintf("foundation-projects-%s-shared", c.BusinessCode), 1)
	}
	return c
}
