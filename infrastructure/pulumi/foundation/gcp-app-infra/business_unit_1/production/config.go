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

// config.go is this leaf's variable surface (upstream variables.tf).

package main

import (
	"strings"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// AppInfraConfig is the leaf's resolved configuration.
type AppInfraConfig struct {
	Env          string
	EnvCode      string
	BusinessCode string
	Region       string

	// Cross-stage stacks (remote.go).
	ProjectsStackName  string
	BootstrapStackName string

	// Repository allowed to impersonate the platform-issued deploy identities.
	Repository string

	// Apps deployed into this environment.
	Apps []AppConfig
}

// AppConfig is one application's slot in this environment's app-infra leaf.
type AppConfig struct {
	// Name seeds resource names and the default deploy account id.
	Name string
	// DeployAccountID overrides the default <Name>-deploy. Set when ADOPTING an
	// account an app stack previously owned.
	DeployAccountID string
	// DeployRoles are the project-level roles the deploy SA needs.
	DeployRoles []string
}

// loadConfig resolves the leaf configuration from the stack config.
func loadConfig(ctx *pulumi.Context) *AppInfraConfig {
	cfg := config.New(ctx, "")

	c := &AppInfraConfig{
		Env:                pinnedEnv,
		EnvCode:            pinnedEnvCode,
		BusinessCode:       orDefault(cfg.Get("business_code"), "bu1"),
		Region:             orDefault(cfg.Get("region"), "us-west1"),
		ProjectsStackName:  cfg.Require("projects_stack_name"),
		BootstrapStackName: cfg.Require("bootstrap_stack_name"),
		Repository:         orDefault(cfg.Get("repository"), "VitruvianSoftware/vitruvian-core"),
	}

	// Apps are declared as a comma-separated list so a new app is a one-line
	// config change; per-app knobs stay keyed off the app name.
	for _, name := range splitList(cfg.Get("apps")) {
		app := AppConfig{
			Name:            name,
			DeployAccountID: cfg.Get(name + "_deploy_account_id"),
			DeployRoles:     splitList(cfg.Get(name + "_deploy_roles")),
		}
		if len(app.DeployRoles) == 0 {
			app.DeployRoles = defaultDeployRoles
		}
		c.Apps = append(c.Apps, app)
	}
	return c
}

// defaultDeployRoles is the least-privilege set a serverless app's deploy SA
// needs to ship a revision. It is replicated EXACTLY from the app-side stack
// being adopted (oauth-user-inspector/infra/identity) — adoption must not
// silently widen or narrow a live deploy identity's permissions. Anything
// broader belongs in an explicit per-app override so it shows up in review.
var defaultDeployRoles = []string{
	"roles/run.admin",
	"roles/iam.serviceAccountUser",
	"roles/serviceusage.serviceUsageConsumer",
	"roles/logging.viewer",
}

// GitHubEnvironment is the per-env GitHub Environment that may impersonate this
// app's deploy SA, e.g. "oauth-user-inspector-development".
func (a AppConfig) GitHubEnvironment(env string) string {
	return a.Name + "-" + env
}

func orDefault(v, def string) string {
	if v == "" {
		return def
	}
	return v
}

func splitList(v string) []string {
	if strings.TrimSpace(v) == "" {
		return nil
	}
	parts := strings.Split(v, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}
