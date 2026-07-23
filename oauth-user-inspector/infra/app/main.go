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
	"github.com/pulumi/pulumi-cloudflare/sdk/v5/go/cloudflare"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/cloudrun"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/cloudrunv2"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// secretPrefix namespaces this app's Secret Manager reads so co-tenant OSS
// apps in the shared oss project cannot collide (server/server.ts getSecret
// prepends it; the runtime SA's accessor grant is conditioned to it).
const secretPrefix = "OAUTH_USER_INSPECTOR_"

const digestMarker = "@sha256:"

// cfPreviewToken is the non-secret placeholder value pulumi-preview.yaml injects
// as CLOUDFLARE_API_TOKEN for the advisory oauth preview (matrix.cfPreviewToken).
// It lets the default cloudflare provider CONFIGURE without a real credential;
// the code treats it as "not a real token" so it never calls the Cloudflare API
// with it. Keep this in sync with pulumi-preview.yaml.
const cfPreviewToken = "preview-only-not-a-real-cloudflare-token"

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

		// WORKLOAD MIGRATION (core-vs-application split). Default FALSE: the app
		// stack owns its Cloud Run service, as it always has. When TRUE the
		// service + public invoker are owned by the foundation gcp-app-infra
		// leaf (the serverless_space archetype), and this stack stops declaring
		// them — but the CUSTOM DOMAIN stays here by design
		// (docs/engineering/core-vs-application-infrastructure.md: the domain
		// mapping and its DNS record are app-specific).
		serviceName := fmt.Sprintf("oauth-user-inspector-%s", env)
		workloadMigrated := cfg.GetBool("workloadMigrated")

		// The DomainMapping targets the local service resource pre-migration and
		// the literal service name post-migration. Both resolve to the same
		// string, so flipping the flag is a no-op for the mapping.
		var routeName pulumi.StringInput = pulumi.String(serviceName)

		if !workloadMigrated {
			app, err := cloud_run.NewCloudRun(ctx, "oauth-user-inspector", &cloud_run.CloudRunArgs{
				ProjectID:           pulumi.String(project),
				Region:              pulumi.String(region),
				Name:                serviceName,
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
			routeName = app.Service.Name
			ctx.Export("serviceUrl", app.Service.Uri)

			// Public demo tool: opt-in allUsers invoker (pkg/cloud_run leaves
			// IAM to the caller). Permitted on the oss projects by the gcp-org
			// DRS override. Post-migration the foundation leaf owns this.
			if _, err := cloudrunv2.NewServiceIamMember(ctx, "oauth-user-inspector-public", &cloudrunv2.ServiceIamMemberArgs{
				Project:  pulumi.String(project),
				Location: pulumi.String(region),
				Name:     app.Service.Name,
				Role:     pulumi.String("roles/run.invoker"),
				Member:   pulumi.String("allUsers"),
			}); err != nil {
				return err
			}
		}

		// Optional per-env custom domain (config `customDomain`, e.g.
		// oauth-inspector.ipv1337.dev): a Cloud Run DomainMapping (v1 API —
		// there is no v2 equivalent; it binds by the run service's short name)
		// plus a grey-cloud (DNS-only) Cloudflare CNAME pointing the hostname
		// at Google's front end. Proxied MUST stay false: Google's managed
		// certificate on the mapping validates the hostname over plain DNS,
		// and an orange-cloud proxy would intercept that and break issuance.
		// Absent/empty config keeps the env mapping-free (opt-in preserved).
		//
		// Prereq (AUTOMATED, app-scoped): the deploying SA must be a verified
		// owner of the domain or the DomainMapping create is rejected by the
		// API. Ownership in Google's Site Verification service is PER-CALLER,
		// so THIS env's deploy job SELF-verifies the zone as its own deploy SA
		// right before this `pulumi up` (the _deploy-cloud-run.yaml "Ensure
		// custom-domain ownership" step running
		// tools/ci/ensure-site-verification.sh with the env's OWN floating
		// project as the Site Verification quota project; every floating
		// project declares siteverification in the foundation project
		// factory's ActivateApis + a one-time manual console enable, and the
		// app's dev identity stack anchors the Cloudflare-token secret IAM).
		// Self-verify = Site Verification DNS-TXT + a persistent Cloudflare
		// TXT record per env SA; there is NO owner delegation (the API refuses
		// owners-list writes when an external token-verified owner is
		// present). No manual Search Console step.
		if customDomain := cfg.Get("customDomain"); customDomain != "" {
			mapping, err := cloudrun.NewDomainMapping(ctx, "oauth-user-inspector-domain", &cloudrun.DomainMappingArgs{
				Project:  pulumi.String(project),
				Location: pulumi.String(region),
				Name:     pulumi.String(customDomain),
				Metadata: &cloudrun.DomainMappingMetadataArgs{
					Namespace: pulumi.String(project),
				},
				Spec: &cloudrun.DomainMappingSpecArgs{
					// Reference the service OUTPUT (not the literal name) so
					// the mapping is ordered after the service exists on a
					// first-ever deploy.
					RouteName: routeName,
					// Take over the domain if it is still mapped elsewhere
					// (e.g. prod's oauth-inspector.ipv1337.dev was mapped to a
					// retired gen-lang demo project). Without this the create
					// is rejected: "Domain is already mapped to another
					// project or region ... specify forceOverride". Set
					// unconditionally for all envs: it is a no-op for a domain
					// this project already owns (dev/nonprod), and robust
					// against any future re-map.
					ForceOverride: pulumi.Bool(true),
				},
			})
			if err != nil {
				return err
			}

			// DNS target from the mapping's status: a subdomain mapping
			// surfaces exactly one CNAME resource record. The fallback
			// ghs.googlehosted.com is Google's documented target for Cloud
			// Run subdomain mappings and covers a not-yet-populated status.
			dnsTarget := mapping.Statuses.ApplyT(func(ss []cloudrun.DomainMappingStatus) string {
				if len(ss) > 0 {
					for _, rr := range ss[0].ResourceRecords {
						if rr.Rrdata != nil && *rr.Rrdata != "" {
							return *rr.Rrdata
						}
					}
				}
				return "ghs.googlehosted.com"
			}).(pulumi.StringOutput)

			ctx.Export("customDomain", pulumi.String(customDomain))
			ctx.Export("customDomainDnsTarget", dnsTarget)

			// The Cloudflare credential arrives via the CLOUDFLARE_API_TOKEN env
			// var — at deploy time the REAL token, fetched from the dev floating
			// project's Secret Manager as the env's deploy SA
			// (_deploy-cloud-run.yaml cloudflare-token-secret-project; never a
			// GitHub secret, never in Pulumi config or state — secrets model
			// §pipeline-env). Advisory PR previews get a NON-SECRET placeholder
			// (pulumi-preview.yaml matrix.cfPreviewToken, == cfPreviewToken here)
			// so the default cloudflare provider can still CONFIGURE without a
			// real credential; a dry run makes zero Cloudflare API calls.
			//
			// The DNS record is declared UNCONDITIONALLY whenever customDomain is
			// set. It must never drop out of the program: once a deploy has
			// created it, a program that omits it plans a DELETE of the live
			// record — and planning that delete forces the (default) cloudflare
			// provider to configure, which fails on a token-less preview
			// ("must provide apiToken"). A genuine token-less *apply* still fails
			// fast here.
			token := os.Getenv("CLOUDFLARE_API_TOKEN")
			// A "real" token is anything other than empty or the advisory-preview
			// placeholder. The zone LOOKUP (a live API call) must key off THIS,
			// not ctx.DryRun(): a real `pulumi up` also evaluates a DryRun preview
			// pass, and gating the lookup on DryRun made that pass fall back to a
			// placeholder zone id — showing a spurious `~zoneId` REPLACE of the
			// live record on every deploy (the apply pass then re-resolved and
			// no-op'd it). Keying off the real token keeps both passes of a deploy
			// consistent (no phantom replace) while the advisory preview, which
			// has only the placeholder, still skips the API call.
			tokenIsReal := token != "" && token != cfPreviewToken
			if !tokenIsReal && !ctx.DryRun() {
				return fmt.Errorf("customDomain %q is set but CLOUDFLARE_API_TOKEN is empty: the deploy fetches it from the CLOUDFLARE_API_TOKEN secret in the dev floating project's Secret Manager (Cloudflare token with Zone.Read + DNS.Edit on the zone; see _deploy-cloud-run.yaml cloudflare-token-secret-project)", customDomain)
			}
			// Zone id resolution, in order:
			//  1. the pinned cloudflareZoneId config — used directly in BOTH the
			//     preview and the deploy, so neither shows a phantom replace. A
			//     Cloudflare zone id is not a secret (it appears in the dashboard
			//     URL and in every preview diff), so it is committed; this is the
			//     path the live stacks take.
			//  2. otherwise a live LookupZone by name — only a real token can call
			//     the API, so the advisory preview (placeholder token) can't use it.
			//  3. otherwise a placeholder id that keeps the record in the plan
			//     without an API call (advisory preview of an un-pinned zone only).
			zone := cfg.Get("cloudflareZone")
			if zone == "" {
				zone = "ipv1337.dev"
			}
			zoneID := cfg.Get("cloudflareZoneId")
			if zoneID == "" {
				zoneID = zone
				if !tokenIsReal {
					zoneID = "preview-unresolved-zone-id"
				} else if strings.Contains(zone, ".") {
					looked, err := cloudflare.LookupZone(ctx, &cloudflare.LookupZoneArgs{Name: &zone})
					if err != nil {
						return fmt.Errorf("resolving cloudflare zone %q: %w", zone, err)
					}
					zoneID = looked.Id
				}
			}
			if _, err := cloudflare.NewRecord(ctx, "oauth-user-inspector-dns", &cloudflare.RecordArgs{
				ZoneId:  pulumi.String(zoneID),
				Name:    pulumi.String(customDomain),
				Type:    pulumi.String("CNAME"),
				Content: dnsTarget,
				Ttl:     pulumi.Int(300),
				Proxied: pulumi.Bool(false),
			}, pulumi.DependsOn([]pulumi.Resource{mapping})); err != nil {
				return err
			}
		}

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
