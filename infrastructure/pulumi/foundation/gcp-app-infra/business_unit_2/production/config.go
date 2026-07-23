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
	"strconv"
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

// AppConfig is one application hosted in this environment. Its deploy identity
// is minted in gcp-projects and consumed here by StackReference.
type AppConfig struct {
	Name string
	// WorkloadEnabled turns on the serverless_space archetype for this app.
	//
	// DEFAULT FALSE, and that is the cutover switch. The app's Cloud Run
	// service is LIVE and serving; a Pulumi stack cannot take ownership of an
	// existing resource just by declaring it. The move requires `pulumi
	// import` into this stack plus a state delete from the app stack — both
	// credentialed operations that cannot happen in a PR. So this code ships
	// inert, and the cutover is a per-env runbook step
	// (docs/engineering/core-vs-application-infrastructure.md §7).
	WorkloadEnabled bool
	// RuntimeServiceAccount is the app's runtime identity (the app still owns
	// it — only the workload moves).
	RuntimeServiceAccount string
	// SecretPrefix partitions the app's Secret Manager reads in a shared project.
	SecretPrefix string
	// ServiceName is the app's BASE service name. serverless_space appends the
	// environment, so the deployed service is <ServiceName>-<env> — matching
	// what the app stack runs today. Do NOT put the env in this value.
	ServiceName string
	// MaxInstances caps autoscaling; 0 leaves the archetype default.
	MaxInstances int
	// PublicInvoker grants allUsers run.invoker (DRS-permitted on oss projects).
	PublicInvoker bool
	// EnvVars are the app's plain (non-secret) container env vars, as
	// "K=V,K2=V2". These must REPRODUCE what the live service already has: the
	// §7 step-2 post-import preview is only empty when they match, and an apply
	// with a var missing STRIPS it off a running service. The archetype adds
	// SECRET_PREFIX itself, so it is not listed here.
	EnvVars map[string]string
}

// loadConfig resolves the leaf configuration from the stack config.
func loadConfig(ctx *pulumi.Context) *AppInfraConfig {
	cfg := config.New(ctx, "")

	c := &AppInfraConfig{
		Env:               pinnedEnv,
		EnvCode:           pinnedEnvCode,
		BusinessCode:      orDefault(cfg.Get("business_code"), "bu2"),
		Region:            cfg.Get("region"), // empty => inherit projects default_region (remote.go)
		ProjectsStackName: cfg.Require("projects_stack_name"),
	}

	// Apps are declared as a comma-separated list so a new app is a one-line
	// config change; per-app knobs stay keyed off the app name.
	for _, name := range splitList(cfg.Get("apps")) {
		app := AppConfig{
			Name:                  name,
			WorkloadEnabled:       cfg.Get(name+"_workload_enabled") == "true",
			RuntimeServiceAccount: cfg.Get(name + "_runtime_service_account"),
			SecretPrefix:          cfg.Get(name + "_secret_prefix"),
			ServiceName:           orDefault(cfg.Get(name+"_service_name"), name),
			PublicInvoker:         cfg.Get(name+"_public_invoker") == "true",
			EnvVars:               splitKV(cfg.Get(name + "_env_vars")),
		}
		if v := cfg.Get(name + "_max_instances"); v != "" {
			if n, err := strconv.Atoi(v); err == nil {
				app.MaxInstances = n
			}
		}
		c.Apps = append(c.Apps, app)
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

// splitKV parses "K=V,K2=V2" into a map; empty input yields nil.
func splitKV(s string) map[string]string {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	m := map[string]string{}
	for _, part := range strings.Split(s, ",") {
		kv := strings.SplitN(strings.TrimSpace(part), "=", 2)
		if len(kv) == 2 && kv[0] != "" {
			m[kv[0]] = kv[1]
		}
	}
	return m
}
