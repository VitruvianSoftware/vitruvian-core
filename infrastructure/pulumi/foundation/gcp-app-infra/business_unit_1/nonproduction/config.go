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

	// Cross-stage stack (remote.go).
	ProjectsStackName string

	// Apps deployed into this environment.
	Apps []AppConfig
}

// AppConfig is one application hosted in this environment. This leaf is
// scaffolding only: it re-exports the app's stage-4 deploy identity (keyed by
// Name) for the app's own infra/app stack to consume. The workload knobs
// (runtime SA, service name, env vars, invoker, max-instances) moved to the
// app's own stack along with the Cloud Run service.
type AppConfig struct {
	Name string
}

// loadConfig resolves the leaf configuration from the stack config.
func loadConfig(ctx *pulumi.Context) *AppInfraConfig {
	cfg := config.New(ctx, "")

	c := &AppInfraConfig{
		Env:               pinnedEnv,
		EnvCode:           pinnedEnvCode,
		BusinessCode:      orDefault(cfg.Get("business_code"), "bu1"),
		Region:            cfg.Get("region"), // empty => inherit projects default_region (remote.go)
		ProjectsStackName: cfg.Require("projects_stack_name"),
	}

	// Apps are declared as a comma-separated list so a new app is a one-line
	// config change; per-app knobs stay keyed off the app name.
	for _, name := range splitList(cfg.Get("apps")) {
		c.Apps = append(c.Apps, AppConfig{Name: name})
	}
	return c
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
