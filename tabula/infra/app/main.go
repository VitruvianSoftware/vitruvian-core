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

// Package main is the per-environment tabula app stack on the
// vitruviansoftware.dev foundation (stage-5 "application stage", spec
// docs/superpowers/specs/2026-07-10-oss-application-stage-design.md).
//
// Each stack (development / nonproduction / production) deploys the app into
// the env's prj-{env}-bu2-oss-floating project as a Cloud Run v2 service,
// composed from the published pkg/cloud_run primitive — mirroring the
// serverless_space reference module's shape (runtime SA + SECRET_PREFIX env +
// opt-in allUsers invoker) without depending on the example tree.
//
// Build-once, promote-by-digest: the image is built ONCE by the build job
// (GitHub environment tabula-build) into the shared Artifact
// Registry in the infra-pipeline project, and every env deploys the SAME
// immutable @sha256 digest ref (never a mutable :tag). The digest arrives as
// the per-invocation TABULA_IMAGE_DIGEST env var (or the
// imageDigest config for a local break-glass run). The app's own Artifact
// Registry repository is gone — the shared repo is owned by the
// tabula-build stack.
//
// The allUsers run.invoker binding relies on the org's project-scoped
// domain-restricted-sharing override on the oss projects (gcp-org
// oss_public_invoker_projects, PR #867) — the app is a public demo tool.
//
// Runs as the per-env deploy SA (tabula-deploy@<oss project>,
// minted by the sibling tabula-deploy-identity stack) via the
// tabula-<env> GitHub Environment.
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"sort"
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
const secretPrefix = "TABULA_"

const digestMarker = "@sha256:"

// cfPreviewToken is the non-secret placeholder value pulumi-preview.yaml injects
// as CLOUDFLARE_API_TOKEN for the advisory preview (matrix.cfPreviewToken).
// It lets the default cloudflare provider CONFIGURE without a real credential;
// the code treats it as "not a real token" so it never calls the Cloudflare API
// with it. Keep this in sync with pulumi-preview.yaml.
const cfPreviewToken = "preview-only-not-a-real-cloudflare-token"

// revisionNameFor derives the Cloud Run revision name from the image digest AND
// the rendered environment.
//
// A revision is immutable and its name identifies image + config TOGETHER. The
// digest alone is not enough: build-once/promote-by-digest means one image is
// deployed to three envs, and any config change to that image produces
// different revision CONTENT under an identical name, which the API rejects:
//
//	Error 409: Revision named 'tabula-api-development-1c144786' with different
//	configuration already exists.
//
// Hashing the env in keeps the name deterministic — the deploy runs `pulumi up`
// twice (deploy, then promote) and must address the SAME revision both times,
// as must a rerun after a transient failure — while still changing whenever the
// content does. Keys are sorted so Go's randomized map iteration cannot make the
// name unstable, and the separators are bytes that cannot occur in an env name,
// so {AB=C} and {A=BC} cannot collide.
func revisionNameFor(serviceName, shortDigest string, env map[string]string) string {
	keys := make([]string, 0, len(env))
	for k := range env {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	h := sha256.New()
	for _, k := range keys {
		h.Write([]byte(k))
		h.Write([]byte{0})
		h.Write([]byte(env[k]))
		h.Write([]byte{0})
	}
	// 6 hex chars: this only has to distinguish the handful of configs a single
	// image is ever deployed with, and the name has a 63-char budget it shares
	// with the service-name prefix.
	configHash := hex.EncodeToString(h.Sum(nil))[:6]

	return fmt.Sprintf("%s-%s-%s", serviceName, shortDigest, configHash)
}

// envMap builds the plain (non-secret) environment for the service.
//
// apiURL and postMessageOrigin are both PUBLIC values (a URL and a
// chrome-extension:// origin), and both are load-bearing for the extension
// login flow — see the per-key comments at the call site. Empty means ABSENT
// rather than empty-string, so an unconfigured env is visible as a missing key
// instead of an empty one.
func envMap(project, apiURL, postMessageOrigin string) map[string]string {
	env := map[string]string{
		"NODE_ENV":             "production",
		"GOOGLE_CLOUD_PROJECT": project,
		"SECRET_PREFIX":        secretPrefix,
	}
	if apiURL != "" {
		env["API_URL"] = apiURL
	}
	if postMessageOrigin != "" {
		env["AUTH_POSTMESSAGE_ORIGIN"] = postMessageOrigin
	}
	return env
}

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "tabula-app")
		project := cfg.Require("project") // the env's oss-floating project id
		region := cfg.Get("region")
		if region == "" {
			region = "us-central1"
		}
		env := cfg.Require("environment")
		runtimeSA := cfg.Require("runtimeServiceAccount")

		// Immutable digest ref into the SHARED build Artifact Registry, e.g.
		//   us-central1-docker.pkg.dev/<infra-pipeline proj>/tabula/app@sha256:...
		// There is deliberately no mutable-tag fallback: deploying anything but a
		// pinned digest would break build-once/promote-digest.
		imageDigest := envOrConfig("TABULA_IMAGE_DIGEST", cfg, "imageDigest")
		if imageDigest == "" {
			if !ctx.DryRun() {
				return fmt.Errorf("an image digest ref is required: set TABULA_IMAGE_DIGEST (CI) or the imageDigest config to <ar>/app@sha256:...")
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
		// Cloud Run REQUIRES a revision name to be prefixed with its service
		// name; `tabula-<env>-<sha>` against service `tabula-api-<env>` is
		// rejected with `spec.traffic.revision_name[0]: ... invalid`. Derive both
		// from one serviceName so they cannot drift apart again.
		serviceName := fmt.Sprintf("tabula-api-%s", env)
		// The env is part of the revision's identity, not just the image — see
		// revisionNameFor. Rendered once here so the name and the deployed
		// container are hashed from the SAME map and cannot drift.
		serviceEnv := envMap(project, cfg.Get("apiUrl"), cfg.Get("authPostmessageOrigin"))
		revisionName := revisionNameFor(serviceName, shortDigest, serviceEnv)

		promote := envOrConfigBool("TABULA_PROMOTE", cfg, "promote")
		stableRevision := envOrConfig("TABULA_STABLE_REVISION", cfg, "stableRevision")

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

		app, err := cloud_run.NewCloudRun(ctx, "tabula", &cloud_run.CloudRunArgs{
			ProjectID:           pulumi.String(project),
			Region:              region,
			Name:                serviceName,
			Image:               pulumi.String(imageDigest),
			ServiceAccountEmail: pulumi.String(runtimeSA),
			// NODE_ENV/GOOGLE_CLOUD_PROJECT/SECRET_PREFIX are all the app needs
			// as plain config: every credential is resolved lazily from Secret
			// Manager under SECRET_PREFIX (tabula/api/src/lib/secrets.ts), NOT
			// injected via secretKeyRef — which is what lets a revision be
			// created before its secrets exist.
			//
			// API_URL is the public base the app builds its WorkOS redirect URI
			// from (auth.service.ts: `${API_URL}/auth/callback`), so it must
			// match a URI registered in the WorkOS dashboard for this env —
			// WorkOS rejects an unregistered redirect_uri outright. Unset, the
			// app falls back to localhost, which fails loudly rather than
			// silently authenticating against the wrong environment.
			//
			// AUTH_POSTMESSAGE_ORIGIN is the EXACT origin the auth callback
			// page postMessages the token to (auth.routes.ts
			// resolvePostMessageOrigin) — the extension's chrome-extension://
			// origin, never '*', so the token is never delivered to an
			// arbitrary opener. Unset, it falls back to http://localhost:3000
			// and the extension's opener never receives the token at all.
			//
			// Both were set by the retired infrastructure/pulumi/apps/tabula
			// stack and were dropped in the bu2 rewrite; neither is a secret.
			Env:          serviceEnv,
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
		if _, err := cloudrunv2.NewServiceIamMember(ctx, "tabula-public", &cloudrunv2.ServiceIamMemberArgs{
			Project:  pulumi.String(project),
			Location: pulumi.String(region),
			Name:     app.Service.Name,
			Role:     pulumi.String("roles/run.invoker"),
			Member:   pulumi.String("allUsers"),
		}); err != nil {
			return err
		}

		// Optional per-env custom domain (config `customDomain`, e.g.
		// tabula-api.vitruviansoftware.dev): a Cloud Run DomainMapping (v1 API —
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
			mapping, err := cloudrun.NewDomainMapping(ctx, "tabula-domain", &cloudrun.DomainMappingArgs{
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
					RouteName: app.Service.Name,
					// Take over the domain if it is still mapped elsewhere
					// (e.g. a hostname still mapped to a
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
			// tabula is a COMMERCIAL app and lives on vitruviansoftware.dev;
			// ipv1337.dev is reserved for the open-source apps. The default
			// matters: a config miss must not silently publish a paid-tier
			// hostname into the OSS zone.
			zone := cfg.Get("cloudflareZone")
			if zone == "" {
				zone = "vitruviansoftware.dev"
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
			if _, err := cloudflare.NewRecord(ctx, "tabula-dns", &cloudflare.RecordArgs{
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
