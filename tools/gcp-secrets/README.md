# gcp-secrets

Seed and inspect **GCP Secret Manager secret values** through `bazel run`.

```sh
bazel run //tools/gcp-secrets:status -- tabula/infra/build   # what still needs a value
bazel run //tools/gcp-secrets:seed   -- tabula/infra/build   # fill in every unseeded secret
```

## Why this exists

A secret has two halves, and they ship differently:

| half | how it ships |
| --- | --- |
| the **container** + its IAM | declared in Pulumi, applied by the pipeline (§2.3) |
| the **value** | cannot be committed — even Pulumi-encrypted, that is a secret in git history forever (§2.4) |

So the value is the one part that a human has to hand over out of band. Principle
§2.2 says that step is still a `bazel run` target, not a `gcloud` line someone
gets pasted in chat: *"Shipping an operational `*.sh` you run directly is the
anti-pattern; wrap it before it lands."*

This is the sibling of [`//tools/sync-env-secrets`](../sync-env-secrets), which
covers GitHub Actions secrets and deliberately does **not** cover GCP Secret
Manager.

## What the wrapper folds in

- **Identity.** The account and target project come from
  `infrastructure/gcp-identities.tsv`, keyed on the app's infra dir, via the same
  resolver the Pulumi wrappers use. This machine has several gcloud accounts;
  ambient `gcloud` silently targets whichever one is current.
- **Value handling.** Read with `read -rs` (never echoed), passed to gcloud on
  **stdin** via `--data-file=-`. Never an argv element — argv is world-readable
  through `ps`, so `--data-value=…` would leak the secret to every user on the
  box. It never reaches stdout, stderr, or shell history.
- **Idempotence.** An already-seeded secret is skipped, so a re-run cannot stack
  a second version and quietly change which value is `latest`. Use `--force` for
  a deliberate rotation.
- **Honest failures.** `gcloud` exits **0** while printing
  `ERROR: … Reauthentication failed` to stderr when credentials expire. Suppressing
  stderr would turn a broken credential into a confident, empty *"this project has
  no secrets"*. Both the status code and stderr are checked, and the real message
  is surfaced with the fix (`gcloud auth login <account>`).

## Usage

```sh
# Which secrets in the project still have no value?
bazel run //tools/gcp-secrets:status -- tabula/infra/build

# Prompt for every unseeded secret (the "stack just applied" flow)
bazel run //tools/gcp-secrets:seed -- tabula/infra/build

# One specific secret
bazel run //tools/gcp-secrets:seed -- tabula/infra/build NEON_API_KEY

# Rotate one that already has a value
bazel run //tools/gcp-secrets:seed -- tabula/infra/build --force NEON_API_KEY
```

`<infra-dir>` is the app's Pulumi infra directory exactly as it appears in
`infrastructure/gcp-identities.tsv`. An unlisted dir is refused rather than
falling back to ambient credentials.

## Tests

`bazel test //tools/gcp-secrets:gcp_secrets_test` — hermetic, driving the real
script against a fake `gcloud` that records argv and stdin per call. It pins the
properties whose failure would be a leak or a wrong-target write: value on stdin
and absent from argv, absent from all output, every call identity+project pinned,
already-seeded skipped, `--force` rotates, empty input skips, an unmapped dir
refused, and an auth failure fatal despite gcloud's exit 0.
