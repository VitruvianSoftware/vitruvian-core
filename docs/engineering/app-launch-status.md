# Application launch status

The source of truth for **whether an app has real users**, and therefore how
disruptive changes to it are allowed to be. Check this before any change that
would cause downtime, recreate live resources, or migrate regions/projects.

## The rule

- **Not launched** → **disruption is fine.** Recreate resources, change regions,
  tear down and rebuild, accept downtime. Get the infrastructure into the
  *correct* shape rather than preserving accidents just because they currently
  work. Do NOT contort a change into a zero-downtime cutover for an app nobody
  uses — that caution is wasted effort and often riskier than a clean rebuild.
- **Launched** → **protect live traffic.** Zero-downtime cutovers, adopt-don't-
  replace, staged rollouts, backups before destructive steps. The care the
  workload cutover took (import → empty-diff → state-delete) is the bar.

"Real users" means anyone other than the maintainer (James). A staging/demo
instance James pokes at is *not* launched.

## Status

| App | Launched? | Since | Notes |
| --- | --- | --- | --- |
| oauth-user-inspector | **No** | — | Public demo tool, but no external users yet. Free to reshape (region standardization, build-stack strip). |
| tabula | **No** | — | Pre-launch. Free to reshape. |
| mcp-slack | **No** | — | Not deployed as a hosted service. |
| nexus-agent | **No** | — | Not deployed as a hosted service. |

## When an app launches

Change its row to **Yes** + the date, and from that point treat it under the
"Launched" rule above. Update the companion memory (`app-launch-status`) so
agent sessions pick up the change without re-litigating it.

> Nothing in this repo is launched as of 2026-07-23. Until a row here says
> otherwise, prefer the clean rebuild over the careful cutover.
