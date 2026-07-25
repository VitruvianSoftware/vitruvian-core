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

// variables.go holds the module's input surface, following the same
// per-concern convention as env_base/confidential_space (upstream
// variables.tf). serverless_space has no upstream counterpart — it is our
// serverless addition to the upstream 5-app-infra module set.

package serverless_space

import (
	"github.com/VitruvianSoftware/pulumi-library/go/pkg/cloud_run"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// ServerlessSpaceArgs configures a Cloud Run workload deployment.
type ServerlessSpaceArgs struct {
	Env          string
	BusinessUnit string
	ProjectID    pulumi.StringInput
	Region       pulumi.StringInput
	ServiceName  string
	ImageDigest  pulumi.StringInput
	// RuntimeServiceAccountEmail, when set, is used as the Cloud Run runtime
	// identity; otherwise a per-service runtime SA (sa-<ServiceName>) is created.
	RuntimeServiceAccountEmail pulumi.StringInput
	// SecretPrefix partitions this app's secret env var names in a shared project
	// (e.g. "OAUTH_USER_INSPECTOR_"); surfaced to the container as SECRET_PREFIX.
	SecretPrefix  string
	EnvVars       map[string]string
	SecretEnv     []cloud_run.SecretEnv
	PublicInvoker bool
	MinInstances  int
	MaxInstances  int

	// Blue-green promotion. When RevisionSuffix is set, the new revision is named
	// <ServiceName>-<Env>-<RevisionSuffix> and traffic is split:
	//   - Promote==true or StableRevision=="" (first deploy): 100% to the new revision.
	//   - otherwise: 100% stays on StableRevision, 0% to the new revision tagged
	//     "candidate" (a smoke test hits the candidate URL before promotion).
	// When RevisionSuffix is empty, the default 100%-to-latest behaviour is used.
	RevisionSuffix string
	StableRevision string
	Promote        bool
}
