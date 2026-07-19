/*
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

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
	Region       string
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
