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

// variables.go holds the module's input surface (upstream variables.tf),
// following the same per-concern convention as app_deploy_identity.

package app_build_space

import "github.com/pulumi/pulumi/sdk/v3/go/pulumi"

// Args configures one application's build space: the Artifact Registry
// repository its images live in, and the identity allowed to push to it.
//
// WHY THIS IS FOUNDATION AND NOT APPLICATION. The repository lives in the
// business unit's shared infra-pipeline project — a project the FOUNDATION
// creates and owns. An app stack declaring a repository there, and granting IAM
// on it, is the inversion core-vs-application-infrastructure.md §3 test 4 rules
// out: an app may create its own identity, but it may not grant that identity
// power over resources it does not own. The app pushes to this repository; it
// does not get to define it or decide who else may read it.
type Args struct {
	// App is the application name, e.g. "oauth-user-inspector".
	App string
	// BuildProjectID is the BU's shared infra-pipeline project.
	BuildProjectID pulumi.StringInput
	// Region is the Artifact Registry location.
	Region string
	// RepositoryID overrides the repository id. Set it when ADOPTING an
	// existing repository whose id does not match App.
	RepositoryID string
	// BuildAccountID overrides the build SA account id. Set it when ADOPTING
	// an existing account whose id does not match <App>-build.
	BuildAccountID string
	// WorkloadIdentityPool is the FULL pool resource name from gcp-bootstrap.
	WorkloadIdentityPool pulumi.StringInput
	// GitHubEnvironment is the GitHub Environment allowed to impersonate the
	// build SA, e.g. "oauth-user-inspector-build".
	GitHubEnvironment string
	// KeepCount, when > 0, retains only the N most recent versions. Retention
	// is a platform policy decision, which is part of why the repository is
	// declared here rather than by the app.
	KeepCount int
}
