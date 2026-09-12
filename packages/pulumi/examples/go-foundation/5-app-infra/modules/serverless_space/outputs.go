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

// outputs.go holds the module's output surface, following the same
// per-concern convention as env_base/confidential_space (upstream
// outputs.tf). serverless_space has no upstream counterpart — it is our
// serverless addition to the upstream 5-app-infra module set.

package serverless_space

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// ServerlessSpaceResult holds outputs from the serverless_space deployment.
type ServerlessSpaceResult struct {
	ServiceName    pulumi.StringOutput
	ServiceUri     pulumi.StringOutput
	RuntimeSAEmail pulumi.StringOutput
}
