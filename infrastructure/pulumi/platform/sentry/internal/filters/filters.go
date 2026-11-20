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

// Package filters configures Sentry inbound event filters across projects
// (crawler noise, browser extensions, legacy browsers) via Sentry's REST API.
package filters

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/sentry/internal/config"
	"github.com/pulumi/pulumi-command/sdk/go/command/local"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// ProjectFilters maps a project slug to the inbound filter IDs to enable.
type ProjectFilters map[string][]string

// DesiredForProjects computes which inbound filters should be enabled per project.
func DesiredForProjects(projects []config.ProjectConfig) ProjectFilters {
	webSlugs := map[string]bool{
		"backstage":             true,
		"oauth-user-inspector":  true,
		"vitruvian-tabs":        true,
		"vitruviansoftware-dev": true,
	}
	out := make(ProjectFilters, len(projects))
	for _, p := range projects {
		ids := []string{"web-crawlers"}
		if webSlugs[p.Slug] {
			ids = append(ids, "browser-extensions", "legacy-browsers")
		}
		out[p.Slug] = ids
	}
	return out
}

// FiltersBaseURL returns the base project API URL prefix.
func FiltersBaseURL(baseURL, org string) string {
	return strings.TrimRight(baseURL, "/") + "/0/projects/" + org + "/"
}

const script = `set -eu
token="${SENTRY_TOKEN:-${SENTRY_AUTH_TOKEN:-}}"
[ -n "$token" ] || { echo "SENTRY_TOKEN or SENTRY_AUTH_TOKEN must be set" >&2; exit 1; }
python3 - "$token" <<'PY'
import json, os, sys, urllib.request

token = sys.argv[1]
base = os.environ["SENTRY_FILTERS_BASE_URL"]
desired = json.loads(os.environ["SENTRY_FILTERS_MAP"])

for slug, filter_ids in desired.items():
    for fid in filter_ids:
        req = urllib.request.Request(
            f"{base}{slug}/filters/{fid}/",
            data=b'{"active":true}',
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
            method="PUT",
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            if resp.status not in (200, 204):
                raise RuntimeError(f"filter {fid} on {slug} returned {resp.status}")
PY
`

// Reconcile enables inbound noise filters for all declared Sentry projects.
func Reconcile(ctx *pulumi.Context, baseURL, org string, projects []config.ProjectConfig, opts ...pulumi.ResourceOption) (*local.Command, error) {
	base := FiltersBaseURL(baseURL, org)
	desired := DesiredForProjects(projects)
	body, err := json.Marshal(desired)
	if err != nil {
		return nil, fmt.Errorf("marshaling project filters: %w", err)
	}
	// No Triggers: a change to them REPLACES the command, and the Sentry
	// apply's plan guard refuses any replace, so every new project tripped it
	// (mini-party, 2026-11-20). The same values sit in Environment, and a
	// change there runs Update, the same idempotent script, as an update.
	// IgnoreChanges on "triggers" keeps the value already in state, so
	// dropping them is not itself a replace.
	opts = append(opts, pulumi.IgnoreChanges([]string{"triggers"}))
	cmd, err := local.NewCommand(ctx, "sentry-project-filters", &local.CommandArgs{
		Create:      pulumi.String(script),
		Update:      pulumi.String(script),
		Interpreter: pulumi.StringArray{pulumi.String("/bin/sh"), pulumi.String("-c")},
		Environment: pulumi.StringMap{
			"SENTRY_FILTERS_BASE_URL": pulumi.String(base),
			"SENTRY_FILTERS_MAP":      pulumi.String(string(body)),
		},
	}, opts...)
	if err != nil {
		return nil, fmt.Errorf("reconciling Sentry inbound filters: %w", err)
	}
	return cmd, nil
}
