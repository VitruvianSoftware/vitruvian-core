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

// Mirrors: 0-bootstrap/modules/parent-iam-member/variables.tf in the TF
// foundation — the module's input surface.

package parentiammember

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// ParentIamMemberArgs mirrors upstream variables.tf.
type ParentIamMemberArgs struct {
	// Member is the IAM member (e.g. "serviceAccount:...", "group:...").
	Member pulumi.StringInput
	// ParentType is one of "project", "folder" or "organization".
	ParentType string
	// ParentId is the ID of the parent resource the roles are granted on.
	ParentId pulumi.StringInput
	// Roles is the list of roles granted to the member on the parent.
	Roles []string
}
