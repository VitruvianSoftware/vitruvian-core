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

package cloud_build

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// CloudBuildArgs defines the arguments for configuring Cloud Build.
type CloudBuildArgs struct {
	ProjectID string
	RepoURL   string // Optional: if setting up a trigger
}

// ConfigureCloudBuild is a placeholder for future Cloud Build trigger management.
// The cloudbuild.yaml file will be written directly by the main program.
func ConfigureCloudBuild(ctx *pulumi.Context, name string, args *CloudBuildArgs) error {
	// No Pulumi resources are created here directly for the cloudbuild.yaml file.
	// The file content will be managed by the main program using the write_file tool.
	return nil
}
