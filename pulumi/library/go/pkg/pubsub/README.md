# pubsub

A Pulumi component for creating Pub/Sub topics with optional subscriptions.

**Upstream Reference:** [terraform-google-modules/pubsub/google](https://registry.terraform.io/modules/terraform-google-modules/pubsub/google)

## Overview

Creates a Pub/Sub topic with:
- Configurable labels
- Optional pull and push subscriptions
- Per-subscription ack deadline and push endpoint configuration

## API Reference

### PubSubArgs

| Field | Type | Required | Description |
|:--|:--|:--|:--|
| `ProjectID` | `pulumi.StringInput` | ✅ | GCP project ID |
| `TopicName` | `string` | ✅ | Topic name |
| `Labels` | `map[string]string` | | Topic labels |
| `Subscriptions` | `[]SubscriptionConfig` | | Subscriptions to create |

### SubscriptionConfig

| Field | Type | Required | Description |
|:--|:--|:--|:--|
| `Name` | `string` | ✅ | Subscription name |
| `AckDeadlineSeconds` | `int` | | Ack deadline (default: 10) |
| `PushEndpoint` | `string` | | Push endpoint URL (omit for pull) |

### Outputs

| Field | Type | Description |
|:--|:--|:--|
| `Topic` | `*pubsub.Topic` | The created topic |
| `Subscriptions` | `map[string]*pubsub.Subscription` | Map of name → subscription |

## Usage

```go
ps, err := pubsub.NewPubSub(ctx, "events", &pubsub.PubSubArgs{
    ProjectID: pulumi.String("my-project"),
    TopicName: "event-stream",
    Labels:    map[string]string{"env": "prod"},
    Subscriptions: []pubsub.SubscriptionConfig{
        {Name: "consumer-pull", AckDeadlineSeconds: 30},
        {Name: "webhook-push", PushEndpoint: "https://app.example.com/events"},
    },
})
```
