# Merge-queue jobs on homelab runners — design

**Date:** 2026-10-19 · **Status:** draft for review · **Owner:** wren
**Scope:** `gitops/argocd/platform/` (a runner controller and one runner scale
set), a CI runner image, `.github/workflows/*` `runs-on`, the `repo-config`
stack (one repository variable, one Actions setting), a conformance check.

## 1. What this is

Merge-queue entries wait for runners. The account's concurrent-job cap is
shared by every pull request, the merge queue and `main`. On 2026-10-19, 43
runs were queued against 9 running, and a queue rebuild added a full batch
of jobs. Small workflows that normally take 20 seconds took 24 minutes. Over
Oct 5–19 the p90 from a PR's first entry into the queue to its merge was
28.5 min (#3518).

This moves the queue's Linux jobs onto runners on the homelab k3s cluster,
which adds capacity that only the queue and `main` use. Pull-request jobs
keep the GitHub-hosted runners and then have the hosted cap to themselves.

Decisions James made on 2026-10-19, taken as given:

| # | Decision |
|---|---|
| 1 | Homelab runners take **merge-queue and push-to-main jobs only**. PR jobs stay on GitHub-hosted runners. |
| 2 | Runner pods run on **fedora and nuc9i9**, the two large amd64 nodes (24 cores/64 GiB and 16/64, both mostly idle). Laptops excluded. |
| 3 | Jobs move behind a **repository variable**: unset, everything runs on GitHub-hosted runners. Pilot a few workflows, then widen. |

Out of scope: macOS jobs (`xcode-27`, `macos-15`) stay on GitHub. So do jobs
that need Docker (`ci.yaml`'s Docker job, `copybara-config-smoketest`) until
a later phase decides on Docker-in-Docker. Pull-request jobs are covered by
decision 1.

## 2. Architecture

```
GitHub (merge_group / push to main)
   │  job requests label "vitruvian-queue"
   ▼
gha-runner-scale-set-controller (namespace arc-system)
   │  scales on demand, one pod per job, deleted after the job
   ▼
runner scale set "vitruvian-queue" (namespace arc-runners)
   pods: image vitruvian-ci-runner@sha256:…, on fedora | nuc9i9
```

- **Controller and scale set:** GitHub's Actions Runner Controller (ARC), using
  the two upstream charts consumed as-is (§3.6 of the principles):
  `gha-runner-scale-set-controller` and `gha-runner-scale-set`. They live as
  ApplicationSets under `gitops/argocd/platform/actions-runner-controller/`
  and `gitops/argocd/platform/actions-runners/`. Owned manifests (the sealed
  secret, the NetworkPolicy) go in `actions-runners-manifests/`.
- **Registration:** at the **repository** level, for `vitruvian-core` only, as
  the scale set named `vitruvian-queue`. That name is the `runs-on` label.
- **Ephemeral:** every job gets a fresh pod that ARC deletes when the job
  ends. No workspace, credential or cache survives into the next job.
- **Placement:** pods are placed with node affinity on
  `kubernetes.io/hostname in (fedora, nuc9i9)`. Each pod requests 4 CPU and
  8 GiB, with limits of 8 CPU and 16 GiB. Settings: `minRunners: 1` (one warm
  pod, so the first job doesn't wait for a pull and start), and
  `maxRunners: 8`, which fits both nodes with headroom for their existing
  workloads. Bazel work stays light because BuildBuddy's remote cache serves
  most actions, exactly as on hosted runners.
- **Authentication:** a GitHub App, `vitruvian-arc`, installed on
  `vitruvian-core` with repository **Administration: read & write** (needed
  to register runners) and Metadata read. Its app id, installation id and
  private key go into a SealedSecret, written by a new
  `tools/gitops/seal_arc_github_app.sh` (with a test), following the existing
  `seal_*` scripts.

## 3. Runner image

The stock `ghcr.io/actions/actions-runner` image is not enough.
`.github/actions/setup-bazel` runs `sudo dpkg -i` on two Ubuntu 26.04
packages, and every queue job assumes the hosted `ubuntu-26.04` image. So
the project builds its own:

- `vitruvian-ci-runner` is built from `ubuntu:26.04`, plus the GitHub Actions
  runner binary at a pinned version, passwordless `sudo` for the runner user,
  and what the queue jobs use from the hosted image: git, curl, xz, unzip,
  zstd, jq, python3, build-essential, ca-certificates.
- It is built with `tools/oci`, pushed to GHCR, and pinned by digest in the
  scale set's values. argocd-image-updater bumps the digest, as for
  `mcp-slack`.
- **A parity test** runs every queue workflow's setup steps (checkout,
  setup-bazel, setup-go, setup-helm) inside the image in CI, so a missing tool
  fails there and not in the queue.

## 4. Routing jobs

Each job that moves gets:

```yaml
runs-on: ${{ (github.event_name == 'merge_group' || (github.event_name == 'push' && github.ref == 'refs/heads/main')) && vars.QUEUE_RUNNER || 'ubuntu-26.04' }}
```

- **The switch:** the repository variable `QUEUE_RUNNER` is `vitruvian-queue`
  when on and empty when off. Empty means every job runs on GitHub-hosted
  runners, so emptying it is an instant, whole-repo rollback with no deploy.
  The variable is managed in `repo-config` (`github.ActionsVariable`), not
  by hand.
- **Pull requests can never pick it:** for `pull_request` the expression is
  always `ubuntu-26.04`. A new conformance rule (`//tools/conformance:check`)
  fails if any workflow names `vitruvian-queue` or `vars.QUEUE_RUNNER`
  outside exactly this guarded expression.
- **actionlint:** `vitruvian-queue` joins the self-hosted labels in
  `.github/actionlint.yaml`.

## 5. Security: the repository is public

The repository is public and allows forks. The risk is a fork PR running its
own code on a homelab runner: a fork PR runs the PR's copy of the
workflows, so it can rewrite `runs-on` to `vitruvian-queue` and ignore the
guard in §4. GitHub cannot limit a repository-level runner to certain
events, so the controls are layered:

1. **Fork PRs need approval to run workflows, from every outside
   contributor.** Today the setting is `first_time_contributors`, so anyone
   who has had one PR merged can run workflows on later PRs without
   approval. It must become `all_external_contributors`, set in `repo-config`,
   **before the scale set registers**. This is a hard prerequisite.
2. **Only reviewed code normally reaches the runners.** Merge-queue entries
   have been approved, and `main` only contains merged code.
3. **Pod isolation:**
   - A dedicated namespace, with no service-account token mounted, and no
     privileged or host-path access.
   - Pod Security `restricted`, except for the `sudo` that `setup-bazel`
     needs inside the container. There is no host access, no capabilities
     beyond the default, and no Docker.
   - A CiliumNetworkPolicy denies egress to the cluster, the LAN and the
     tailnet ranges (pod and service CIDRs, `192.168.0.0/16`,
     `100.64.0.0/10`) and allows the internet on 443/80. A job can reach
     GitHub, BuildBuddy and package mirrors, and nothing on the homelab.
4. **Secrets in a job are the ones it already gets on hosted runners:**
   `BUILDBUDDY_API_KEY` and the job's `GITHUB_TOKEN`. Nothing from the
   cluster is mounted.

## 6. Rollout

| Phase | What | Moves when |
|---|---|---|
| 0 | Fork approval tightened. App created, controller and scale set deployed idle, image built, `QUEUE_RUNNER` empty. | Merged; the runner shows as online and idle in the repo's runner settings |
| 1 | Pilot: actionlint, release-scope, migration-safety, conformance-check, tidy-check, the small, setup-bazel-only workflows. `QUEUE_RUNNER` set. | A week of queue runs with no runner-caused failures |
| 2 | Presubmit and CI Linux jobs, still no Docker | Phase 1 clean |
| 3 | Measure with `//tools/merge-queue-stats` against #3518's baseline | — |

Rollback at any phase: empty `QUEUE_RUNNER`.

**Overlap with #3518:** the HEADGREEN trial runs over the same weeks. Phase 1
and 2 dates go into #3518 so each change's effect can be told apart.

## 7. James's steps

1. Create the `vitruvian-arc` GitHub App (browser), install it on
   `vitruvian-core`, and run `seal_arc_github_app.sh` with its key.
2. Approve the `repo-config` PR (fork-approval setting and `QUEUE_RUNNER`),
   which the guard-review ruleset reserves for him.
3. Approve the image's GHCR package visibility if the org requires it.

Everything else, including the charts, the image, the workflow changes, the
conformance rule and the tests, is agent work by pull request.

## 8. Open questions

- Should the scale set be registered at org level instead, so that a runner
  group can be limited to `vitruvian-core` and to public repos explicitly?
  That needs an org admin, and repo level is enough for one repository.
- Phase 2+: Docker jobs. Rootless DinD in the pod, or keep them hosted?
