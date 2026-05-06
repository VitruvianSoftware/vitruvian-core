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

// Package pubsub provides a reusable Pub/Sub topic and subscription component.
// Mirrors: terraform-google-modules/pubsub/google
package pubsub

import (
	"fmt"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/pubsub"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type SubscriptionConfig struct {
	Name                 string
	AckDeadlineSeconds   int
	MessageRetentionDays int
	PushEndpoint         string
}

type PubSubArgs struct {
	ProjectID     pulumi.StringInput
	TopicName     string
	Labels        map[string]string
	Subscriptions []SubscriptionConfig
}

type PubSub struct {
	pulumi.ResourceState
	Topic         *pubsub.Topic
	Subscriptions map[string]*pubsub.Subscription
}

func NewPubSub(ctx *pulumi.Context, name string, args *PubSubArgs, opts ...pulumi.ResourceOption) (*PubSub, error) {
	if args == nil {
		return nil, fmt.Errorf("args is required")
	}
	component := &PubSub{Subscriptions: make(map[string]*pubsub.Subscription)}
	err := ctx.RegisterComponentResource("pkg:index:PubSub", name, component, opts...)
	if err != nil {
		return nil, err
	}

	topicArgs := &pubsub.TopicArgs{
		Project: args.ProjectID,
		Name:    pulumi.String(args.TopicName),
	}
	if len(args.Labels) > 0 {
		labels := pulumi.StringMap{}
		for k, v := range args.Labels {
			labels[k] = pulumi.String(v)
		}
		topicArgs.Labels = labels
	}

	topic, err := pubsub.NewTopic(ctx, name+"-topic", topicArgs, pulumi.Parent(component))
	if err != nil {
		return nil, err
	}
	component.Topic = topic

	for _, sc := range args.Subscriptions {
		subArgs := &pubsub.SubscriptionArgs{
			Project: args.ProjectID,
			Name:    pulumi.String(sc.Name),
			Topic:   topic.Name,
		}
		if sc.AckDeadlineSeconds > 0 {
			subArgs.AckDeadlineSeconds = pulumi.Int(sc.AckDeadlineSeconds)
		}
		if sc.PushEndpoint != "" {
			subArgs.PushConfig = &pubsub.SubscriptionPushConfigArgs{
				PushEndpoint: pulumi.String(sc.PushEndpoint),
			}
		}

		sub, err := pubsub.NewSubscription(ctx, fmt.Sprintf("%s-sub-%s", name, sc.Name), subArgs, pulumi.Parent(topic))
		if err != nil {
			return nil, err
		}
		component.Subscriptions[sc.Name] = sub
	}

	ctx.RegisterResourceOutputs(component, pulumi.Map{"topicName": topic.Name})
	return component, nil
}
