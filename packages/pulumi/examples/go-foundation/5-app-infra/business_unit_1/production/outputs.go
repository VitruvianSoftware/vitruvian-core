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

// outputs.go mirrors upstream
// 5-app-infra/business_unit_1/production/outputs.tf — the exports this leaf
// publishes.

package main

import (
	"foundation-5-app-infra/modules/serverless_space"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// exportAppInfraOutputs publishes the always-present leaf exports.
func exportAppInfraOutputs(ctx *pulumi.Context, remote *projectsRemoteState) {
	ctx.Export("project_id", remote.AppProjectID)
	ctx.Export("region", remote.Region)
}

// exportServerlessOutputs publishes the serverless workload exports (only
// present when the digest-gated serverless workload is deployed).
func exportServerlessOutputs(ctx *pulumi.Context, ss *serverless_space.ServerlessSpaceResult) {
	ctx.Export("serverless_service_uri", ss.ServiceUri)
}
