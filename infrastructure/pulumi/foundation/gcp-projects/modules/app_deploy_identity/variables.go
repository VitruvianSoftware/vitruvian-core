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
// following the same per-concern convention as serverless_space.

package app_deploy_identity

import "github.com/pulumi/pulumi/sdk/v3/go/pulumi"

// Args configures one application's platform-issued deploy identity.
type Args struct {
	// App is the application name, e.g. "oauth-user-inspector". It seeds the
	// default account id (<App>-deploy) unless DeployAccountID overrides it.
	App string
	// Env is the environment this identity serves (development/nonproduction/
	// production) — display only; the leaf pins the real environment.
	Env string
	// ProjectID is the environment's app-hosting project (the oss floating
	// project from the gcp-projects stage).
	ProjectID pulumi.StringInput
	// DeployAccountID overrides the account id. Set it when ADOPTING an
	// existing account whose id does not match <App>-deploy.
	DeployAccountID string
	// DeployRoles are the project-level roles the deploy SA needs. These reach
	// outside the application, which is why they are authored in the foundation.
	DeployRoles []string
	// WorkloadIdentityPool is the FULL pool resource name from gcp-bootstrap,
	// e.g. projects/<n>/locations/global/workloadIdentityPools/foundation-pool.
	WorkloadIdentityPool pulumi.StringInput
	// GitHubEnvironment is the per-env GitHub Environment allowed to
	// impersonate this SA, e.g. "oauth-user-inspector-development". The WIF
	// provider already pins the repository, so the environment is the isolation
	// layer.
	GitHubEnvironment string
	// ConditionalDeployRoles are project-level roles granted WITH an IAM
	// condition. Nil (the zero value) reproduces the pre-existing behaviour
	// exactly. They are a SEPARATE field, not entries in DeployRoles, because
	// in GCP an IAM condition is part of the BINDING'S IDENTITY: the same role
	// with a condition is a different binding, not a modified one. Granting a
	// prefix-scoped role unconditionally would silently widen it to every
	// co-tenant application in the shared project.
	ConditionalDeployRoles []ConditionalRole
	// ProjectNumber resolves the ${projectNumber} placeholder in condition
	// expressions. Required only when some expression uses that placeholder —
	// Secret Manager conditions must address secrets by project NUMBER, which
	// differs per environment and is only known as a stack output.
	ProjectNumber pulumi.StringInput
}

// ConditionalRole is a project-level role grant carrying an IAM condition.
//
// Expression is CEL and may contain the placeholders ${projectNumber} and
// ${projectId}, which are substituted from Args. Both Title and Expression are
// part of the binding's identity in GCP, so neither may be normalised or
// reconstructed — they must match the live binding byte for byte or the apply
// creates a SECOND binding instead of adopting the existing one.
type ConditionalRole struct {
	Role       string
	Title      string
	Expression string
}
