/*
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package pubsub

import (
	"testing"

	"github.com/VitruvianSoftware/pulumi-library/go/internal/testutil"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/require"
)

func TestNewPubSub_NilArgs(t *testing.T) {
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		_, err := NewPubSub(ctx, "test", nil)
		require.Error(t, err)
		require.Contains(t, err.Error(), "args is required")
		return nil
	}, pulumi.WithMocks("project", "stack", testutil.NewTracker()))
	require.NoError(t, err)
}

func TestNewPubSub_TopicOnly(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		result, err := NewPubSub(ctx, "test-topic", &PubSubArgs{
			ProjectID: pulumi.String("test-proj"),
			TopicName: "my-topic",
			Labels:    map[string]string{"env": "test"},
		})
		require.NoError(t, err)
		require.NotNil(t, result.Topic)
		require.Len(t, result.Subscriptions, 0)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:pubsub/topic:Topic", 1)
	tracker.RequireType(t, "gcp:pubsub/subscription:Subscription", 0)
}

func TestNewPubSub_WithSubscriptions(t *testing.T) {
	tracker := testutil.NewTracker()
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		result, err := NewPubSub(ctx, "test-subs", &PubSubArgs{
			ProjectID: pulumi.String("test-proj"),
			TopicName: "events-topic",
			Subscriptions: []SubscriptionConfig{
				{Name: "pull-sub", AckDeadlineSeconds: 20},
				{Name: "push-sub", PushEndpoint: "https://example.com/push"},
			},
		})
		require.NoError(t, err)
		require.Len(t, result.Subscriptions, 2)
		return nil
	}, pulumi.WithMocks("project", "stack", tracker))
	require.NoError(t, err)

	tracker.RequireType(t, "gcp:pubsub/topic:Topic", 1)
	tracker.RequireType(t, "gcp:pubsub/subscription:Subscription", 2)
}
