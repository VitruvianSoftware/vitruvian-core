# gcp-cloudrun

A read-only look at a Cloud Run service or revision: how it is configured, where
its traffic goes, which revisions exist, and what it logged recently. It can
only read. It cannot deploy, update, delete, move traffic or change IAM.

```sh
# a service: describe (with the traffic split), its revisions, its logs
bazel run //tools/gcp-cloudrun:describe -- --app oauth-user-inspector \
    --service oauth-user-inspector-development

# one revision: describe it, and only its logs
bazel run //tools/gcp-cloudrun:describe -- --app oauth-user-inspector \
    --revision oauth-user-inspector-development-77543af1 --since 30m

# another environment: the project comes from the app's Pulumi stack
bazel run //tools/gcp-cloudrun:describe -- --app oauth-user-inspector --env prod \
    --service oauth-user-inspector-production
```

`--help` lists every flag. Defaults: region `us-central1`, logs from the last
`3h`, at most `200` entries.

## Where the project comes from

- `--app <name>` finds `apps/*/<name>/infra/app`; `--infra <dir>` names a
  Pulumi project directly.
- Without `--env`, the project is that directory's row in
  [`infrastructure/gcp-identities.tsv`](../../infrastructure/gcp-identities.tsv)
  (column 3). That map only lists each app's development project.
- With `--env dev|nonprod|prod`, it is `gcp:project` in
  `<infra>/Pulumi.<env>.yaml`, which is where AGENTS.md says project ids live.
- `--project <id>` skips the lookup.

## Which account it acts as

The token is minted with [`//tools/gcp-token`](../gcp-token), so it works the
same on a laptop and in a cloud session.

The identity map's account column is not used as-is for app rows: there it is
the app's deploy service account, which only CI can act as (through Workload
Identity Federation). You cannot mint a token for it locally. So the tool acts
as a person:

1. `--account <email>` if you pass one;
2. otherwise the map's account, if it is a person rather than a
   `*.iam.gserviceaccount.com` service account;
3. otherwise `james.nguyen@gmail.com`, the account every first-party app is
   operated under today (AGENTS.md, "GCP identity is pinned").

If that person has no read access to Cloud Run in the project, the describe and
list steps fail with `PERMISSION_DENIED` and the tool says so. It does not try
other credentials.

## How it stays read-only

- Every gcloud command is built by one function, `gcloud()`, which runs
  `guard()`. The guard allows only `gcloud run services|revisions` and
  `gcloud logging`, and only the verbs `describe`, `list` and `read`. Anything
  else (`deploy`, `update`, `update-traffic`, `delete`, `replace`,
  `set-iam-policy`, ...) is an error and nothing runs.
- The runner checks the guard again just before it executes gcloud.
- Service, revision, region and project names must start with a letter and
  hold only lowercase letters, digits and hyphens. So they cannot break out of
  the logging filter, and gcloud can never read one as a flag.

## The token

The token never appears on a command line or in output. gcloud has no
access-token environment variable (only the `auth/access_token_file`
property; checked against Cloud SDK 590.0.1), so the tool writes the token to a
private `0600` file in the temp directory, points `CLOUDSDK_AUTH_ACCESS_TOKEN_FILE`
at it, and deletes it on exit.

Ctrl-C, `kill` (SIGTERM) and closing the terminal (SIGHUP) do not skip that
cleanup. The tool catches those signals and only records them. gcloud still
receives and obeys them, because a caught signal is reset to its default when
gcloud starts. The tool then stops running commands, deletes the file and exits
130. A `kill -9` cannot be caught, so each run also deletes token files that
belonged to processes that no longer exist.

## Tests

`bazel test //tools/gcp-cloudrun/...` covers the identity-map parsing, account
choice, argv for each mode, the guard (including every write verb above), and
that the token never reaches argv or output. The tests run no gcloud: command
execution sits behind a `Runner` trait that the tests replace.
