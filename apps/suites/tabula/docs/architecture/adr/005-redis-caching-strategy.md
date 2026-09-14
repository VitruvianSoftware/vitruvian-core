# 5. Redis Caching Strategy

Date: 2025-12-08

## Status

Accepted

## Context

We are using Upstash Redis for caching and session management. The free tier of Upstash limits us to
a single Redis database instance. However, we have multiple environments (Development, Production)
that need to use Redis.

If both environments connect to the same Redis instance without any separation, they will overwrite
each other's keys (e.g., a session ID generated in Dev could collide with or be read by Prod, or
cache keys could return incorrect data).

## Decision

We will use a single Upstash Redis instance for all environments but enforce **Key Namespacing** to
isolate data.

1.  **Single Instance**: Both Development and Production environments will connect to the same
    Upstash Redis URL.
2.  **Key Prefixing**: All Redis keys MUST be prefixed with the current environment name.
    - Pattern: `{environment}:{service}:{key}`
    - Example (Dev): `development:api:session:12345`
    - Example (Prod): `production:api:session:12345`
3.  **Implementation**: The Redis client wrapper in the application code will automatically prepend
    `process.env.NODE_ENV` (or a configured `ENVIRONMENT` variable) to all keys.

## Consequences

### Positive

- **Cost Efficiency**: We stay within the free tier of Upstash by using a single database.
- **Simplicity**: No need to manage multiple Redis credentials or instances.
- **Isolation**: Data collisions are prevented by the namespace prefix.

### Negative

- **Operational Risk**: A "flushdb" command run by accident in Development would wipe Production
  data.
  - _Mitigation_: Disable dangerous commands in the application client. Use strict access controls
    if possible (though Upstash free tier has limited ACLs).
- **Performance**: No significant impact, but keys are slightly longer.
- **Monitoring**: Metrics are aggregated for the whole instance, making it harder to distinguish Dev
  vs Prod load on the Upstash dashboard.

## Implementation Details

The Redis client should be initialized with a `keyPrefix` option if supported by the library (e.g.,
`ioredis` supports this), or wrapped in a service that enforces it.

```typescript
import Redis from 'ioredis';

const redis = new Redis(process.env.UPSTASH_REDIS_URL, {
  keyPrefix: `${process.env.NODE_ENV || 'development'}:`,
});
```
