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

package main

import (
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/pubsub"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/securitycenter"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// deploySCCNotification creates the Security Command Center notification
// pipeline: a Pub/Sub topic + subscription, and an SCC notification config
// that streams all active findings to the topic.
// This mirrors the Terraform foundation's scc_notification.tf.
func deploySCCNotification(ctx *pulumi.Context, cfg *OrgConfig, sccProjectID pulumi.StringOutput) error {
	// 1. Pub/Sub Topic for SCC findings
	sccTopic, err := pubsub.NewTopic(ctx, "scc-notification-topic", &pubsub.TopicArgs{
		Project: sccProjectID,
		Name:    pulumi.String("top-scc-notification"),
	})
	if err != nil {
		return err
	}

	// 2. Pub/Sub Subscription for consuming SCC findings
	if _, err := pubsub.NewSubscription(ctx, "scc-notification-subscription", &pubsub.SubscriptionArgs{
		Project: sccProjectID,
		Name:    pulumi.String("sub-scc-notification"),
		Topic:   sccTopic.Name,
	}); err != nil {
		return err
	}

	// 3. SCC V2 Notification Config — streams findings to Pub/Sub
	if _, err := securitycenter.NewV2OrganizationNotificationConfig(ctx, "scc-notification", &securitycenter.V2OrganizationNotificationConfigArgs{
		Organization: pulumi.String(cfg.OrgID),
		ConfigId:     pulumi.String(cfg.SCCNotificationName),
		Description:  pulumi.String("SCC Notification for all active findings"),
		PubsubTopic:  sccTopic.ID(),
		StreamingConfig: &securitycenter.V2OrganizationNotificationConfigStreamingConfigArgs{
			Filter: pulumi.String(cfg.SCCNotificationFilter),
		},
	}); err != nil {
		return err
	}

	return nil
}
