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

package main

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// lookupHubProjectID reads the hub host project id from the 1-org stack
// reference, mirroring upstream 3-networks-hub-and-spoke/envs/production/remote.tf.
func lookupHubProjectID(ctx *pulumi.Context, cfg *NetConfig) (pulumi.StringOutput, error) {
	netHubOrgStack, err := pulumi.NewStackReference(ctx, "org", &pulumi.StackReferenceArgs{
		Name: pulumi.String(cfg.OrgStackName),
	})
	if err != nil {
		return pulumi.StringOutput{}, err
	}
	return netHubOrgStack.GetStringOutput(pulumi.String("net_hub_project_id")), nil
}
