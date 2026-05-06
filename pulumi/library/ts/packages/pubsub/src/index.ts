/**
 * PubSub Module
 * Creates Pub/Sub topics with optional subscriptions and IAM bindings.
 * Mirrors: terraform-google-modules/pubsub/google
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface SubscriptionConfig {
    name: string;
    ackDeadlineSeconds?: number;
    messageRetentionDuration?: string;
    pushEndpoint?: string;
}

export interface PubSubArgs {
    projectId: pulumi.Input<string>;
    topicName: string;
    labels?: Record<string, string>;
    subscriptions?: SubscriptionConfig[];
}

export class PubSub extends pulumi.ComponentResource {
    public readonly topic: gcp.pubsub.Topic;
    public readonly subscriptions: gcp.pubsub.Subscription[] = [];

    constructor(name: string, args: PubSubArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:PubSub", name, args, opts);

        this.topic = new gcp.pubsub.Topic(`${name}-topic`, {
            project: args.projectId,
            name: args.topicName,
            labels: args.labels,
        }, { parent: this });

        if (args.subscriptions) {
            for (const sc of args.subscriptions) {
                const sub = new gcp.pubsub.Subscription(`${name}-sub-${sc.name}`, {
                    project: args.projectId,
                    name: sc.name,
                    topic: this.topic.name,
                    ackDeadlineSeconds: sc.ackDeadlineSeconds,
                    messageRetentionDuration: sc.messageRetentionDuration,
                    pushConfig: sc.pushEndpoint ? { pushEndpoint: sc.pushEndpoint } : undefined,
                }, { parent: this.topic });
                this.subscriptions.push(sub);
            }
        }

        this.registerOutputs({ topicName: this.topic.name });
    }
}
