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

// Package site_domain declares how the vitruviansoftware.dev website is
// published on its own root domain: the Cloudflare records that point the
// apex at GitHub Pages and prove the domain to GitHub, and the Pages setting
// on the website's mirror repository.
//
// WHY THIS IS HERE AND NOT IN A PER-APP STACK. The other apps put their own
// hostnames in a per-app stack under <app>/infra/. Those are subdomains. This
// is the ROOT of a zone that is also the organisation's identity domain (mail,
// SPF, Workspace verification), so it is owned at the platform level, and
// repo-config is the platform stack that is already applied through CI, gated
// and previewed on every pull request.
//
// WHAT IT OWNS, AND DELIBERATELY NOTHING ELSE. Three records and one setting.
// The zone also holds MX, SPF, DKIM and Google verification records, records
// written by external-dns, records written by the tabula stacks and by
// tools/ci/ensure-site-verification.sh, and another GitHub account's Pages
// verification. None of those is declared here, and TestOwnsOnlyTheSiteRecords
// fails if one ever is.
//
// ADOPTION. Everything but www already existed (it was made by hand, before
// this repo had Pulumi), so each is imported by id. Every resource is
// protected: a mistaken edit that would delete or replace one fails the run
// instead of taking the site down.
//
// DORMANT UNTIL SWITCHED ON. The package does nothing unless SITE_DOMAIN_MANAGED
// is "true". Once on it must stay on: in Pulumi a resource that is not declared
// is deleted, and protect turns that into a failed run rather than a deleted
// record.
package site_domain

import (
	"fmt"
	"os"

	"github.com/pulumi/pulumi-cloudflare/sdk/v5/go/cloudflare"
	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const (
	// Switch is the environment variable that turns this package on.
	Switch = "SITE_DOMAIN_MANAGED"

	// ZoneID is the Cloudflare zone for vitruviansoftware.dev. A zone id is not
	// a credential: it is in the dashboard URL and in every preview diff.
	ZoneID = "fa827eb1be98b4f6059cf34f90c64774"

	// Apex is the website's root domain.
	Apex = "vitruviansoftware.dev"

	// MirrorRepo is the repository GitHub Pages builds and serves the site from.
	MirrorRepo = "site-vitruviansoftware-dev"

	challengePrefix = "_github-pages-challenge-"
)

// Record is one DNS record this package owns.
type Record struct {
	// Resource is the Pulumi resource name. It is part of the resource's
	// identity: renaming it plans a replace, so it is fixed.
	Resource string
	// ID is the Cloudflare record id, used once to adopt the live record. It
	// is empty for a record this package creates (www).
	ID      string
	Type    string
	Name    string
	Content string
	// TTL is in seconds; 1 means "automatic" in Cloudflare.
	TTL int
	// Proxied routes the hostname through Cloudflare, which then presents its
	// own certificate for it. Only www sets it; see its entry below.
	Proxied bool
}

// Records is the whole DNS surface of this package.
//
// The apex is a CNAME, not A and AAAA records. Cloudflare flattens a CNAME at
// the zone apex, so a resolver sees GitHub's eight Pages addresses. GitHub
// routes by the custom domain and not by the CNAME target, so the target only
// has to resolve to Pages.
//
// It points at this organisation's own Pages hostname. It was adopted pointing
// at another GitHub account's (bluecentre.github.io), imported unchanged so the
// first apply changed nothing, and repointed afterwards as its own edit. Both
// names resolve to the same eight addresses, which is why the move is safe.
func Records() []Record {
	return []Record{
		{
			Resource: "site-apex-cname",
			ID:       "a3e45075c39e5ff202f1db62ffbcb733",
			Type:     "CNAME",
			Name:     Apex,
			Content:  "vitruviansoftware.github.io",
			TTL:      1,
		},
		{
			// GitHub's org-level proof that VitruvianSoftware controls the
			// domain. The other account's challenge record in the same zone is
			// not ours and is not declared.
			Resource: "site-pages-challenge-txt",
			ID:       "a5cbbbe453e1c52e205e57b66bb82749",
			Type:     "TXT",
			// Relative to the zone. The provider stores an imported record's name
			// without the zone suffix, so the fully qualified form reads as a
			// change of name and plans a REPLACE (which protect then blocks).
			Name:    challengePrefix + "vitruviansoftware",
			Content: "02d06225bae50f50c8258a17eae46b",
			TTL:     1,
		},
		{
			// www. A CNAME to the organisation's Pages hostname. With the apex
			// as the custom domain GitHub answers www with a 301 to the apex,
			// preserving the path. It did not exist before 2026-10-12, so it is
			// created, not imported (no ID).
			//
			// PROXIED, unlike the apex. GitHub never added www to the site's
			// certificate (18+ hours, a re-save and a remove/re-add later), so a
			// browser failed the TLS handshake before it could be redirected. A
			// redirect needs a connection first. Proxied, Cloudflare terminates
			// TLS with its own certificate and GitHub's 301 passes through.
			// Only www is proxied: the apex must stay DNS-only so GitHub can
			// issue and renew its certificate.
			Resource: "site-www-cname",
			Type:     "CNAME",
			Name:     "www",
			Content:  "vitruviansoftware.github.io",
			TTL:      1,
			Proxied:  true,
		},
	}
}

// Enabled reports whether the switch is on.
func Enabled() bool { return os.Getenv(Switch) == "true" }

// Manage declares the records and the Pages setting, or nothing when the
// switch is off.
func Manage(ctx *pulumi.Context) error {
	if !Enabled() {
		return nil
	}
	// Name the missing input. Left to the Cloudflare provider this surfaces as
	// "must provide exactly one of apiKey, apiToken...", on a run that has
	// nothing to do with DNS to a reader of the log. A preview that does not
	// hold the real token is given a non-empty placeholder by its workflow, so
	// it does not reach this.
	if os.Getenv("CLOUDFLARE_API_TOKEN") == "" {
		return fmt.Errorf("%s is true but CLOUDFLARE_API_TOKEN is empty: the "+
			"DNS_CLOUDFLARE_API_TOKEN repo secret has not been set. Store it "+
			"first (docs/operations/key-rotation.md); refusing to run, because "+
			"not declaring the site's records would plan to delete them", Switch)
	}

	for _, r := range Records() {
		opts := []pulumi.ResourceOption{pulumi.Protect(true)}
		if r.ID != "" {
			opts = append(opts, pulumi.Import(pulumi.ID(ZoneID+"/"+r.ID)))
		}
		_, err := cloudflare.NewRecord(
			ctx, r.Resource, &cloudflare.RecordArgs{
				ZoneId:  pulumi.String(ZoneID),
				Name:    pulumi.String(r.Name),
				Type:    pulumi.String(r.Type),
				Content: pulumi.String(r.Content),
				Ttl:     pulumi.Int(r.TTL),
				// DNS-only unless the record says otherwise: GitHub Pages must
				// see the request itself to issue and renew the apex's
				// certificate, and proxying the apex would break that.
				Proxied: pulumi.Bool(r.Proxied),
			},
			opts...,
		)
		if err != nil {
			return err
		}
	}

	_, err := github.NewRepositoryPages(
		ctx, "site-pages", &github.RepositoryPagesArgs{
			Repository:    pulumi.String(MirrorRepo),
			BuildType:     pulumi.String("workflow"),
			Cname:         pulumi.String(Apex),
			HttpsEnforced: pulumi.Bool(true),
		},
		// The import id of this resource is the repository name.
		pulumi.Import(pulumi.ID(MirrorRepo)),
		pulumi.Protect(true),
	)
	return err
}
