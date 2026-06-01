# Agent guide — vitruvian-core

## GCP identity is pinned per-infrastructure

This repo manages cloud infrastructure under multiple Google accounts (personal,
abrial, Vitruvian). **Never assume the ambient `gcloud` account is correct.**

The mapping of infrastructure → GCP account is in
[`infrastructure/gcp-identities.tsv`](infrastructure/gcp-identities.tsv).

- **Pulumi:** the Bazel wrappers
  (`bazel run //infrastructure/pulumi/<project>:{preview,up,refresh,destroy,config,setup}`)
  read that file and automatically inject an access token for the declared
  account — you do not touch `gcloud config`. If the declared account isn't
  logged in, the wrapper fails fast and tells you which `gcloud auth login` to run.
- **Ad-hoc GCP commands** (`gcloud`, `gsutil`, …): look up the account (and project) in the map, then:

  ```bash
  export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token --account=<account>)"
  # if the map declares a project (3rd column), also:
  export GOOGLE_CLOUD_PROJECT=<gcp_project>
  ```

> Adding a new Pulumi project that uses GCP? Add a row to the map **first** — the
> wrapper silently skips injection (and falls back to the ambient account) for
> projects not listed.
