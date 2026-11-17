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

// Package dashboards reconciles organization-wide Sentry dashboards through
// Sentry's REST API, since pulumiverse/pulumi-sentry v0.0.9 does not expose
// dashboard resources.
package dashboards

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/pulumi/pulumi-command/sdk/go/command/local"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Layout defines a widget's grid position and dimensions on a 6-column Sentry dashboard.
type Layout struct {
	X    int `json:"x"`
	Y    int `json:"y"`
	W    int `json:"w"`
	H    int `json:"h"`
	MinH int `json:"minH"`
}

// Query defines a single Discover/error-events query inside a widget.
type Query struct {
	Name       string   `json:"name"`
	Conditions string   `json:"conditions"`
	Fields     []string `json:"fields"`
	Aggregates []string `json:"aggregates"`
	Columns    []string `json:"columns"`
	Orderby    string   `json:"orderby"`
}

// Widget defines a single panel on a Sentry dashboard.
type Widget struct {
	Title       string  `json:"title"`
	DisplayType string  `json:"displayType"`
	Interval    string  `json:"interval,omitempty"`
	Limit       int     `json:"limit,omitempty"`
	WidgetType  string  `json:"widgetType"`
	Layout      Layout  `json:"layout"`
	Queries     []Query `json:"queries"`
}

// Dashboard defines a Sentry organization dashboard payload.
type Dashboard struct {
	Title   string   `json:"title"`
	Widgets []Widget `json:"widgets"`
}

// DashboardsURL returns the organization dashboards API endpoint.
func DashboardsURL(baseURL, org string) string {
	return strings.TrimRight(baseURL, "/") + "/0/organizations/" + org + "/dashboards/"
}

// DefaultDashboards returns the standard Vitruvian Sentry dashboards.
func DefaultDashboards() []Dashboard {
	serviceProjects := "project:[backstage,oauth-user-inspector,vitruviansoftware-dev,vitruvian-tabs,vitruvian-relay,vitruvian-slack-mcp,vitruvian-roborock-mcp,vitruvian-wand]"
	clientProjects := "project:[vitruvian-code,vitruvian-atrium,vitruvian-speaker,vitruvian-courier,vitruvian-remote,vitruvian-watch,vitruvian-devx,vitruvian-homelab,ostation,vitruvian-github,vitruvian-tv]"

	return []Dashboard{
		{
			Title: "Vitruvian Platform Overview",
			Widgets: []Widget{
				{
					Title:       "Errors Over Time",
					DisplayType: "area",
					Interval:    "1h",
					WidgetType:  "error-events",
					Layout:      Layout{X: 0, Y: 0, W: 3, H: 2, MinH: 2},
					Queries: []Query{{
						Fields:     []string{"count()"},
						Aggregates: []string{"count()"},
						Columns:    []string{},
					}},
				},
				{
					Title:       "Errors by Project",
					DisplayType: "bar",
					Interval:    "1d",
					Limit:       10,
					WidgetType:  "error-events",
					Layout:      Layout{X: 3, Y: 0, W: 3, H: 2, MinH: 2},
					Queries: []Query{{
						Fields:     []string{"project", "count()"},
						Aggregates: []string{"count()"},
						Columns:    []string{"project"},
						Orderby:    "-count()",
					}},
				},
				{
					Title:       "Unresolved Issues",
					DisplayType: "table",
					WidgetType:  "error-events",
					Layout:      Layout{X: 0, Y: 2, W: 4, H: 3, MinH: 2},
					Queries: []Query{{
						Conditions: "is:unresolved",
						Fields:     []string{"issue", "project", "count()"},
						Aggregates: []string{"count()"},
						Columns:    []string{"issue", "project"},
						Orderby:    "-count()",
					}},
				},
				{
					Title:       "Events by Environment",
					DisplayType: "bar",
					Interval:    "1d",
					Limit:       10,
					WidgetType:  "error-events",
					Layout:      Layout{X: 4, Y: 2, W: 2, H: 3, MinH: 2},
					Queries: []Query{{
						Fields:     []string{"environment", "count()"},
						Aggregates: []string{"count()"},
						Columns:    []string{"environment"},
						Orderby:    "-count()",
					}},
				},
				{
					Title:       "Unhandled Crashes & Panics",
					DisplayType: "table",
					WidgetType:  "error-events",
					Layout:      Layout{X: 0, Y: 5, W: 3, H: 3, MinH: 2},
					Queries: []Query{{
						Conditions: "is:unresolved error.unhandled:true",
						Fields:     []string{"issue", "project", "count()"},
						Aggregates: []string{"count()"},
						Columns:    []string{"issue", "project"},
						Orderby:    "-count()",
					}},
				},
				{
					Title:       "Top Releases by Error Count",
					DisplayType: "table",
					WidgetType:  "error-events",
					Layout:      Layout{X: 3, Y: 5, W: 3, H: 3, MinH: 2},
					Queries: []Query{{
						Fields:     []string{"release", "count()", "count_unique(user)"},
						Aggregates: []string{"count()", "count_unique(user)"},
						Columns:    []string{"release"},
						Orderby:    "-count()",
					}},
				},
			},
		},
		{
			Title: "Backend, Web & MCP Health",
			Widgets: []Widget{
				{
					Title:       "Service & Web Error Trend",
					DisplayType: "area",
					Interval:    "1h",
					WidgetType:  "error-events",
					Layout:      Layout{X: 0, Y: 0, W: 3, H: 2, MinH: 2},
					Queries: []Query{{
						Conditions: serviceProjects,
						Fields:     []string{"count()"},
						Aggregates: []string{"count()"},
						Columns:    []string{},
					}},
				},
				{
					Title:       "Errors by Service",
					DisplayType: "bar",
					Interval:    "1d",
					Limit:       10,
					WidgetType:  "error-events",
					Layout:      Layout{X: 3, Y: 0, W: 3, H: 2, MinH: 2},
					Queries: []Query{{
						Conditions: serviceProjects,
						Fields:     []string{"project", "count()"},
						Aggregates: []string{"count()"},
						Columns:    []string{"project"},
						Orderby:    "-count()",
					}},
				},
				{
					Title:       "Active Service Issues",
					DisplayType: "table",
					WidgetType:  "error-events",
					Layout:      Layout{X: 0, Y: 2, W: 3, H: 3, MinH: 2},
					Queries: []Query{{
						Conditions: "is:unresolved " + serviceProjects,
						Fields:     []string{"issue", "project", "count()"},
						Aggregates: []string{"count()"},
						Columns:    []string{"issue", "project"},
						Orderby:    "-count()",
					}},
				},
				{
					Title:       "Error & Fatal Events",
					DisplayType: "table",
					WidgetType:  "error-events",
					Layout:      Layout{X: 3, Y: 2, W: 3, H: 3, MinH: 2},
					Queries: []Query{{
						Conditions: "is:unresolved level:[error,fatal] " + serviceProjects,
						Fields:     []string{"title", "project", "count()"},
						Aggregates: []string{"count()"},
						Columns:    []string{"title", "project"},
						Orderby:    "-count()",
					}},
				},
			},
		},
		{
			Title: "Desktop, Mobile, CLIs & Extensions",
			Widgets: []Widget{
				{
					Title:       "Client & CLI Error Trend",
					DisplayType: "area",
					Interval:    "1h",
					WidgetType:  "error-events",
					Layout:      Layout{X: 0, Y: 0, W: 3, H: 2, MinH: 2},
					Queries: []Query{{
						Conditions: clientProjects,
						Fields:     []string{"count()"},
						Aggregates: []string{"count()"},
						Columns:    []string{},
					}},
				},
				{
					Title:       "Errors by App",
					DisplayType: "bar",
					Interval:    "1d",
					Limit:       10,
					WidgetType:  "error-events",
					Layout:      Layout{X: 3, Y: 0, W: 3, H: 2, MinH: 2},
					Queries: []Query{{
						Conditions: clientProjects,
						Fields:     []string{"project", "count()"},
						Aggregates: []string{"count()"},
						Columns:    []string{"project"},
						Orderby:    "-count()",
					}},
				},
				{
					Title:       "Active Client & CLI Issues",
					DisplayType: "table",
					WidgetType:  "error-events",
					Layout:      Layout{X: 0, Y: 2, W: 3, H: 3, MinH: 2},
					Queries: []Query{{
						Conditions: "is:unresolved " + clientProjects,
						Fields:     []string{"issue", "project", "count()"},
						Aggregates: []string{"count()"},
						Columns:    []string{"issue", "project"},
						Orderby:    "-count()",
					}},
				},
				{
					Title:       "Top Client & CLI Releases",
					DisplayType: "table",
					WidgetType:  "error-events",
					Layout:      Layout{X: 3, Y: 2, W: 3, H: 3, MinH: 2},
					Queries: []Query{{
						Conditions: clientProjects,
						Fields:     []string{"release", "count()"},
						Aggregates: []string{"count()"},
						Columns:    []string{"release"},
						Orderby:    "-count()",
					}},
				},
			},
		},
	}
}

// Body serializes the dashboard payload to JSON.
func Body(d Dashboard) (string, error) {
	b, err := json.Marshal(d)
	if err != nil {
		return "", fmt.Errorf("marshaling dashboard %q: %w", d.Title, err)
	}
	return string(b), nil
}

// script idempotently creates or updates a Sentry dashboard matched by title.
const script = `set -eu
token="${SENTRY_TOKEN:-${SENTRY_AUTH_TOKEN:-}}"
[ -n "$token" ] || { echo "SENTRY_TOKEN or SENTRY_AUTH_TOKEN must be set" >&2; exit 1; }
python3 - "$token" <<'PY'
import json, os, sys, urllib.request

token = sys.argv[1]
url = os.environ["SENTRY_DASHBOARDS_URL"]
payload = json.loads(os.environ["SENTRY_DASHBOARD_BODY"])
title = payload["title"]

req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
with urllib.request.urlopen(req, timeout=20) as resp:
    existing = json.loads(resp.read())

match = next((d for d in existing if d.get("title") == title), None)
target_url = f"{url}{match['id']}/" if match else url
method = "PUT" if match else "POST"

up = urllib.request.Request(
    target_url,
    data=json.dumps(payload).encode(),
    headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    method=method,
)
with urllib.request.urlopen(up, timeout=20) as resp:
    out = json.loads(resp.read())
    if not out.get("id"):
        raise RuntimeError(f"Sentry did not return a dashboard id for {title}")
PY
`

// Reconcile ensures all DefaultDashboards exist and match their declared definitions.
func Reconcile(ctx *pulumi.Context, baseURL, org string, opts ...pulumi.ResourceOption) ([]*local.Command, error) {
	url := DashboardsURL(baseURL, org)
	defs := DefaultDashboards()
	cmds := make([]*local.Command, 0, len(defs))

	for i, d := range defs {
		body, err := Body(d)
		if err != nil {
			return nil, err
		}
		name := fmt.Sprintf("sentry-dashboard-%d", i+1)
		cmd, err := local.NewCommand(ctx, name, &local.CommandArgs{
			Create:      pulumi.String(script),
			Update:      pulumi.String(script),
			Interpreter: pulumi.StringArray{pulumi.String("/bin/sh"), pulumi.String("-c")},
			Environment: pulumi.StringMap{
				"SENTRY_DASHBOARDS_URL": pulumi.String(url),
				"SENTRY_DASHBOARD_BODY": pulumi.String(body),
			},
			Triggers: pulumi.Array{pulumi.String(url), pulumi.String(body)},
		}, opts...)
		if err != nil {
			return nil, fmt.Errorf("reconciling Sentry dashboard %q: %w", d.Title, err)
		}
		cmds = append(cmds, cmd)
	}
	return cmds, nil
}
