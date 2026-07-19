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

// outputs.go mirrors upstream 5-app-infra/modules/env_base/outputs.tf —
// the module's output surface.

package env_base

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// EnvBaseResult holds outputs from the env_base deployment.
type EnvBaseResult struct {
	InstanceSelfLink pulumi.StringOutput
	InstanceName     pulumi.StringOutput
	InstanceZone     pulumi.StringOutput
	InstanceDetails  pulumi.MapOutput
}
