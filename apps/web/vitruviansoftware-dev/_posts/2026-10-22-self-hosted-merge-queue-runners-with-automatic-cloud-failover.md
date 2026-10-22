---
title: "Self-Hosted Merge-Queue Runners Without the 24/7 Pager: Ephemeral Homelab CI with Automatic Cloud Failover"
description: >-
  When pull requests, the merge queue and main all share one hosted runner pool, merges wait
  behind PR feedback. Here is how we moved vitruvian-core's merge-queue jobs onto throwaway
  homelab runners, behind a one-line routing rule and a canary that fails back to GitHub's
  runners by itself.
date: 2026-10-22 16:00:00 +0000
categories: [ci-cd, kubernetes, platform-engineering, agents, devops]
image: /images/homelab-split-ci-plane.svg
---

Self-hosted CI runners have a reputation. They're cheap and fast until 3 a.m., when a node reboots, the merge queue stops, and someone has to wake up and fix a machine that isn't production but blocks it.

We wanted the capacity without the pager. So we set one rule: **if the homelab runners stop working, CI must carry on without a person doing anything.** Merges might slow down. They must never stop.

This post shows how we built that in [vitruvian-core](https://github.com/VitruvianSoftware/vitruvian-core), our open-source monorepo. It covers the routing rule, the security boundary, the Kubernetes setup and the watchdog that flips CI back to GitHub's runners. Every snippet below is copied from the repository as it is today (licence headers dropped, some comments shortened), and every number comes from our own runs or design notes. Three incidents from the first day are in here too, because they taught us more than the design did.

---

## 1. The problem: agents multiply pull requests

Much of the work in vitruvian-core is done by AI coding agents. Each one works on its own branch, opens its own pull requests and queues its own merges. That is great for throughput, and hard on CI.

On GitHub, an account has a cap on how many hosted jobs run at once. In our repository, three kinds of work shared that cap:

- **pull requests**: every push to every open PR;
- **the merge queue**: GitHub re-tests each approved PR on top of the latest `main` before it lands;
- **pushes to `main`**: the checks and deployments that run after each merge.

More agents means more PRs, more PR pushes, and more queue entries, all drawing from the same pool. Merges ended up waiting in line behind PR feedback.

![The Agent-Multiplier CI Wall](/images/homelab-queue-bottleneck.svg)
*Figure 1: Before, pull requests, the merge queue and main share one hosted pool. After, merge-queue and main jobs get their own homelab runners, and PRs keep GitHub's.*

Here is what that looked like, from our [design spec](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/docs/superpowers/specs/2026-10-19-queue-runners-on-homelab-design.md):

- On **2026-10-19**, **43 runs were queued against 9 running**. A merge-queue rebuild had just added a full batch of jobs.
- Small workflows that normally take **20 seconds took 24 minutes** end to end. Nearly all of that was waiting for a runner.
- From 5 to 19 October, the **p90 time from a PR's first entry into the queue to its merge was 28.5 minutes** (issue [#3518](https://github.com/VitruvianSoftware/vitruvian-core/issues/3518)). In plain terms, one merge in ten waited longer than that.

We had two homelab machines sitting mostly idle: `fedora` (24 cores, 64 GiB) and `nuc9i9` (16 cores, 64 GiB). Both were already nodes in our k3s cluster. The question was how to use them without making them a single point of failure.

---

## 2. The split: trusted work goes home, untrusted work stays on GitHub

The first decision was which jobs the homelab may run. We chose by **who wrote the code**, not by what the job does.

![Split Traffic Plane & Trust Boundary](/images/homelab-split-ci-plane.svg)
*Figure 2: Pull-request jobs, forks included, always run on GitHub's machines. Merge-queue and main jobs may run on the homelab, inside a boundary of six layered controls.*

- **Pull requests stay on GitHub-hosted runners.** vitruvian-core is public and accepts forks. A fork PR runs *its own copy* of our workflow files, so it can change any line, including the one that picks the runner. Code we haven't reviewed should only ever run on a disposable machine GitHub owns.
- **Merge-queue entries and pushes to `main` may use the homelab.** Queue entries are approved PRs. `main` only contains merged code. That code has been reviewed.

This split has a nice side effect. Every job that moves to the homelab hands its hosted slot back to the PR lane, so PR feedback speeds up too.

### The trust boundary, layer by layer

GitHub cannot limit a repository-level runner to certain events. Anything that can edit a workflow can ask for the runner. So no single control is enough, and we layered six:

1. **Fork PRs need approval before any workflow runs**, for every outside contributor. Ours was set to ask only first-time contributors, so anyone with one merged PR could run workflows freely. We changed it to `all_external_contributors`. The Pulumi GitHub provider has no resource for this setting, so our repo-config pipeline sets it through the API after every apply, reads it back, and fails if it didn't take. We made this a hard prerequisite: it had to be in place *before* the runners registered.
2. **Only reviewed code reaches the runners.** That's the routing rule in section 3.
3. **A fresh pod per job, deleted when the job ends**, with no Kubernetes service-account token mounted and no Docker. Nothing survives into the next job: no workspace, no credentials, no cache.
4. **Pod Security "baseline" is enforced** on the namespace: no privileged pods, host namespaces, host paths or extra capabilities. We'd prefer "restricted", but it forbids the privilege escalation that `sudo` needs, and our Bazel setup step runs `sudo dpkg -i`. So "restricted" is set to warn and audit only.
5. **Network egress is DNS plus the public internet on ports 80 and 443.** The pods cannot reach the cluster, the LAN or the tailnet. A job can talk to GitHub, BuildBuddy and package mirrors, and nothing in the house.
6. **Same secrets as on hosted runners.** A job gets `BUILDBUDDY_API_KEY` and its own `GITHUB_TOKEN`. Nothing from the cluster.

Here is the egress policy, from [`network-policy.yaml`](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/gitops/argocd/platform/actions-runners-manifests/network-policy.yaml). It is allow-only on purpose: a deny rule on the cluster range would also block DNS.

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: runners-egress
  namespace: arc-runners
spec:
  endpointSelector: {}
  egress:
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
    - toCIDRSet:
        - cidr: 0.0.0.0/0
          except:
            - 10.0.0.0/8
            - 172.16.0.0/12
            - 192.168.0.0/16
            - 100.64.0.0/10
            - 169.254.0.0/16
            - 127.0.0.0/8
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
            - port: "80"
              protocol: TCP
```

One thing keeps the homelab runners light: **both lanes share the same BuildBuddy remote cache.** Most Bazel actions in a queue run are cache downloads, not compiles, so a runner pod doesn't need to build much from scratch.

**To adopt this:** split by trust first, then by capacity. Before you register any self-hosted runner on a public repository, require approval for workflow runs from *all* outside contributors, not just first-timers. Write the egress policy before the first job runs, not after.

---

## 3. One line decides where a job runs

We wanted three things from the routing:

- PRs can never land on the homelab;
- a person can send every job back to GitHub with one change;
- a robot can send every job back to GitHub with no change from anyone.

All three fit in a single `runs-on` line, which every routed job carries verbatim:

{% raw %}
```yaml
runs-on: ${{ (github.event_name == 'merge_group' || (github.event_name == 'push' && github.ref == 'refs/heads/main')) && vars.QUEUE_RUNNER == 'on' && vars.QUEUE_RUNNER_FALLBACK != 'on' && 'vitruvian-queue' || 'ubuntu-26.04' }}
```
{% endraw %}

GitHub Actions expressions have no `if/else`, but `a && b || c` works the same way here: if `a` is true it returns `b`, otherwise `c`. (That trick only works when `b` is a non-empty string. Ours is `'vitruvian-queue'`.)

![The Single-Line runs-on Expression & Conformance Gate](/images/homelab-runs-on-circuit-breaker.svg)
*Figure 3: Three gates in series. Any "no" sends the job to GitHub-hosted `ubuntu-26.04`, exactly as before the change. A test rejects every other way of naming the runner.*

Read it as three gates:

1. **Is this trusted work?** The event must be `merge_group`, or a `push` to `refs/heads/main`. GitHub sets these values for each run. For a pull request this gate always fails, and the rest of the line never matters.
2. **Is the switch on?** `QUEUE_RUNNER` is a repository variable managed in our Pulumi `repo-config` stack, not by hand. Setting it to `off` sends every job back to GitHub on the next run. No deploy, no workflow edits. That's the human rollback lever. It's `on`/`off` and not empty/non-empty because GitHub doesn't allow empty variable values.
3. **Is the fallback off?** `QUEUE_RUNNER_FALLBACK` is a second variable that **only the watchdog writes** (section 5). `repo-config` never touches it, so an infrastructure apply can't undo an automatic failover. If the variable doesn't exist, `!= 'on'` is true, so a missing fallback means "homelab allowed".

Notice what the variable *can't* do. `QUEUE_RUNNER` is a switch, not a label. The label `vitruvian-queue` is written into the workflow itself. Someone who can change a variable can't use it to point jobs at a different runner.

### The conformance gate

A rule that lives in many workflow files will drift. Someone will write `runs-on: vitruvian-queue` to test something, and forget it. So a test holds the line exactly. [`tools/ci/queue-runner-routing.sh`](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/tools/ci/queue-runner-routing.sh) scans every workflow. Any non-comment line that mentions the runner label or the `QUEUE_RUNNER` variables must *be* the rule, character for character:

{% raw %}
```bash
DIR="${1:?usage: queue-runner-routing.sh <workflows-dir>}"
ROUTED="runs-on: \${{ (github.event_name == 'merge_group' || (github.event_name == 'push' && github.ref == 'refs/heads/main')) && vars.QUEUE_RUNNER == 'on' && vars.QUEUE_RUNNER_FALLBACK != 'on' && 'vitruvian-queue' || 'ubuntu-26.04' }}"

fail=0
for f in "$DIR"/*.yaml; do
  [ "$(basename "$f")" = queue-runner-watch.yaml ] && continue
  n=0
  while IFS= read -r line; do
    n=$((n + 1))
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in '#'*) continue ;; esac
    case "$line" in
      *vitruvian-queue* | *QUEUE_RUNNER*)
        # Same text, any indentation or "- " list marker, nothing else on the line.
        body="${trimmed#- }"
        if [ "$body" != "$ROUTED" ]; then
          echo "queue-runner-routing: $f:$n names the homelab runner outside the one allowed rule:" >&2
          echo "    $trimmed" >&2
          fail=1
        fi ;;
    esac
  done <"$f"
done
```
{% endraw %}

It runs as a Bazel test, `bazel test //tools/ci:queue_runner_routing_test`, over every workflow file in the repository. So `runs-on: vitruvian-queue` fails, an `if: vars.QUEUE_RUNNER == 'on'` fails, and the rule with a single character changed fails. The one exemption is the watchdog's own workflow, which has to name the runner directly because it *is* the probe.

To be clear about what this protects: the test guards **our** workflows from mistakes. It can't stop a fork, which runs its own copy of the files. Fork approval (layer 1 above) is what stops a fork.

The pilot routed four small workflows in PR [#3551](https://github.com/VitruvianSoftware/vitruvian-core/pull/3551): `actionlint`, `release-scope`, `migration-safety` and `conformance-check`. Each one carries a comment that points at the test, like this one from [`conformance-check.yaml`](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/.github/workflows/conformance-check.yaml):

{% raw %}
```yaml
jobs:
  conformance-check:
    # Homelab runner for merge-queue and main jobs when QUEUE_RUNNER is on and the
    # fallback is off; GitHub-hosted otherwise, and always for pull requests
    # (tools/ci/queue-runner-routing.sh holds this line exact).
    runs-on: ${{ (github.event_name == 'merge_group' || (github.event_name == 'push' && github.ref == 'refs/heads/main')) && vars.QUEUE_RUNNER == 'on' && vars.QUEUE_RUNNER_FALLBACK != 'on' && 'vitruvian-queue' || 'ubuntu-26.04' }}
```
{% endraw %}

If you use [actionlint](https://github.com/rhysd/actionlint), add your runner's label to `self-hosted-runner.labels` in `.github/actionlint.yaml`, or it will flag the label as unknown.

**To adopt this:** copy the line and swap in your own label and hosted image (`ubuntu-latest`, say). Create both variables, with the switch managed in code if you can. Copy the routing check and run it in CI. Then move one small, boring workflow first.

---

## 4. Inside the cluster: Actions Runner Controller on k3s

The runners themselves are GitHub's [Actions Runner Controller](https://github.com/actions/actions-runner-controller) (ARC), installed with its two upstream Helm charts as they ship. We didn't fork them. Argo CD deploys both from ApplicationSets.

![Inside the K3s Cluster](/images/homelab-arc-k3s-topology.svg)
*Figure 4: The ARC listener sits on the control-plane servers and asks GitHub how many jobs are waiting. The controller creates one runner pod per job on `fedora` or `nuc9i9`. Each pod registers, runs one job, and is deleted.*

How a job flows, in three steps:

1. A **listener** pod keeps a long-running connection to GitHub, asking how many `vitruvian-queue` jobs are waiting.
2. When the number goes up, the **controller** creates that many runner pods, up to the limit.
3. Each **runner pod** registers with GitHub for exactly one job, runs it, and is deleted.

The scale-set values, from [`actions-runners/applicationset.yaml`](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/gitops/argocd/platform/actions-runners/applicationset.yaml):

```yaml
githubConfigUrl: https://github.com/VitruvianSoftware/vitruvian-core
githubConfigSecret: vitruvian-arc-github-app
# The runs-on label workflows name.
runnerScaleSetName: vitruvian-queue
minRunners: 0
# Fits fedora (24c/64G) and nuc9i9 (16c/64G) beside what they run.
maxRunners: 8
controllerServiceAccount:
  namespace: arc-system
  name: arc-gha-rs-controller
# The listener holds the long poll that tells the controller to start
# runners: keep it on the always-on servers, not a laptop.
listenerTemplate:
  spec:
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: node-role.kubernetes.io/control-plane
                  operator: Exists
    containers:
      - name: listener
template:
  spec:
    automountServiceAccountToken: false
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: kubernetes.io/hostname
                  operator: In
                  values: [fedora, nuc9i9]
    containers:
      - name: runner
        image: ghcr.io/vitruviansoftware/vitruvian-ci-runner@sha256:b06b5d1249f6c4442ca4a23f5579858acdab236a9773d3d83c98ab801582dfc8
        command: ["/home/runner/run.sh"]
        resources:
          requests:
            cpu: "4"
            memory: 8Gi
          limits:
            cpu: "8"
            memory: 16Gi
        securityContext:
          runAsNonRoot: true
          runAsUser: 1001
          privileged: false
          # setup-bazel runs `sudo dpkg -i`; sudo needs it.
          allowPrivilegeEscalation: true
```

A few choices worth explaining:

- **The runners register on one repository, not the organisation.** ARC logs in as a dedicated GitHub App, `vitruvian-arc`, installed only on vitruvian-core. It has *Administration: read & write*, which GitHub requires to register runners, and *Metadata: read*. The key lives in a SealedSecret.
- **The controller watches one namespace** (`watchSingleNamespace: arc-runners`), so it doesn't need cluster-wide rights to manage one runner set.
- **`minRunners: 0`.** The design proposed one warm pod. We run zero for now, so each job waits for a pod to start and register first. This is a knob we'll revisit once we have timings.
- **`maxRunners: 8` at 4–8 CPU each** fits beside the other workloads on both nodes. Laptops in the cluster never run runner pods.

### Two incidents on day one, and the fixes that stayed

We turned the pilot on early on 20 October. Within hours, two problems showed up that no design review would have caught.

**The controller couldn't resolve DNS ([#3562](https://github.com/VitruvianSoftware/vitruvian-core/pull/3562)).** Our cluster network uses Cilium, which gives every pod a security "identity" based on its labels and service account. The ARC controller's labels plus its service account mapped to identity `16648`. On 20 October, any pod with that identity got **no DNS replies on any node**. Queries left the node and nothing came back, with no drop logged and a healthy endpoint. The controller couldn't look up `api.github.com`, so **no runner could start for 40 minutes**. The same labels with a different service account worked, and so did the same service account with different labels.

We never found the cause inside Cilium. The fix that stuck is one meaningless label, which moves the pod to a new identity:

```yaml
# gha-runner-scale-set-controller values
podLabels:
  vitruvian.dev/cilium-identity: "2"
flags:
  # Least privilege: no cluster-wide watch for one scale set.
  watchSingleNamespace: arc-runners
nodeSelector:
  kubernetes.io/arch: amd64
```

The label was first patched onto the live Deployment by hand during the incident. The PR made it permanent, so the next Helm render can't quietly drop it. A hand fix that only lives in the cluster is a regression waiting for the next sync.

**The listener landed on a laptop ([#3564](https://github.com/VitruvianSoftware/vitruvian-core/pull/3564)).** The listener is the one pod that tells the controller to start runners. The scheduler put it on `james-mbp16`, a MacBook on Wi-Fi. The fix is the `listenerTemplate` affinity above: control-plane servers only. We already apply the same rule to CoreDNS.

### The runner image and its written contract

GitHub's stock runner image wasn't enough. Our queue jobs were written for GitHub's hosted `ubuntu-26.04` image, and our Bazel setup step installs two Ubuntu 26.04 packages with `sudo dpkg -i`, which an older base can't do. So we build `vitruvian-ci-runner` from [`tools/ci-runner/Dockerfile`](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/tools/ci-runner/Dockerfile), with every input pinned:

```dockerfile
FROM ubuntu:26.04@sha256:c098726dd9b9733f3e885f8de0ef375206a311b0a317eadc40d347b1115fb944

ARG RUNNER_VERSION=2.338.0
ARG RUNNER_SHA256=af4b794c1bc41d73d40535e3fe092a39f9679cd8d965954c2aca25a05ca41d32

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl gh git git-lfs gnupg jq lsb-release \
      nodejs npm python3 python3-pip python3-venv shellcheck sudo tzdata \
      unzip xz-utils zip zstd \
 && rm -rf /var/lib/apt/lists/*

# GitHub's hosted image ships bazelisk as `bazel`; the queue jobs run `bazel`
# directly, so it must be on the PATH. Pinned by SHA-256.
ARG BAZELISK_VERSION=1.27.0
ARG BAZELISK_SHA256=e1508323f347ad1465a887bc5d2bfb91cffc232d11e8e997b623227c6b32fb76
RUN curl -fsSL -o /usr/local/bin/bazelisk \
      "https://github.com/bazelbuild/bazelisk/releases/download/v${BAZELISK_VERSION}/bazelisk-linux-amd64" \
 && echo "${BAZELISK_SHA256}  /usr/local/bin/bazelisk" | sha256sum -c - \
 && chmod 0755 /usr/local/bin/bazelisk \
 && ln -s bazelisk /usr/local/bin/bazel

# The runner user, uid 1001 as ARC's pods run it, with passwordless sudo.
RUN useradd --create-home --uid 1001 --shell /bin/bash runner \
 && echo 'runner ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/runner \
 && chmod 0440 /etc/sudoers.d/runner

WORKDIR /home/runner
RUN curl -fsSL -o runner.tar.gz \
      "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
 && echo "${RUNNER_SHA256}  runner.tar.gz" | sha256sum -c - \
 && tar -xzf runner.tar.gz \
 && rm runner.tar.gz \
 && ./bin/installdependencies.sh \
 && rm -rf /var/lib/apt/lists/* \
 && chown -R runner:runner /home/runner

USER runner
```

The image is only half of it. The other half is a **written contract** of what our jobs expect from a runner, as a script: [`tools/ci-runner/parity.sh`](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/tools/ci-runner/parity.sh).

```bash
set -euo pipefail
fail=0
check() { if "$@" >/dev/null 2>&1; then echo "  ok: $*"; else echo "  FAIL: $*" >&2; fail=1; fi; }

. /etc/os-release
check test "$VERSION_ID" = 26.04
check test "$(id -un):$(id -u)" = runner:1001
check sudo -n true # setup-bazel's `sudo dpkg -i`
check sudo -n dpkg --version
for tool in git git-lfs gh curl jq python3 node npm npx shellcheck unzip zip xz zstd gcc g++ make tar gpg; do
  check command -v "$tool"
done
check test -x /home/runner/run.sh
check /home/runner/bin/Runner.Listener --version
# Bazel: the jobs run `bazel` directly, as on the hosted image, so both names
# must be on the PATH (not fetched at check time), at the repo's version.
check command -v bazel
check command -v bazelisk
check env USE_BAZEL_VERSION="${BAZEL_VERSION:-9.3.0}" bazel --version

[ "$fail" -eq 0 ] && echo "parity: OK" || { echo "parity: FAILED" >&2; exit 1; }
```

It runs in two places:

- **In the image's own CI, before every push to the registry.** A missing tool fails the image build, not the merge queue.
- **Inside every canary run on the live runners** (section 5). This one catches what the build can't: a running runner on an older image, or a cluster that changed underneath it.

Both lines of defence came from real gaps on 20 October. Reading the pilot workflows turned up tools the hosted image has and ours didn't: `shellcheck`, `node`, `npm` and `gh` ([#3550](https://github.com/VitruvianSoftware/vitruvian-core/pull/3550)). Then the first real queue job on the homelab failed with `bazel: command not found` ([#3559](https://github.com/VitruvianSoftware/vitruvian-core/pull/3559)). The parity script *had* checked Bazel, but it downloaded its own copy into `/tmp` to do it, so it passed for the wrong reason. Now it requires both `bazel` and `bazelisk` already on the `PATH`. A check that installs the thing it's checking proves nothing. The pod's digest is bumped by pull request after the image workflow publishes, so nothing in the cluster ever pulls `:latest`.

**To adopt this:** install ARC's two charts as they ship. Use a GitHub App scoped to one repository. Pin the listener to machines that are always on. Build your runner image from the same OS as the hosted image your jobs were written for, and write `parity.sh` *before* you route the first job: list every tool your workflows call without installing it first.

---

## 5. The watchdog: a canary, a 4-minute timer and an automatic fallback

This is the part that lets us sleep.

If the homelab dies (power cut, ISP outage, a broken node, the DNS bug above), jobs labelled `vitruvian-queue` just wait. GitHub doesn't time them out quickly. The merge queue stalls, and without a watchdog it stays stalled until a person notices.

So [`queue-runner-watch`](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/.github/workflows/queue-runner-watch.yaml) asks the pool for a job and starts a timer somewhere the pool can't take down with it.

![The 4-Minute Canary Watchdog Loop](/images/homelab-canary-watchdog-loop.svg)
*Figure 5: Each run starts two jobs at once: a canary on the homelab and a watcher on GitHub's runners. After 240 seconds the watcher reads the canary's status and sets `QUEUE_RUNNER_FALLBACK` to match.*

The workflow, without its licence header and with some comments shortened:

{% raw %}
```yaml
name: queue-runner-watch

on:
  # - merge_group: queue activity is the demand for the homelab runners, and a
  #   dead pool shows up as a stalled queue, where nothing merges and nothing
  #   pushes. Without this trigger the failure this guards against is the one
  #   case in which it never runs (found on 2026-10-20).
  # - push to main: after every merge.
  # - schedule: GitHub's cron is best-effort; this one had not fired once in
  #   several hours. Kept for quiet periods, off-peak minutes.
  merge_group:
  push:
    branches: [main]
  schedule:
    - cron: '7,17,27,37,47,57 * * * *'
  workflow_dispatch: {}

permissions:
  contents: read

# One watcher per commit, none cancelling another: a burst of queue events must
# not keep killing the running watcher before its 4-minute wait finishes.
concurrency:
  group: queue-runner-watch-${{ github.sha }}
  cancel-in-progress: false

jobs:
  # Runs on the homelab. Named "canary": the watcher looks it up by name.
  canary:
    if: ${{ vars.QUEUE_RUNNER == 'on' }}
    runs-on: vitruvian-queue
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
          sparse-checkout: |
            tools/ci-runner
            .bazelversion
      # A runner that starts but cannot run the queue's jobs fails here,
      # and the fallback goes on.
      - name: The runner image has what the queue jobs need
        run: BAZEL_VERSION="$(cat .bazelversion)" bash tools/ci-runner/parity.sh

  watch:
    if: ${{ vars.QUEUE_RUNNER == 'on' }}
    runs-on: ubuntu-26.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      # Writing a repository variable and cancelling a run need more than the
      # workflow's own read-only token.
      - name: Mint a GitHub App token
        id: app-token
        uses: ./.github/actions/mint-pulumi-app-token
        with:
          client-id: ${{ vars.PULUMI_APP_CLIENT_ID }}
          private-key: ${{ secrets.APP_PRIVATE_KEY }}
          owner: ${{ github.repository_owner }}

      - name: Wait for the canary, then set or clear the fallback
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
          REPO: ${{ github.repository }}
          RUN_ID: ${{ github.run_id }}
          WAIT_SECONDS: '240'
        run: bash tools/ci/queue-runner-watch.sh
```
{% endraw %}

And the decision, in [`tools/ci/queue-runner-watch.sh`](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/tools/ci/queue-runner-watch.sh):

```bash
set -euo pipefail

GH="${GH_BIN:-gh}"
: "${REPO:?}" "${RUN_ID:?}"
JOB="${CANARY_JOB:-canary}"
VAR=QUEUE_RUNNER_FALLBACK

sleep "${WAIT_SECONDS:-240}"

state="$("$GH" api "repos/${REPO}/actions/runs/${RUN_ID}/jobs" \
  --jq ".jobs[] | select(.name == \"${JOB}\") | \"\\(.status) \\(.conclusion // \"\")\"")"
[ -n "$state" ] || { echo "queue-runner-watch: no job named '${JOB}' in run ${RUN_ID}" >&2; exit 1; }
status="${state%% *}"
conclusion="${state#* }"

case "$status:$conclusion" in
  in_progress:* | completed:success)
    want=off
    why="the canary $status${conclusion:+ ($conclusion)}: homelab runners are taking jobs" ;;
  *)
    want=on
    why="the canary is '${status}${conclusion:+ / $conclusion}' after ${WAIT_SECONDS:-240}s: homelab runners are not taking jobs" ;;
esac

# A failed read still prints the API's error body on stdout (a 404 for a variable
# that does not exist yet), so only a read that succeeds AND says on or off is a
# value; anything else is treated as not set, and the variable is created.
if current="$("$GH" api "repos/${REPO}/actions/variables/${VAR}" --jq .value 2>/dev/null)"; then
  case "$current" in on | off) ;; *) current=missing ;; esac
else
  current=missing
fi
echo "queue-runner-watch: ${why}; ${VAR} is '${current}', want '${want}'"

if [ "$current" != "$want" ]; then
  if [ "$current" = missing ]; then
    "$GH" api -X POST "repos/${REPO}/actions/variables" -f name="$VAR" -f value="$want" >/dev/null
  else
    "$GH" api -X PATCH "repos/${REPO}/actions/variables/${VAR}" -f value="$want" >/dev/null
  fi
  if [ "$want" = on ]; then
    echo "::warning::queue jobs fall back to GitHub-hosted runners: ${why}"
  else
    echo "queue jobs return to the homelab runners"
  fi
fi

# A canary nobody picked up must not wait in the queue for a runner that may
# come back hours later.
if [ "$want" = on ] && [ "$status" != completed ] && [ "$status" != in_progress ]; then
  "$GH" api -X POST "repos/${REPO}/actions/runs/${RUN_ID}/cancel" >/dev/null || true
fi
```

The logic fits on one card:

| Canary after 240 s | What it means | Fallback |
|---|---|---|
| running, or finished green | a runner took the job and can run our tools | `off`: use the homelab |
| still queued | no runner took it: cluster, power, network or controller is down | `on`: use GitHub |
| failed or cancelled | a runner started but can't run our jobs | `on`: use GitHub |

Recovery is automatic too. When the homelab comes back, the next canary runs, and the fallback goes back to `off`. The script only writes when the answer changes, so the variable's "last updated" time tells you when the last failover or recovery happened.

### The bug that matters most: the watchdog couldn't see the failure it was built for

The first version ran on a schedule and after every push to `main`. That sounds thorough. In an **outage test** on 20 October we found it was blind to the one failure it existed for:

1. The runner pool dies.
2. Queue jobs wait for a runner that never comes, so **nothing merges**.
3. Nothing merges, so **nothing is pushed to `main`**, and the push trigger never fires.
4. GitHub's cron is best-effort. Ours **hadn't fired once in several hours.**

So the watcher never ran in the exact situation it was built for. PR [#3570](https://github.com/VitruvianSoftware/vitruvian-core/pull/3570) added the `merge_group` trigger. Now **the stalled queue itself starts the check**: any new queue entry starts a watcher, and within about four minutes the fallback is on.

The same PR fixed concurrency. The first version used one shared group with `cancel-in-progress: true`, so a burst of queue events would keep killing the running watcher before its 4-minute wait finished. Now each commit gets its own group and nothing cancels anything. (A constant group with `cancel-in-progress: false` doesn't work either: GitHub still evicts *pending* runs in a group when a newer one queues, and our repository's conformance check rejects constant groups for that reason.)

Two more first-day fixes are worth copying:

- **The canary checks the image, not just the pod** ([#3563](https://github.com/VitruvianSoftware/vitruvian-core/pull/3563)). "A pod started" isn't the same as "our jobs can run". Since the canary runs `parity.sh`, a runner missing `bazel` fails the canary and turns the fallback on. The wait went from 3 to 4 minutes to fit the checkout and the checks.
- **A 404 is not a value** ([#3568](https://github.com/VitruvianSoftware/vitruvian-core/pull/3568)). On its very first live run, the script read a variable that didn't exist yet. `gh` printed the API's error body on stdout and exited 1, and the script took that error text for the value. It then tried to `PATCH` a variable that didn't exist, and failed. Now only a successful read that says exactly `on` or `off` counts. Anything else means "missing", and the script creates the variable. The test's fake `gh` now prints the 404 body on stdout, like the real one.

### What the live data says

As of writing, the 200 most recent `queue-runner-watch` runs (21–22 October) were **198 successes and 2 still running**. None failed. `QUEUE_RUNNER_FALLBACK` was last written on 20 October at 09:44 UTC, during the setup day, and has said `off` since.

The triggers tell their own story. Of those 200 runs, **101 came from `merge_group`, 88 from pushes to `main`, and 11 from the schedule.** A cron that fires every 10 minutes should have run about 268 times in that window. It ran 11. If we had relied on the schedule, the watchdog would have been mostly asleep.

**To adopt this:** copy the workflow and the script. Trigger on `merge_group` (or whatever event *creates* demand for your runners), not only on events that need the pool to be healthy first. Make the canary run your own parity checks. Put the watcher on hosted runners, and give it a GitHub App token that can write variables and cancel runs. Keep the fallback variable out of your infrastructure-as-code, so an apply can't undo a failover.

---

## 6. What this costs, and what it doesn't fix

No design is free. Here are the trade-offs we know about.

- **Jobs already waiting aren't moved.** `runs-on` is decided when a job is queued. When the fallback turns on, *new* jobs go to GitHub, but a job that was already waiting for `vitruvian-queue` keeps waiting. Someone has to re-run it, or wait for the merge queue's 60-minute check timeout to drop the entry, which then has to be queued again. Re-routing waiting jobs automatically is the obvious next step.
- **The watcher uses hosted capacity.** Each run holds a GitHub-hosted runner for about four minutes, mostly sleeping. At the rate above, roughly 200 runs in two days, that's around 13 hours of hosted-runner time over about 45 hours. That's about a third of one slot on average, spent on insurance. Watchers that overlap reach the same answer, so the extras only cost minutes.
- **The worst-case gap is about 14 minutes.** With the queue active, a dead pool is caught about 4 minutes after the next queue event. On a quiet day with only the schedule, it's up to 10 minutes between checks plus the 4-minute wait, *if* GitHub's cron fires at all.
- **Some jobs stay on GitHub.** That includes macOS jobs and anything that needs Docker, until we decide on Docker-in-Docker in a later phase. And for now only four workflows are routed. Wider presubmit and CI jobs are phase 2, after a clean week of phase 1.
- **We haven't measured the gain yet.** Phase 3 runs `bazel run //tools/merge-queue-stats` against the 28.5-minute baseline in issue #3518. It overlaps with a separate merge-queue grouping trial (HEADGREEN) running the same weeks, so we're logging dates carefully to tell the two effects apart. We'll publish the numbers, good or bad.
- **The root cause of the DNS failure is unknown.** The label workaround has held, but we don't know *why* Cilium identity 16648 lost DNS. We're treating it as a known unknown, not as fixed.

---

## Adopting this in your own repository

The whole pattern, in order:

1. **Tighten fork approval** to all outside contributors *before* any self-hosted runner registers. Make it code, and check the live value after every apply.
2. **Build a runner image** from the same OS as the hosted image your jobs expect, with every input pinned. Write `parity.sh` and run it in the image's CI.
3. **Install ARC** with its two upstream charts, a single-repository GitHub App, `watchSingleNamespace`, a listener pinned to always-on machines, ephemeral pods with no service-account token, and an egress policy that allows only DNS and the public internet.
4. **Create two repository variables**: a human switch (`off`) and a robot fallback (unset). Manage the switch in code. Never manage the fallback in code.
5. **Add the watchdog** (canary plus watcher), triggered by `merge_group`, `push` and a schedule.
6. **Add the routing check** to CI, so the one-line rule is the only way to name your runner.
7. **Route one small workflow**, turn the switch on, and pull the plug on a runner node on purpose. Watch the fallback turn on and the queue keep moving. We found our worst bug this way, not in an outage.
8. **Widen slowly**, and measure against a baseline you recorded before you started.

The homelab will go down again. A node will reboot for a kernel update, or the power will flicker. When it does, the merge queue will slow down a little, a variable will change, and nobody will need to wake up. That's the deal we wanted from self-hosted CI.

---

*Everything in this post lives in [vitruvian-core](https://github.com/VitruvianSoftware/vitruvian-core): the [design spec](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/docs/superpowers/specs/2026-10-19-queue-runners-on-homelab-design.md), the [watchdog](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/.github/workflows/queue-runner-watch.yaml), the [runner image](https://github.com/VitruvianSoftware/vitruvian-core/tree/main/tools/ci-runner), and the [ARC manifests](https://github.com/VitruvianSoftware/vitruvian-core/tree/main/gitops/argocd/platform). It's MIT-licensed. Take what helps.*
