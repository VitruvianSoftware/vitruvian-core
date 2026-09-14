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

package base_env

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// resolveAcmPolicyID resolves the Access Context Manager policy id from the
// 1-org stack reference (or returns an empty output when no org stack is
// configured), mirroring upstream 3-networks-svpc/modules/base_env/remote.tf.
func resolveAcmPolicyID(ctx *pulumi.Context, args *Args) (pulumi.StringOutput, error) {
	if args.OrgStackName == "" {
		return pulumi.String("").ToStringOutput(), nil
	}
	orgStack, err := pulumi.NewStackReference(ctx, "org", &pulumi.StackReferenceArgs{
		Name: pulumi.String(args.OrgStackName),
	})
	if err != nil {
		return pulumi.StringOutput{}, err
	}
	return orgStack.GetStringOutput(pulumi.String("access_context_manager_policy_id")), nil
}
