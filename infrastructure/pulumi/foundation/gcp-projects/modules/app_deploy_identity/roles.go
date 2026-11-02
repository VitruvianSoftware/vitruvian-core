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

// roles.go is the closed set of project-level roles this module will grant.
//
// The deploy and app-infra pipeline identities are reachable from CI, and the
// projects they deploy into are shared by co-tenant applications. So the set
// of project roles they may hold is an ALLOW-list, checked at program time:
// a role that is not listed here fails the preview with an error that names
// it, instead of reaching a live IAM policy.
//
// Roles that let a principal act as, mint tokens for, or manage service
// accounts are never granted at project level (where they would cover every
// service account in the project, including other applications' identities).
// The one such permission a deploy needs, acting as the runtime service
// account it sets on its Cloud Run services, is granted on those named
// accounts only (Args.ActAsServiceAccounts).

package app_deploy_identity

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
)

// allowedProjectRoles are the only UNCONDITIONED project-level roles a deploy
// or app-infra pipeline identity may hold: manage Cloud Run services, consume
// the project's enabled APIs, and read logs.
var allowedProjectRoles = map[string]bool{
	"roles/run.admin":                         true,
	"roles/serviceusage.serviceUsageConsumer": true,
	"roles/logging.viewer":                    true,
}

// allowedConditionalProjectRoles are the only project-level roles that may be
// granted WITH an IAM condition (the per-app Secret Manager prefix).
var allowedConditionalProjectRoles = map[string]bool{
	"roles/secretmanager.admin":          true,
	"roles/secretmanager.secretAccessor": true,
}

// actAsRole is the role granted on each named runtime service account.
const actAsRole = "roles/iam.serviceAccountUser"

// neverProjectWide are roles that must not appear in either allow-list. The
// allow-list alone already refuses them; this list exists so the tests can
// prove nobody widens the allow-list to include one.
var neverProjectWide = []string{
	"roles/owner",
	"roles/editor",
	"roles/iam.serviceAccountUser",
	"roles/iam.serviceAccountTokenCreator",
	"roles/iam.serviceAccountOpenIdTokenCreator",
	"roles/iam.workloadIdentityUser",
	"roles/iam.serviceAccountKeyAdmin",
	"roles/iam.serviceAccountAdmin",
	"roles/iam.serviceAccountCreator",
	"roles/iam.securityAdmin",
	"roles/iam.roleAdmin",
	"roles/iam.workloadIdentityPoolAdmin",
	"roles/resourcemanager.projectIamAdmin",
}

// neverProjectWidePrefixes catch whole families, so a role added later under
// the same prefix is refused without editing neverProjectWide.
var neverProjectWidePrefixes = []string{
	"roles/iam.",
	"roles/resourcemanager.",
}

// isNeverProjectWide reports whether role may never be granted at project level.
func isNeverProjectWide(role string) bool {
	for _, r := range neverProjectWide {
		if role == r {
			return true
		}
	}
	for _, p := range neverProjectWidePrefixes {
		if strings.HasPrefix(role, p) {
			return true
		}
	}
	return false
}

// validateProjectRoles refuses any unconditioned project role outside
// allowedProjectRoles. who names the identity in the error.
func validateProjectRoles(who string, roles []string) error {
	for _, role := range roles {
		if strings.HasPrefix(role, "roles/secretmanager.") {
			return fmt.Errorf(
				"%s: %q must be declared in ConditionalDeployRoles with a secret-prefix condition, not in DeployRoles: "+
					"an unconditioned Secret Manager grant reaches every co-tenant app's secrets in this shared project", who, role,
			)
		}
		if role == actAsRole {
			return fmt.Errorf(
				"%s: %q is not granted at project level; list the runtime service accounts this identity "+
					"deploys as in ActAsServiceAccounts, and it is granted on those accounts only", who, role,
			)
		}
		if !allowedProjectRoles[role] {
			return fmt.Errorf("%s: project role %q is not in the allow-list (%s)",
				who, role, strings.Join(sortedKeys(allowedProjectRoles), ", "))
		}
	}
	return nil
}

// validateConditionalRoles refuses any conditioned project role outside
// allowedConditionalProjectRoles.
func validateConditionalRoles(who string, roles []ConditionalRole) error {
	for _, cr := range roles {
		if !allowedConditionalProjectRoles[cr.Role] {
			return fmt.Errorf("%s: conditional project role %q is not in the allow-list (%s)",
				who, cr.Role, strings.Join(sortedKeys(allowedConditionalProjectRoles), ", "))
		}
	}
	return nil
}

// accountIDPattern is GCP's service account id format (6-30 chars).
var accountIDPattern = regexp.MustCompile(`^[a-z][a-z0-9-]{4,28}[a-z0-9]$`)

// validateActAsTargets checks the runtime service accounts an identity may act
// as. Each is a bare account id in the identity's own project (the email is
// built from it, so another project cannot be named), and none may be an
// identity this module issues: acting as another deploy, preview or pipeline
// identity would hand over that identity's grants.
func validateActAsTargets(who, self string, ids []string) error {
	seen := map[string]bool{}
	for _, id := range ids {
		if !accountIDPattern.MatchString(id) {
			return fmt.Errorf("%s: act-as target %q must be a bare service account id in the same project "+
				"(6-30 chars, lowercase letters, digits and hyphens), not an email or resource name", who, id)
		}
		if id == self || isPlatformIdentity(id) {
			return fmt.Errorf("%s: act-as target %q is a platform-issued identity; only an application's "+
				"runtime service account may be named here", who, id)
		}
		if seen[id] {
			return fmt.Errorf("%s: act-as target %q is listed twice", who, id)
		}
		seen[id] = true
	}
	return nil
}

// isPlatformIdentity matches the account ids this module issues.
func isPlatformIdentity(id string) bool {
	return strings.HasSuffix(id, "-deploy") ||
		strings.Contains(id, "-deploy-") ||
		strings.HasSuffix(id, "-preview") ||
		strings.HasPrefix(id, "sa-app-infra-")
}

func sortedKeys(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// CheckProjectRoles applies the module's allow-list to an unconditioned role
// list, so a leaf can test its committed config without running the program.
func CheckProjectRoles(roles []string) error { return validateProjectRoles("roles", roles) }

// CheckConditionalRoles applies the module's allow-list to a conditioned list.
func CheckConditionalRoles(roles []ConditionalRole) error {
	return validateConditionalRoles("conditional roles", roles)
}

// NeverProjectWide reports whether role may never be granted at project level
// by this module. Leaf tests use it to check their own defaults directly.
func NeverProjectWide(role string) bool { return isNeverProjectWide(role) }
