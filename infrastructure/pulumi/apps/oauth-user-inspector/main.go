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

// Package main is the per-environment oauth-user-inspector app stack on the
// vitruviansoftware.dev foundation (stage-5 "application stage", spec
// docs/superpowers/specs/2026-07-10-oss-application-stage-design.md).
//
// Each stack (development / nonproduction / production) deploys the app into
// the env's prj-{env}-bu1-oss-floating project as a Cloud Run v2 service,
// composed from the published pkg/cloud_run primitive — mirroring the
// serverless_space reference module's shape (runtime SA + SECRET_PREFIX env +
// opt-in allUsers invoker) without depending on the example tree.
//
// Build-once, promote-by-digest: the image is built ONCE by the build job
// (GitHub environment oauth-user-inspector-build) into the shared Artifact
// Registry in the infra-pipeline project, and every env deploys the SAME
// immutable @sha256 digest ref (never a mutable :tag). The digest arrives as
// the per-invocation OAUTH_USER_INSPECTOR_IMAGE_DIGEST env var (or the
// imageDigest config for a local break-glass run). The app's own Artifact
// Registry repository is gone — the shared repo is owned by the
// oauth-user-inspector-build stack.
//
// The allUsers run.invoker binding relies on the org's project-scoped
// domain-restricted-sharing override on the oss projects (gcp-org
// oss_public_invoker_projects, PR #867) — the app is a public demo tool.
//
// Runs as the per-env deploy SA (oauth-user-inspector-deploy@<oss project>,
// minted by the sibling oauth-user-inspector-deploy-identity stack) via the
// oauth-user-inspector-<env> GitHub Environment.
package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/VitruvianSoftware/pulumi-library/go/pkg/cloud_run"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/cloudrunv2"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// secretPrefix namespaces this app's Secret Manager reads so co-tenant OSS
// apps in the shared oss project cannot collide (server/server.ts getSecret
// prepends it; the runtime SA's accessor grant is conditioned to it).
const secretPrefix = "OAUTH_USER_INSPECTOR_"

const digestMarker = "@sha256:"

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "oauth-user-inspector")
		project := cfg.Require("project") // the env's oss-floating project id
		region := cfg.Get("region")
		if region == "" {
			region = "us-west1"
		}
		env := cfg.Require("environment")
		runtimeSA := cfg.Require("runtimeServiceAccount")

		// Immutable digest ref into the SHARED build Artifact Registry, e.g.
		//   us-west1-docker.pkg.dev/<infra-pipeline proj>/oauth-user-inspector/app@sha256:...
		// There is deliberately no mutable-tag fallback: deploying anything but a
		// pinned digest would break build-once/promote-digest.
		imageDigest := envOrConfig("OAUTH_USER_INSPECTOR_IMAGE_DIGEST", cfg, "imageDigest")
		if imageDigest == "" {
			if !ctx.DryRun() {
				return fmt.Errorf("an image digest ref is required: set OAUTH_USER_INSPECTOR_IMAGE_DIGEST (CI) or the imageDigest config to <ar>/app@sha256:...")
			}
			// Advisory PR previews (pulumi-preview.yaml) evaluate the program
			// without a build having run, so no digest exists yet. Substitute an
			// obviously-fake placeholder so the plan still renders (the image
			// field shows as a diff — expected preview noise). A real
			// `pulumi up` never takes this branch.
			imageDigest = "preview-placeholder@sha256:0000000000000000000000000000000000000000000000000000000000000000"
		}
		i := strings.LastIndex(imageDigest, digestMarker)
		if i < 0 || len(imageDigest) < i+len(digestMarker)+8 {
			return fmt.Errorf("imageDigest %q is not a digest ref (want <image>@sha256:<hex>)", imageDigest)
		}
		// Revision names must be stable + referenceable for blue-green promote;
		// derive the suffix from the digest's short hash (a digest is not a legal
		// revision name itself).
		shortDigest := imageDigest[i+len(digestMarker) : i+len(digestMarker)+8]
		revisionName := fmt.Sprintf("oauth-user-inspector-%s-%s", env, shortDigest)

		promote := envOrConfigBool("OAUTH_USER_INSPECTOR_PROMOTE", cfg, "promote")
		stableRevision := envOrConfig("OAUTH_USER_INSPECTOR_STABLE_REVISION", cfg, "stableRevision")

		// Blue-green: phase 1 (promote=false) keeps 100% pinned on the current
		// stable revision and publishes the new revision at 0% behind the
		// `candidate` tag (its dedicated URL is smoked before any shift); phase 2
		// (promote=true, after the smoke) routes 100% to the new revision. On the
		// first-ever deploy there is no stable revision, so traffic goes straight
		// to the new one.
		var traffics []cloud_run.TrafficTarget
		if promote || stableRevision == "" {
			traffics = []cloud_run.TrafficTarget{
				{Revision: revisionName, Percent: 100},
			}
		} else {
			traffics = []cloud_run.TrafficTarget{
				{Revision: stableRevision, Percent: 100},
				{Revision: revisionName, Percent: 0, Tag: "candidate"},
			}
		}

		app, err := cloud_run.NewCloudRun(ctx, "oauth-user-inspector", &cloud_run.CloudRunArgs{
			ProjectID:           pulumi.String(project),
			Region:              region,
			Name:                fmt.Sprintf("oauth-user-inspector-%s", env),
			Image:               pulumi.String(imageDigest),
			ServiceAccountEmail: pulumi.String(runtimeSA),
			Env: map[string]string{
				"NODE_ENV":             "production",
				"GOOGLE_CLOUD_PROJECT": project,
				"SECRET_PREFIX":        secretPrefix,
			},
			MaxInstances: 10,
			Port:         8080,
			RevisionName: revisionName,
			Traffics:     traffics,
		})
		if err != nil {
			return err
		}

		// Public demo tool: opt-in allUsers invoker (pkg/cloud_run leaves IAM to
		// the caller). Permitted on the oss projects by the gcp-org DRS override.
		if _, err := cloudrunv2.NewServiceIamMember(ctx, "oauth-user-inspector-public", &cloudrunv2.ServiceIamMemberArgs{
			Project:  pulumi.String(project),
			Location: pulumi.String(region),
			Name:     app.Service.Name,
			Role:     pulumi.String("roles/run.invoker"),
			Member:   pulumi.String("allUsers"),
		}); err != nil {
			return err
		}

		ctx.Export("serviceUrl", app.Service.Uri)
		ctx.Export("serviceAccount", pulumi.String(runtimeSA))
		return nil
	})
}

// envOrConfig reads a per-invocation deploy input: the environment variable
// wins (process-scoped, so concurrent invocations can't clobber each other).
func envOrConfig(envName string, cfg *config.Config, cfgKey string) string {
	if v := os.Getenv(envName); v != "" {
		return v
	}
	return cfg.Get(cfgKey)
}

// envOrConfigBool is envOrConfig for booleans.
func envOrConfigBool(envName string, cfg *config.Config, cfgKey string) bool {
	if v := os.Getenv(envName); v != "" {
		b, err := strconv.ParseBool(v)
		if err != nil {
			panic(fmt.Sprintf("%s=%q is not a boolean", envName, v))
		}
		return b
	}
	return cfg.GetBool(cfgKey)
}
