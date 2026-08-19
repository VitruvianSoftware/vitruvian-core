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

// Package cluster_reader grants read-only GCP access to identities that live
// OUTSIDE this foundation -- specifically, workloads in the homelab Kubernetes
// cluster that federate in via the workload identity provider built by
// gcp-bootstrap (see docs/gcp-cluster-federation.md).
//
// WHY THE GRANT LIVES HERE AND NOT IN gcp-bootstrap
// -------------------------------------------------
// gcp-bootstrap creates the identity; it deliberately grants it nothing. Roles
// on a project belong to the stage that owns that project, so the foundation's
// stage 0 never quietly accumulates authority over workloads it does not
// manage. That split is what makes the identity safe to create early and grant
// late.
//
// WHY READ-ONLY IS ENFORCED HERE RATHER THAN DOCUMENTED
// -----------------------------------------------------
// The whole point of this identity is that a Backstage or Grafana card can
// answer "what is live and is it healthy". Nothing about that needs write
// access, and the roles are validated against an allowlist below rather than
// passed straight through: a future config edit that adds roles/run.admin
// fails the apply instead of silently handing a browser-facing service the
// ability to deploy.
package cluster_reader

import (
	"fmt"
	"sort"
	"strings"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// allowedRoles is the complete set this module will grant. Deliberately narrow:
// every entry is a *.viewer with no mutating permission.
var allowedRoles = map[string]bool{
	"roles/run.viewer":        true,
	"roles/monitoring.viewer": true,
}

type Args struct {
	// ProjectID is the project whose resources become readable.
	ProjectID pulumi.StringOutput
	// Members are fully-qualified IAM members (e.g. "serviceAccount:x@y.iam...").
	Members []string
	// Roles to grant. Must all be in allowedRoles.
	Roles []string
}

// Deploy grants each member each role on the project. It is a no-op when no
// members are configured, so the whole feature stays absent until switched on.
func Deploy(ctx *pulumi.Context, name string, args *Args) error {
	if len(args.Members) == 0 {
		return nil
	}
	if len(args.Roles) == 0 {
		return fmt.Errorf("cluster_reader %q: members are configured but no roles were given", name)
	}

	for _, role := range args.Roles {
		if !allowedRoles[role] {
			return fmt.Errorf(
				"cluster_reader %q: role %q is not read-only; allowed roles are %s",
				name, role, strings.Join(sortedAllowedRoles(), ", "),
			)
		}
	}
	for _, m := range args.Members {
		if !strings.Contains(m, ":") {
			return fmt.Errorf(
				"cluster_reader %q: member %q is missing its type prefix (want e.g. serviceAccount:...)",
				name, m,
			)
		}
	}

	// Stable iteration: a map here would reorder between applies and show a
	// spurious diff on every preview.
	for _, m := range args.Members {
		for _, role := range args.Roles {
			// One binding per (member, role). IAMMember rather than IAMBinding:
			// IAMBinding is AUTHORITATIVE for the role and would strip every
			// other member that happens to hold it on this project.
			resName := fmt.Sprintf("%s-%s-%s", name, sanitizeMember(m), sanitizeRole(role))
			if _, err := projects.NewIAMMember(ctx, resName, &projects.IAMMemberArgs{
				Project: args.ProjectID,
				Role:    pulumi.String(role),
				Member:  pulumi.String(m),
			}); err != nil {
				return fmt.Errorf("granting %s to %s: %w", role, m, err)
			}
		}
	}
	return nil
}

func sortedAllowedRoles() []string {
	out := make([]string, 0, len(allowedRoles))
	for r := range allowedRoles {
		out = append(out, r)
	}
	sort.Strings(out)
	return out
}

// sanitizeMember/sanitizeRole turn IAM strings into stable Pulumi resource-name
// components. Two different members must not collapse to the same name, or the
// second binding would silently replace the first.
func sanitizeMember(m string) string {
	return strings.NewReplacer(":", "-", "@", "-at-", ".", "-").Replace(m)
}

func sanitizeRole(r string) string {
	return strings.NewReplacer("roles/", "", ".", "-").Replace(r)
}
