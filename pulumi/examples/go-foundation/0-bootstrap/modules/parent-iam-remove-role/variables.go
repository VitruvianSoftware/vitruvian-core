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

// Mirrors: 0-bootstrap/modules/parent-iam-remove-role/variables.tf in the TF
// foundation — the module's input surface.

package parentiamremoverole

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// ParentIamRemoveRoleArgs mirrors upstream variables.tf.
type ParentIamRemoveRoleArgs struct {
	// ParentType is one of "project", "folder" or "organization".
	ParentType string
	// ParentId is the ID of the parent resource the roles are removed from.
	ParentId pulumi.StringInput
	// Roles is the list of roles whose members are removed (authoritative
	// empty bindings).
	Roles []string
}
