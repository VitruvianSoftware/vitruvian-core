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

package alerts

import (
	"fmt"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	sentry "github.com/pulumiverse/pulumi-sentry/sdk/go/sentry"
)

func ReconcileDefaultIssueAlerts(ctx *pulumi.Context, org string, projects map[string]*sentry.SentryProject, opts ...pulumi.ResourceOption) error {
	for slug, proj := range projects {
		alertName := fmt.Sprintf("alert-%s-new-issue", slug)
		_, err := sentry.NewSentryIssueAlert(ctx, alertName, &sentry.SentryIssueAlertArgs{
			Organization: pulumi.String(org),
			Project:      proj.Slug,
			Name:         pulumi.Sprintf("%s New Issue Alert", slug),
			ActionMatch:  pulumi.String("any"),
			FilterMatch:  pulumi.String("any"),
			Frequency:    pulumi.Int(30),
			Conditions: pulumi.StringMapArray{
				pulumi.StringMap{
					"id": pulumi.String("sentry.rules.conditions.first_seen_event.FirstSeenEventCondition"),
				},
			},
			Actions: pulumi.StringMapArray{
				pulumi.StringMap{
					"id":              pulumi.String("sentry.mail.actions.NotifyEmailAction"),
					"targetType":      pulumi.String("IssueOwners"),
					"fallthroughType": pulumi.String("ActiveMembers"),
				},
			},
		}, append(opts, pulumi.DependsOn([]pulumi.Resource{proj}))...)
		if err != nil {
			return fmt.Errorf("creating sentry issue alert for %s: %w", slug, err)
		}
	}
	return nil
}
