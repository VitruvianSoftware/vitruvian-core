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

// outputs.go is the module's return surface (upstream outputs.tf).

package app_build_space

import "github.com/pulumi/pulumi/sdk/v3/go/pulumi"

// Result is what the leaf exports so other stages and the app's build pipeline
// can consume the build space without re-deriving its names.
type Result struct {
	// RepositoryID is the Artifact Registry repository id (not the full path).
	RepositoryID pulumi.StringOutput
	// RepositoryName is the full resource name.
	RepositoryName pulumi.StringOutput
	// BuildServiceAccountEmail is the identity permitted to PUSH images.
	BuildServiceAccountEmail pulumi.StringOutput
}
