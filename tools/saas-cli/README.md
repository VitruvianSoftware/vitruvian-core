# saas-cli

The **Neon** and **Upstash** CLIs, pre-authenticated, behind `bazel run`.

```sh
bazel run //tools/saas-cli:whoami                     # verify both credentials work
bazel run //tools/saas-cli:neon    -- projects list
bazel run //tools/saas-cli:neon    -- connection-string <project-id>
bazel run //tools/saas-cli:upstash -- redis list
```

Everything after `--` goes to the CLI verbatim.

## Authentication is not a step

Both credentials already live in the shared infra-pipeline project's Secret
Manager (seeded with [`//tools/gcp-secrets`](../gcp-secrets)). The wrapper reads
them per invocation and hands them to the CLI as environment variables. So:

- **no `login` subcommand, and no token cached on disk.** `neonctl auth` would
  write `~/.config/neonctl/credentials.json`; we never invoke it, so there is
  nothing to go stale or leak from a laptop.
- **you are always using the same credential CI uses**, so what you see locally
  matches what the pipeline sees.
- **rotating the secret takes effect on the next invocation**, everywhere.

The GCP identity used to read the secrets is pinned from
`infrastructure/gcp-identities.tsv` — never ambient `gcloud`, which on this
machine could be any of several accounts.

## ⚠️ Provisioning belongs to Pulumi

`tabula/infra/data` owns the Neon projects and the Upstash database. Creating or
deleting one through these CLIs puts it **outside Pulumi state**, and the next
`pulumi up` will try to reconcile the difference — recreating what you deleted,
or fighting what you made.

Use these to **look**: list, describe, connection strings, metrics, and the
occasional break-glass with no Pulumi equivalent. Change desired state in the
stack.

## Access

Reading the credentials requires `secretmanager.secretAccessor` on them. CI has
it as `tabula-build@`; a human needs it too, granted as code via
`tabula-build:operatorPrincipal` in `tabula/infra/build/Pulumi.production.yaml`.
Unset by default, so a new business unit copying this stack grants nobody.

If a run fails with `PERMISSION_DENIED`, that grant is what is missing.

## Version pinning

`NEONCTL_VERSION` and `UPSTASH_CLI_VERSION` are pinned in the script so a run is
reproducible and a surprise major cannot land in the middle of an incident —
same reasoning as the Squawk pin in `tools/ci/migration-safety.sh`. Override per
invocation with the matching env var when you need a newer one.

## Tests

`bazel test //tools/saas-cli:saas_cli_test` — hermetic, driving the real script
against fake `gcloud`/`npx` binaries that record argv **and** the environment
they were handed. It pins: the key travels in the environment and never argv
(which `ps` exposes) or the output; the CLI version is pinned; every `gcloud`
call is identity+project pinned; and both a `gcloud` auth failure (which exits
**0**) and an unseeded secret are fatal with an actionable message.
