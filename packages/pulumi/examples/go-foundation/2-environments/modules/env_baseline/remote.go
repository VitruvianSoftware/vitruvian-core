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

// Cross-stage state — the Pulumi analog of upstream env_baseline/remote.tf.
//
// Upstream reads the 0-bootstrap and 1-org state via terraform_remote_state
// (org_id, billing account, prefixes, parent, tags). Engine adaptation: our
// port receives those as module inputs instead — scalar identifiers flow in
// synchronously from Pulumi stack config (Args.OrgID, Args.BillingAccount,
// Args.ProjectPrefix, Args.FolderPrefix, Args.Parent), and the 1-org "tags"
// map arrives as a StackReference output wired by the env leaf (Args.Tags).
// This file keeps the remote-state consumption logic that remains: resolving
// this environment's tag value from the 1-org tags map.

package env_baseline

import (
	"fmt"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// envTagValue resolves the environment_{env} tag value ID from the 1-org
// stage's "tags" output map (upstream remote.tf local.tags).
func envTagValue(tagsOutput pulumi.Output, env string) pulumi.StringOutput {
	return tagsOutput.ApplyT(func(v interface{}) string {
		if m, ok := v.(map[string]interface{}); ok {
			key := fmt.Sprintf("environment_%s", env)
			if val, exists := m[key]; exists {
				return val.(string)
			}
		}
		return ""
	}).(pulumi.StringOutput)
}
