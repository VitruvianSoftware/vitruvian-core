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

package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/VitruvianSoftware/pulumi-library/go/pkg/cloud_run"
	"github.com/VitruvianSoftware/vitruvian-core/tabula/infra/web/revision"
	"github.com/pulumi/pulumi-cloudflare/sdk/v5/go/cloudflare"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/cloudrun"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/cloudrunv2"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

const cfPreviewToken = "preview-only-not-a-real-cloudflare-token"

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "tabula-web")
		project := cfg.Require("project")
		region := cfg.Get("region")
		if region == "" {
			region = "us-central1"
		}
		env := cfg.Require("environment")
		runtimeSA := cfg.Require("runtimeServiceAccount")

		// Image digest — simpler than API (no revision hashing needed).
		imageDigest := os.Getenv("TABULA_WEB_IMAGE_DIGEST")
		if imageDigest == "" {
			imageDigest = cfg.Get("imageDigest")
		}
		if imageDigest == "" {
			if !ctx.DryRun() {
				return fmt.Errorf("image digest required: set TABULA_WEB_IMAGE_DIGEST")
			}
			imageDigest = "preview-placeholder@sha256:0000000000000000000000000000000000000000000000000000000000000000"
		}

		serviceName := fmt.Sprintf("tabula-web-%s", env)

		serviceEnv := map[string]string{
			"NODE_ENV": "production",
			"HOSTNAME": "0.0.0.0",
		}

		shortDigest, err := revision.ShortDigest(imageDigest)
		if err != nil {
			return err
		}
		revisionName := revision.Name(serviceName, shortDigest, serviceEnv)

		promote := envOrConfigBool("TABULA_WEB_PROMOTE", cfg, "promote")
		stableRevision := envOrConfig("TABULA_WEB_STABLE_REVISION", cfg, "stableRevision")

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

		// Cloud Run service — static site, no secrets, no migration.
		app, err := cloud_run.NewCloudRun(ctx, "tabula-web", &cloud_run.CloudRunArgs{
			ProjectID:           pulumi.String(project),
			Region:              pulumi.String(region),
			Name:                serviceName,
			Image:               pulumi.String(imageDigest),
			ServiceAccountEmail: pulumi.String(runtimeSA),
			RevisionName:        revisionName,
			Env:                 serviceEnv,
			Traffics:            traffics,
			MaxInstances:        5,
			Port:                8080,
		})
		if err != nil {
			return err
		}

		// Public: allUsers invoker.
		if _, err := cloudrunv2.NewServiceIamMember(ctx, "tabula-web-public", &cloudrunv2.ServiceIamMemberArgs{
			Project:  pulumi.String(project),
			Location: pulumi.String(region),
			Name:     app.Service.Name,
			Role:     pulumi.String("roles/run.invoker"),
			Member:   pulumi.String("allUsers"),
		}); err != nil {
			return err
		}

		ctx.Export("serviceUrl", app.Service.Uri)

		var routeName pulumi.StringInput = app.Service.Name

		// Optional per-env custom domain (config `customDomain`, e.g.
		// tabula.vitruviansoftware.dev): a Cloud Run DomainMapping (v1 API —
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
			// NOT pulumi.Import(...): that unconditionally tells Pulumi this
			// DomainMapping already exists in GCP and to adopt it, which is
			// only true for an env that has deployed before. It failed
			// outright on nonproduction's first-ever deploy: "resource
			// ...domainmappings/tabula.staging.vitruviansoftware.dev does not
			// exist". A plain create is correct for every env -- ForceOverride
			// below already handles "the domain exists but is mapped
			// elsewhere" (same mechanism tabula/infra/app's DomainMapping
			// relies on, which never used pulumi.Import at all). For
			// development, where this WAS already imported into state before
			// this fix, removing the option is safe: Pulumi's import is a
			// one-time directive for a resource not yet in state, a no-op
			// once it's already tracked there.
			mapping, err := cloudrun.NewDomainMapping(ctx, "tabula-web-domain", &cloudrun.DomainMappingArgs{
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
			if _, err := cloudflare.NewRecord(ctx, "tabula-web-dns", &cloudflare.RecordArgs{
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
