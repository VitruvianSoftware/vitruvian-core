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
