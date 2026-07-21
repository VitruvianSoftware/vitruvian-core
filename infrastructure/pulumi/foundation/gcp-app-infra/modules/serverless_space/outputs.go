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
