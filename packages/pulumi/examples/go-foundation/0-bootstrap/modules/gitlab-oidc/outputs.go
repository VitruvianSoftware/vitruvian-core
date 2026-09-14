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

// Mirrors: 0-bootstrap/modules/gitlab-oidc/outputs.tf in the TF foundation —
// the module's output surface, exposed as fields on the GitlabOidc component
// resource.

package gitlaboidc

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// GitlabOidc is the component resource mirroring upstream
// 0-bootstrap/modules/gitlab-oidc.
type GitlabOidc struct {
	pulumi.ResourceState

	// PoolName mirrors upstream output "pool_name".
	PoolName pulumi.StringOutput
	// ProviderName mirrors upstream output "provider_name".
	ProviderName pulumi.StringOutput
}
