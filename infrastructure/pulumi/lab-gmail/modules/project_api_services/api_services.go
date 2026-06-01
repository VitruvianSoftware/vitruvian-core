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

package project_api_services

import (
	"github.com/pulumi/pulumi-gcp/sdk/v7/go/gcp/projects"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// EnableAPIServicesArgs defines the arguments for enabling API services.
type EnableAPIServicesArgs struct {
	ProjectID string
	Services  []string
}

// EnableAPIServices enables a list of specified API services for a GCP project.
// It returns a map of service names to their corresponding projects.Service resources.
func EnableAPIServices(ctx *pulumi.Context, name string, args *EnableAPIServicesArgs) (map[string]*projects.Service, error) {
	enabledServices := make(map[string]*projects.Service)
	for _, service := range args.Services {
		svc, err := projects.NewService(ctx, name+"-"+service, &projects.ServiceArgs{
			Project: pulumi.String(args.ProjectID),
			Service: pulumi.String(service),
			DisableOnDestroy: pulumi.Bool(false), // Keep API enabled even if Pulumi stack is destroyed
		})
		if err != nil {
			return nil, err
		}
		enabledServices[service] = svc
	}
	return enabledServices, nil
}