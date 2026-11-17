# pagerduty

Read-only looks at the live PagerDuty account, to check what the
[`pagerduty` Pulumi stack](../../infrastructure/pulumi/platform/pagerduty) did.

```sh
bazel run //tools/pagerduty:read -- /schedules
bazel run //tools/pagerduty:read -- /users/<id>/contact_methods
bazel run //tools/pagerduty:read -- /users/<id>/notification_rules
```

- **GET only**, to `https://api.pagerduty.com` only. A path that could change
  the host is refused.
- **Contact details are masked** (`address`, `email`, `phone_number` keep their
  last two characters), so the output is safe to paste.
- **Token:** `PAGERDUTY_TOKEN`, then `PAGERDUTY_API_KEY`, then
  `~/.config/pagerduty/api-key`. It reaches curl on stdin, never on its
  command line.

Changes to the account go through the Pulumi stack, never through this tool.
