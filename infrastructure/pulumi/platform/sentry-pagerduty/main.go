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

// Pulumi program wiring our self-hosted Sentry organization's PagerDuty
// integration to the routing key exported by vitruvian-pagerduty and ensuring
// every non-excluded Sentry project pages PagerDuty on high-priority issues.
package main

import (
	"github.com/pulumi/pulumi-terraform-provider/sdks/go/sentry/sentry"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/sentry-pagerduty/internal/alerts"
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/sentry-pagerduty/internal/sentrytoken"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		settings, err := alerts.Load(config.New(ctx, alerts.Namespace))
		if err != nil {
			return err
		}

		token, err := sentrytoken.Resolve(ctx)
		if err != nil {
			return err
		}

		provider, err := sentry.NewProvider(ctx, "sentry", &sentry.ProviderArgs{
			BaseUrl: pulumi.String(settings.BaseURL),
			Token:   token,
		})
		if err != nil {
			return err
		}

		_, err = alerts.Reconcile(ctx, provider, settings)
		return err
	})
}
