# Getting past the GitHub Actions bottleneck — RFC

**Date:** 2026-11-13 · **Status:** RFC for feedback (not yet a design) · **Owner:** wren
**Scope:** CI speed from PR to an installable release. GitHub keeps hosting the repo and the merge queue stays the only gate; no new recurring spend.

Written with the Elephant-Goldfish brainstorm: six independent reviewers attacked the problem statement, then the maintainer's answers were folded in. The facts the reviewers worked from are in the appendix. Next step after feedback: a formal design (`/egm-draft` on this file).

## Overview

The starting idea was that changes reach users slowly because we run out of runners. The six reviewers mostly reject that. The data says runners are no longer the main delay on most days. The bad days are driven by the merge queue throwing PRs out, and every PR thrown out also wastes the builds queued behind it.

Facts that drive the conclusion:

- On Nov 13 a job waited a median of 1.6 minutes for a runner (p90 4.9). A queue run took a median of 20 minutes (p90 31). Yet PR open to merged took 369 minutes at p90. About 330 of those minutes are not explained by any number we have.
- PR open to merged p90 was 1,109 minutes on Nov 12, when 7.1% of queue entries failed. It was 369 minutes on Nov 13, at 2.5%. Runner capacity was the same on both days.
- Runner shortage does still hurt at peak. On Nov 3 the p90 wait was 23 to 44 minutes. So the question is how often capacity is the limit, not whether it ever is.
- Nobody has measured merge to installable release. That is half the stated goal.

The brief proposes three alternatives, reshaped from the original three:

- **A. Fewer failures in the queue.** Run tests on the PR before it enters the queue. Quarantine flaky Mac tests. Retry failures caused by infrastructure.
- **B. Cheaper queue runs on a dependable homelab.** Fewer, larger jobs per queue entry. Caches on each machine's own disk, with no shared NFS. Fix the health check. Add a Mac only if measurement shows we need one.
- **C. A fast path from merge to installable.** Measure it first. Then stop release jobs competing with queue jobs for the 5 Mac slots.

Before any of these, spend a day splitting the p90 into its parts. That split decides the order.

The original direction 2 (move heavy builds to a second CI system on the homelab) is set aside. It runs on the same machines that caused the incidents. It adds a second system for one maintainer to look after. If it goes down, the queue gate stalls.

## Analysis

Each finding names the lens or lenses that raised it: design, codebase, zoom-out, comprehension, readiness, structural. Severity: Blocker, Major or Nit.

### 1. The diagnosis and the numbers

- **Blocker. Runner capacity is not the main term on most days.** Runner wait was p90 4.9 minutes against a p90 of 369 minutes from PR open to merge. More runners would save at most about 5 minutes on that day. Queue failure rate tracks the bad days; capacity does not. (design, zoom-out, structural)
- **Blocker. Nobody knows where the time goes.** We have the end-to-end p90 and two of its parts: runner wait and queue run time. Nothing measures human approval wait, time between approval and entering the queue, waiting in the queue, rework after an ejection, the release-please trip, or signing and publishing. ("Ejection" means the queue dropping a PR because a check failed.) Without this split, each direction is a guess. (all six lenses)
- **Blocker. The goal and the data measure different things.** The goal says "approval to merge". Every number we have is "PR open to merged". In a repo where agents open PRs, "approval" has no agreed meaning: a human review, an auto-approve, or entering the queue. "Installable release" is also undefined. A notarized Mac app, an Android build, a CLI binary and an Argo CD sync each finish in a different place. (comprehension, design)
- **Major. The samples do not compare.** Nov 3 covers about 2,000 hosted Linux jobs. Nov 13 covers 102 jobs and may include homelab jobs. The merge-time figures each come from a single day. At about 46 PRs a day, the p90 is roughly the fifth-slowest PR, so one bad PR moves it. Use one method over at least 7 days. (comprehension)
- **Major. Each failure costs about three times its own share.** The queue builds at most 3 entries at once (`infrastructure/pulumi/platform/repo-config/main.go:1928`). With ALLGREEN (the setting that requires every check to pass for every entry), one failure at the front rebuilds the 2 entries behind it. Each rebuild takes 20 to 30 minutes. (design, structural)
- **Major. Cause (b) is our choice, not a GitHub limit.** The queue is the first real test only because the `agent-fast-lane` label skips heavy PR tests. The fast lane moved failures into the queue. It can be narrowed. (comprehension, zoom-out, design)
- **Major. Demand is high per PR.** About 300 runs an hour is about 7,200 a day for 46 merged PRs. That is roughly 150 workflow runs per landed PR, counting release and main runs. Agents push often, and each push starts about 15 small workflows plus Presubmit. (zoom-out)

### 2. What the code shows that the context file missed

- **Blocker. The homelab health check cannot see the most common failure.** The watcher stops polling once the canary job is `in_progress` (`tools/ci/src/queue_runner_watch/lib.rs:298`) and treats that as healthy (`lib.rs:347-348`). A runner that starts but lacks a tool counts as healthy, and missing tools were the most repeated incident. The check also never looks at the NFS cache, the Bazelisk binary or cache speed, which covers the Nov 8 and Nov 9-10 incidents. The workflow header claims otherwise (`.github/workflows/queue-runner-watch.yaml:25-28`). Worst-case failover is about 10 minutes between checks plus 10 minutes of waiting, not the 14 minutes the context file gives. (codebase)
- **Major. Most Linux queue work already runs on BuildBuddy machines.** Linux units use `--config=remote` (`presubmit.yaml:1057`, `tools/remote.bazelrc:4`), and so does `build-test` (`tools/ci/src/affected_targets/lib.rs:275`). This is remote execution: BuildBuddy runs the build steps, not our runner. The homelab pod does the Bazel client work: checkout, fetching dependencies, planning the build, uploading. So the "Bazel 25% slower on the homelab" figure measures client work over a home internet line, not compute. (codebase)
- **Major. The queue probably runs the same tests twice (inferred).** `build-test` builds and tests all affected targets (`lib.rs:280`). The 31 Linux Presubmit units then test the same targets in separate jobs. Each repeats disk cleanup, Bazel setup and the LLVM restore. Both are required checks (`main.go:277-278`). If confirmed, merging them cuts about 33 job claims per queue entry to 2 or 3. (codebase)
- **Major. Any change under `tools/` takes a Mac in the queue.** The macOS path filter includes `tools/**` and both MODULE files (`ci.yaml:520,525-526`). CI tooling PRs are common, so many hold one of the 5 Mac slots. The filter is deliberate: the comment at `ci.yaml:517-519` says the Apple toolchain and the imported `.bazelrc` files live under `tools/`. So narrowing it means listing those exact paths, not dropping `tools/`. (Checked by the Elephant.) If the Presubmit planner fails, all 9 macOS units run (`presubmit.yaml:1001`). (codebase)
- **Major. The cause of issue #1841 looks fixed already.** That issue was the 4h23m block on the push lane. Each app now has its own delivery workflow (`delivery-vitruvian-atrium.yaml:112-117`), and the beta step has no approval gate (`:261-268`). Reviewers who proposed "split release from the push lane" did not know this. The remaining release problem is different (next item). (codebase, corrects design, zoom-out, structural)
- **Major. Getting to "installable" takes two Mac jobs and a second queue trip.** A push to main builds the beta on a hosted Mac (`delivery-vitruvian-atrium.yaml:267`). Production needs the release-please PR to go through the queue again, where the macOS filter matches the app folder. Then it needs another Mac job (`:301-306`). All of these compete for the same 5 Mac slots as PR and queue jobs. GitHub gives no way to put one job ahead of another. (codebase, structural)
- **Nit. Docs have drifted from the live setup.** `main.go:1895-1896` and `applicationset.yaml:21-22` say pushes to main use the homelab; only `merge_group` jobs do (`ci.yaml:213`, `presubmit.yaml:41`). The design spec says one warm pod, a 4-CPU request and a 3-minute canary wait. The live values are no warm pod (`minRunners: 0`), 3.5 CPUs and 600 seconds. With no warm pod, every queue job waits for a fresh pod to start. There are 22 `runs-on: xcode-27` lines, not 20. (codebase)
- **Major (inferred). The shared Actions caches may be stale.** Only hosted jobs on main save them (`.github/actions/setup-bazel/action.yml:294-295`). The main re-test is skipped 90 to 98% of the time (`ci.yaml:206-208`), so saves are rare, and the fallback path may restore old caches. Check the cache creation dates. (codebase)

### 3. Security and the "only gate" rule

- **Major. Required checks match by name only.** No check is pinned to the app that posts it (no `IntegrationId` in `main.go:353-357`). Any app or token that can write statuses could post a green `build-test`. This is true today. It becomes serious if a system outside Actions posts the deciding checks. Pinning is a repo-config change the maintainer must approve himself. (readiness, codebase)
- **Major. Fork code may already reach homelab runners.** Once a fork PR is approved into the queue, its code is in the queue commit, and queue jobs run on the homelab (37 job definitions). A fork PR can also rewrite `runs-on` itself (spec section 5, line 135). The only barrier is the setting that requires approval for outside contributors. This needs an answer before any direction adds homelab work. It may apply to today's setup. (design, codebase)
- **Major. A home Mac must never hold signing secrets.** Release jobs use `VITRUVIAN_SIGNING_CERT_P12` (`delivery-vitruvian-atrium.yaml:286`). Keep signing on hosted runners. That means a home Mac does little for merge to installable. (codebase, readiness)
- **Major. PR runs must not write to the shared cache.** `--remote_upload_local_results` comes from `:remotecache-ci` in `.bazelrc`. If PR code uploads results built on the runner itself, an in-repo PR could poison the cache. PR runs should use remote execution only. (readiness)

### 4. Direction 1: rebuild the homelab runners, add a Tart Mac

- **Major. Mostly a repeat.** Dropping NFS fixes 3 of about 9 incidents: the permission-change stall and the cleanup job deleting cached files (both Nov 8), and the corrupt Bazelisk binary (Nov 9-10). Moving restores off GitHub's cache would also fix the slow transfers (Oct 31, Nov 6). It leaves the DNS failure (Oct 20), runners losing GitHub (Nov 7), images missing tools, dead entries holding all runners (Nov 5), the false fallback switch (Nov 5) and the failover gap. (design, zoom-out, readiness, comprehension, structural)
- **Major. Caches on a machine's own disk conflict with the pod security rule.** The namespace enforces the "baseline" pod security level (`applicationset.yaml` header). Baseline forbids mounting a host folder directly. The choice is one local volume per node, which means one runner pool per node, or a fresh volume per pod, which means cold caches. Someone has to pick before work starts. (readiness)
- **Major. The Mac half is small and unconfirmed.** No Mac is confirmed. Apple's licence allows 2 macOS VMs per Mac, so one Mac mini adds 2 slots to the 5 hosted ones. It adds one machine and one home internet line as single points of failure. A faster machine hides the barrier deadlock (#4534) and the timing flakes; it does not fix them. The repo's rules allow self-hosted runners only on `merge_group` jobs, so the Mac helps only in the queue unless that rule changes. Tart's licence terms need checking. (design, readiness, zoom-out)

### 5. Direction 2: a homelab CI system posts the queue checks

- **Blocker. If it goes down, the gate stalls.** If the system stops posting, every queue entry waits the full 60-minute timeout (`main.go:1925`) before ejection. Nothing falls back to hosted runners. A fallback would have to post as the same pinned app, which puts that app's key into Actions secrets. Nobody has a design for that. (design, readiness, structural)
- **Major. It swaps the part that did not fail.** The incidents came from storage, images, cluster networking and cache location. None came from Actions coordinating jobs. A new CI system runs on the same two machines. (structural, zoom-out, readiness)
- **Major. Every candidate breaks a rule or is unproven.** Buildkite's control plane is paid. BuildBuddy Workflows' free limits are unknown. Tekton has no native queue support and needs an inbound webhook into the homelab, which is new attack surface. Woodpecker's queue support is unknown. Macs stay on Actions, so the 5-slot cap stays. About 114 workflows would need porting. (all lenses)
- **Nit. BuildBuddy Workflows is the only version worth a look.** Linux execution already runs on BuildBuddy, so it would drop the homelab pod, NFS and home uplink from the path. Its free limits could turn into a recurring cost. (codebase)

### 6. Direction 3: verify before the queue

- **Major. It repeats "verified-run" unless CI runs it.** Agents recorded that voluntary laptop run 0 times in 14 days. It only works as a required PR check that CI runs by itself. At that point it means narrowing the fast lane. (all lenses)
- **Major. Most of it exists already.** The PR lane already runs on remote execution (`ci.yaml:402-408`). The fast lane is what skips it (`presubmit.yaml:237-242`). A log-only check that would skip the queue run when the PR already passed the same tree exists (`presubmit.yaml:137-157`, `2075-2090`). It records nothing for fast-lane PRs. (codebase)
- **Major. Cache keys must match.** Remote-execution and cache-only runs produce different keys, which is why the remote cache got zero hits on cold lanes. Unless PR and queue runs use the same settings, the queue rebuilds everything. (design, readiness, structural)
- **Major. It has limits.** It does not cover Macs, because BuildBuddy only caches for macOS. It cannot catch clashes between PRs, which only the queue sees. Fork PRs get no secrets, so they cannot use it. Unless the PR job is a thin client handing work to BuildBuddy, it brings the hosted-runner pressure back. BuildBuddy's free remote-execution limits at about 46 PRs a day are unknown. (design, readiness, comprehension)

### 7. Options the brief missed

- **Quarantine flaky tests first.** Fix #4534. Move the timing tests (#4529, #2712, #2903, #2942) into a set that runs but does not block. Allow one retry for known-flaky tests and for download failures (Bazel's `--flaky_test_attempts`). This costs nothing. (all lenses)
- **Fewer, larger jobs.** Fold the Linux Presubmit units into one `build-test` remote-execution run for queue entries. Fold the 9 macOS units into one or two Bazel runs. (codebase, zoom-out, design, comprehension)
- **Narrow the macOS path filter.** Replace `tools/**` with the Apple toolchain paths. (codebase)
- **Cut runs per push.** Cancel runs that a newer push replaces. Merge the small check workflows. Skip draft agent PRs. (zoom-out)
- **Fail fast in the queue.** Run fast smoke checks before the full build, so a broken entry fails in minutes, not after 20. (design)
- **Switch to hosted runners job by job.** Today one repo-wide variable switches all queue jobs back to hosted runners, and jobs already waiting are not moved. (comprehension, structural)

## The three alternatives

All three keep GitHub hosting the repo and the merge queue as the only gate. None needs a paid plan. None runs fork PRs on our hardware.

### Step zero (before any alternative): split the p90

From the GitHub API, record for each PR: opened, approved, entered the queue, each queue run start, each ejection with its cause, merged, release tagged, asset published. Use 7 to 14 days. Sort each ejection into one of four causes: a real bug the PR's own tests would have caught, a flaky test, an infrastructure failure, or a clash between PRs. `//tools/merge-queue-stats` is the natural home.

Decision rules:
- Ejections and rework over 30% of approval-to-merge p90: start with A.
- Runner wait over 25% of p90 after A: do B.
- Merge to installable over twice approval to merge: move C forward.
- Human approval wait dominating: none of the three fixes it. Say so and stop.

### A. Fewer failures in the queue

**What it is.** CI, not agents, runs the tests a PR affects on the PR itself. It runs after approval and before the PR enters the queue. It uses remote execution with the same settings the queue uses, so the queue reuses the results. Flaky Mac tests move to a non-blocking set. Download and infrastructure failures get one retry. The fast lane shrinks rather than disappears: it still skips tests a PR does not touch.

**What it fixes.** The queue failure rate, which tracks the bad days. Each ejection avoided also saves the 2 entries behind it.

**What it does not fix.** Clashes between PRs. Mac failures that are not flakes (BuildBuddy caches for macOS but does not run the builds). Peak runner shortage. Merge to installable.

**Cost and risk.** No new spend if BuildBuddy's free remote execution covers about 46 PRs a day plus retries; this is unconfirmed. Risk: the PR job claims hosted runners again unless it is a thin client. Risk: cache-key mismatch makes the queue rebuild everything. PR runs must not upload results built on the runner.

**What it reuses.** The PR lane's remote-execution job (`ci.yaml:402-408`). The fast-lane gate (`presubmit.yaml:237-242`). The affected-target planner (`tools/ci/src/agent_fast_lane`). The skip-if-already-tested check (`presubmit.yaml:137-157`). The `release-scope` pattern for a check that passes on both PR and queue events (`main.go:340-350`).

**Kill-or-prove experiment.** Run it in shadow (not required) on fast-lane PRs for one week. Quarantine the top 5 flaky tests at the same time.
- Prove: it would have caught at least 60% of the ejections that followed. Its p90 is 10 minutes or less on one hosted slot per PR. Queue failure rate stays under 2% for 7 days.
- Kill: it catches under 40%.

### B. Cheaper queue runs on a dependable homelab

**What it is.** Two parts. First, each queue entry does less: merge the duplicate Linux Presubmit units into `build-test`'s single remote-execution run, and narrow the macOS filter so `tools/` changes do not take a Mac. Second, the homelab runners become dependable:
- Caches on each machine's own disk, with no shared NFS. Pick between one pool per node and fresh volumes per pod.
- One runner image built from a single tool list and checked before rollout.
- A canary that fails when the image check fails, not when the job merely starts.
- `minRunners` set to 2, so a warm pod is always waiting.
- Switching to hosted runners job by job, which also moves jobs already waiting.

A home Apple Silicon Mac running Tart VMs (Tart runs macOS virtual machines on Apple Silicon; "ephemeral" means each VM is thrown away after one job) comes later. It is added only if step zero shows Mac slots on the critical path. It runs queue jobs only, never signing.

**What it fixes.** Fewer runner claims per queue entry, which helps at peak. The NFS incidents, the blind canary, cold pod starts, needless Mac claims.

**What it does not fix.** DNS and GitHub-connection incidents on the homelab. The 5 hosted Mac slots (a Mac mini adds 2). Flaky tests. Merge to installable.

**Cost and risk.** No recurring cost for the Linux part. The Mac part needs a one-off Mac and power. Risk: caches on one machine go cold when a pod moves to the other. Risk: the merged job becomes one long critical path. Risk: the fork-code question in Analysis section 3 is unresolved.

**What it reuses.** ARC (GitHub's Kubernetes controller that creates self-hosted runners), already running. `tools/ci-runner` and its image check. The canary and `QUEUE_RUNNER_FALLBACK` switch. `gate/all-required-passed` as the single fan-in check. The routing guard.

**Kill-or-prove experiment.**
- First, count how many test targets the two jobs share across 20 queue runs. Prove the merge: at least 90% shared.
- Then put one node on its own disk as a non-required queue lane for 7 days. Prove: job success at least 99.5%, no stall over 10 minutes, Bazel setup under 60 seconds at p90, no false fallback switch. Kill: more than one queue ejection caused by a runner in a week.
- For the macOS filter, prove: under 30% of queue entries claim a Mac.
- For the Mac, borrow one for a day. Run the 9 macOS units under Tart 50 times each. Prove: p90 half of hosted or less, and the barrier deadlock never reproduces.

### C. A fast path from merge to installable

**What it is.** First, measure merge to installable for the last 20 releases of each shipped app. Then remove waste on that path:
- Stop release jobs competing with queue jobs for the 5 Mac slots, for example by running release work when the queue is quiet.
- Build release files from outputs the queue already tested instead of rebuilding.
- Run notarizing without holding a runner while Apple responds.
- Check whether release-please PRs need a full queue trip that matches the macOS filter. Release-please is the tool that opens version-bump PRs.

**What it fixes.** The second half of the goal, which no original direction touched.

**What it does not fix.** Anything before merge.

**Cost and risk.** No new spend. Low risk; it changes workflow wiring, not hardware. The issue #1841 fix seems to be in place already, so the gain may be smaller than expected. We will not know until the baseline exists.

**What it reuses.** The per-app delivery workflows (`delivery-vitruvian-atrium.yaml` and siblings). The delivery generator. The existing skip of the after-merge re-test.

**Kill-or-prove experiment.** Measure the 20-release baseline, then change one product. Prove: that product's merge to installable p90 halves or falls under 60 minutes, with zero runs waiting behind a queue Mac job. Kill: the baseline is already under 60 minutes, so this is not where the time goes.

### Ranked recommendation

1. **A.** It goes straight at the queue failure rate, which tracks the bad days, and it reuses almost everything.
2. **B (Linux part, and merging the duplicate jobs).** It cuts runner claims per queue entry and removes the known homelab failure causes without new spend.
3. **C.** It covers the half of the goal nobody has measured. Run it alongside A, because it touches different files.

The Mac half of B is dropped (no Mac available). In its place, B includes trimming the Mac lane to Mac-only tests (see "Most of the Mac lane is not Mac work"). That is the cheapest measured win for Mac slots, and it can start with no measurement first.

## Goals vs. Non-Goals

**Goals**
- Cut p90 approval to merge, once "approval" has a fixed meaning and a data source.
- Cut p90 merge to installable for each shipped product, once "installable" is defined for each.
- Bring the queue failure rate under 2%, with ejections sorted by cause.
- Keep GitHub hosting the repo and the merge queue as the only gate.
- No new recurring spend. No fork PRs on our hardware. Every change made as code through CI.
- Cut wasted compute: duplicate test runs, needless Mac claims, rebuilds after ejections.

**Non-Goals**
- Paying GitHub for larger runners or higher limits.
- A second CI system as the source of required checks.
- Reducing human approval wait, unless step zero shows it dominates. Then it is a separate decision.
- Running signing or notarizing on home hardware.
- Moving Docker-based jobs to the homelab.

## Alternatives Weighed

- **Original direction 2, a homelab CI system (Tekton, Woodpecker, Buildkite) posting the queue checks.** Rejected. It runs on the same failing machines, adds a second system, and stalls the gate for 60 minutes when it goes down. Buildkite's control plane is paid. Tekton lacks native queue support and needs an inbound webhook. Woodpecker is unknown. Bring it back only if B's shadow run fails for platform reasons rather than storage.
- **BuildBuddy Workflows as the queue check.** Deferred, not rejected. It is the only version of direction 2 that removes the homelab from the path. One-day test first: confirm a $0 tier posts a check on `gh-readonly-queue/*` commits and the queue accepts it.
- **"Verified-run", a laptop BuildBuddy run recorded as a GitHub status.** Tried and abandoned: 0 uses in 14 days. A keeps the idea but has CI run it.
- **A shared NFS cache for the homelab runners.** Tried. It caused the Nov 8 and Nov 9-10 incidents (issue #4429 still open). B replaces it.
- **A queue batch size of 10.** Tried and reverted. 60 or more first-wave jobs blocked position 1.
- **HEADGREEN queue grouping.** Tried and reverted. GitHub cancelled checks on earlier entries and left commits on main with cancelled checks that could not be re-run.
- **Remote cache on cold lanes.** Tried: zero hits, because remote-execution and cache-only keys differ. A must use the same settings in PR and queue to avoid this.
- **target-determinator.** Tried. It never beat a full sweep and then picked the wrong targets.
- **Dropping the agent fast lane completely.** Rejected. PR open to merged p90 was 228 minutes before it. A narrows it instead.
- **Buying a Mac first.** Rejected as a first step. 2 slots do not lift the 5-slot cap much, and a faster Mac hides flakes rather than fixing them.
- **Paying for GitHub capacity.** Ruled out by the maintainer.

## Key Decisions & Staging for Next Steps

1. **Day 1: measure.** Build the per-PR timeline and the ejection causes over 7 to 14 days. Fix the meanings of "approval" and "installable". Apply the decision rules in step zero.
2. **Same week, zero risk:**
   - Fix the canary so a failed image check counts as unhealthy.
   - Quarantine the top 5 flaky tests and fix #4534.
   - Add one retry for download failures.
   - Narrow the macOS path filter.
   - Fix the drifted docs.
3. **Week 1-2: A in shadow** on fast-lane PRs. Decide from the catch rate.
4. **In parallel: C's baseline**, then change one product.
5. **Week 2-3: B.** Count the shared targets, then merge the duplicate jobs. Run the one-node local-disk lane in shadow for 7 days.
6. **Only if step zero shows Mac slots on the critical path:** borrow a Mac and run the Tart test.
7. **Before adding any homelab work:** answer the fork-code question. Pin the required checks to their app (maintainer approval needed).

Decisions needed:
- Pick a cache layout under the "baseline" pod security rule: one pool per node, or fresh volumes per pod.
- Decide whether a home Mac may run PR jobs from trusted in-repo PRs, or only queue jobs.
- Set the numeric targets.

## Answers found in the repo (2026-11-13)

- **"Approval" (Q1).** No human approval is required: `requiredApprovals: "0"` in `infrastructure/pulumi/platform/repo-config/Pulumi.dev.yaml:31`. For an agent PR, "approval" therefore means the moment it is queued (auto-merge armed by `pr-enqueue`). Step zero measures from that event.
- **Fork PRs in the queue (Q3).** Of the last 1,000 merged PRs, 0 came from a fork. The exposure is real in principle (a maintainer or agent app could queue a fork PR, and its code would run on homelab queue runners) but has not happened in this window. The live fork-approval setting could not be read (API returned 403 to the agent app). Recommendation: add a check that fails any `merge_group` run whose head came from a fork, so the rule is enforced in code instead of by habit.
- **BuildBuddy free limits (Q7).** The free Personal plan lists up to 80 Linux cores of remote execution and 100 GB of cache transfer; BuildBuddy says it does not hard-block overage but will contact you. Mac remote execution is paid. Our actual monthly transfer is not yet measured: check the BuildBuddy usage page before A or B adds remote-execution load.

## Most of the Mac lane is not Mac work (measured 2026-11-13)

The maintainer asked whether macOS builds are truly macOS-only. Mostly not.

- **What the Mac jobs test.** The 9 macOS Presubmit units plus `ci.yaml` `macos-build` test 109 targets. Only 13 are Swift tests. The rest: Rust tests, 28 Go tests, 4 Kotlin tests, 2 Python tests, 1 Jest test.
- **How many are tied to macOS.** 32 of the 109 declare that they need macOS. 77 tests that are not Swift declare no macOS need.
- **Most of those already pass on Linux every night.** The nightly Linux sweep (`periodic-full-sweep.yaml`, `bazel test //...` on BuildBuddy Linux machines) ran 517 tests on Nov 13: 510 passed, 7 skipped. Of the 77, 5 are tagged `manual`, which keeps them out of that sweep, and 3 pick their behaviour by OS. That leaves about 69 that run and pass on Linux each night.
  - Confidence: the totals are verified. That each of the 69 passed is inferred, because the sweep log does not list targets one by one (`--show_result=20`).
  - 9 of the 77 are also named in a Linux Presubmit unit, so they run twice in every queue entry.
- **Example: `vitruvian-courier-engine-macos`.** It runs all 27 of the engine's Go tests on a Mac for about 12 minutes (median). Its BUILD file says why: one Signal library builds only on macOS, so only the Signal link test needs a Mac. The same Go tests already run on Linux (`go-race`, `build-test`).
- **What Mac slots cost today.** Over the last 40 Presubmit runs there were 37 Mac jobs: 305 Mac-minutes, a median of 6.1 minutes each. Waiting for a free Mac took 2.1 minutes at the median, 12.9 minutes at p90 and 18.8 minutes at worst. That wait is the 5-Mac-slot cap at work.

**Fix (folds into B, zero cost):** each macOS unit tests only the targets that need macOS (Swift, app bundles, signing, anything restricted to macOS). Everything else moves to, or stays in, the Linux remote-execution lanes.
- **Prove it:** move the 77 to Linux in one PR. They must pass there. Mac-minutes per queue entry must drop by at least half, and p90 Mac wait must fall under 5 minutes over 7 days.
- **Check first:** whether each of the 3 tests that pick their behaviour by OS, and the 5 `manual` ones, genuinely needs a Mac.
- **Release side (unverified idea):** building `.app` bundles needs a Mac. Notarizing is a network round trip to Apple, so it could be split into a job that does not hold a Mac slot while it waits. Measure how long notarizing takes first.

## Maintainer answers (2026-11-13)

- **Target.** Halve today's times, measured as the 7-to-14-day p90 from step zero: queued → merged, and merge → installable. One target for both halves; the Mac apps are measured separately but held to the same "half" rule.
- **Mac candidate: james-mbp32 (checked).** An M1 Pro with 10 cores and 32 GB, so the hardware is about 3x the hosted 3-core Mac. But it is a k3s node today. Its cluster VM holds 8 of the 10 cores and 20 GB of the memory, and only 40 GB of disk is free. It could only build after leaving the cluster.
- **Ruled out** by the maintainer (2026-11-13). No home Mac is planned, and the Mac half of B is dropped unless a different machine appears. The Mac-lane trim below does more for Mac slots anyway.
- **Pinning the required checks is out of scope.** It does not speed anything up. It only matters if a second system posts the deciding checks (direction 2), which is set aside. Kept as a separate security note, not part of this effort.
- **Flaky tests: adopted, Google's way (maintainer decision).** Google treats flakiness as a measured, owned defect, not noise: failures are retried to tell flakes from real breaks, known-flaky tests are kept from blocking submits while they are fixed, each gets an owner and a bug, and Bazel's `flaky = True` is a last resort. Applied here: (1) in the queue, a failed test is rerun once; fail-then-pass on the same code marks it flaky and records it, never silently passes. (2) A flaky test moves to a non-blocking set with an issue, an owner and a 14-day deadline: fix it or delete it. (3) Never quarantined: signing, notarizing, release packaging, security and migration-safety checks. (4) Track the flake rate weekly and alert when it rises.

## Open questions for the maintainer

All seven original questions are answered above. Remaining, for step zero to settle:
1. What counts as "installable" for each product? Working default: the release asset is published (DMG on the GitHub release or Homebrew tap, APK, CLI binary, Argo CD sync done).
2. Does our monthly BuildBuddy cache transfer stay under the free 100 GB once the Mac lane's Linux-capable tests move to remote execution? Read the usage page before and after.

## Appendix: facts the reviewers worked from

Gathered 2026-11-13 from the repo's issues, PRs, docs, agent notes, live Actions data and web search.
"Verified" = read in a primary source or measured. "Inferred" = reasoning, not confirmed.

### The repo and the team
- One public monorepo on GitHub (VitruvianSoftware/vitruvian-core), Bazel build, about 114 workflow files.
  Products: Go/TypeScript CLIs and web apps, Swift macOS apps (several shipped to users, signed + notarized),
  Kotlin Android apps, ESP32 firmware, Pulumi infrastructure, a homelab k3s cluster managed with Argo CD.
- One human maintainer plus many AI agents opening PRs in parallel. About 46 PRs/day went through the merge
  queue (Oct 5–19). Live sample: 1,000 workflow runs in 3h18m on 2026-11-13 (~300 runs/hour).
- Hard constraints from the maintainer: GitHub keeps hosting the repo. No paying GitHub (he ruled out raising
  paid limits). General stance: avoid any new recurring cost unless clearly worth it. GitHub's merge queue
  must stay the single gate that decides what lands; never merge around it or weaken it. All infra changes go
  through CI/CD as code. Wasted compute is treated as seriously as a broken build. Fork PRs must never run on
  self-hosted hardware (public repo).

### How CI works today
- PR: Presubmit (generated, ~41 per-unit jobs chosen by a dependency-map planner) + CI + ~15 small checks.
  Agent PRs labelled `agent-fast-lane` skip the heavy PR tests, so the merge queue is often their first real test.
- Merge queue: squash, ALLGREEN, max 3 entries building / 3 merging, 60-min check timeout, 18 required checks.
- After merge to main: re-test skipped when the queue already tested the same tree (90–98% skipped, 0 bad commits).
- Delivery/release: generated per-product workflows (release-please), macOS signing/notarizing, approval gates.
- Remote build execution and cache: BuildBuddy (one shared key; free/OSS usage; Linux only — macOS uses cache only).
- One 10 GiB GitHub Actions cache budget for the whole repo; repeatedly over budget and evicting (11.1 GiB Aug 20,
  10.9 GiB Oct 7). Mitigated by pruning dead PR/queue caches and moving dependency maps to git refs.

### Runner pools (verified)
- GitHub-hosted Linux (`ubuntu-26.04`): ~140 job definitions.
- GitHub-hosted macOS (`xcode-27`, a preview image, 3 cores): 20 job definitions — 9 presubmit macOS units
  (20–60 min timeouts), `macos-build` (45 min), and release/delivery jobs for the shipped Mac apps.
- GitHub Free plan limits (GitHub docs, via web search): 20 concurrent jobs total on hosted runners, of which at
  most 5 macOS. Jobs over the limit queue. Public repos pay nothing for hosted minutes or self-hosted runners.
  Measured: only 14–20 hosted jobs ran at once under load (PR #4316).
- Self-hosted `vitruvian-queue`: GitHub Actions Runner Controller (ARC, gha-runner-scale-set 0.15.1) on the homelab
  k3s cluster, nodes `fedora` (24 cores/64 GiB) and `nuc9i9` (16 cores/64 GiB). Up to 8 ephemeral pods
  (3.5 CPU / 8 GiB request, 8 CPU / 16 GiB limit). Shared 80 GiB NFS volume on a NAS for Bazel repository cache
  and Bazelisk, pruned weekly. Only merge-queue Linux Bazel jobs route there (37 job definitions), never PRs.
  A watcher workflow (`queue-runner-watch`) runs a canary; if the pool is dead it flips a repo variable
  `QUEUE_RUNNER_FALLBACK=on` and jobs go back to GitHub-hosted runners.

### Measured pain (verified)
- Runner wait, Nov 3, ~2,000 hosted Linux jobs: p50 5 min, p90 23–44 min, p99 ~86 min, for jobs that ran ~3 min.
- Oct 14: small jobs waited 2.3 min (p90 7.6) to do 0.3 min of work; waiting was 41% of Presubmit's critical path.
- Oct 19: 43 runs queued vs 9 running; 20-second workflows took 24 minutes.
- Live sample Nov 13 (102 jobs in merge-queue/PR CI and Presubmit): queue wait median 1.6 min, p90 4.9, max 10.2.
  Merge-queue Presubmit median 20 min (p90 31), merge-queue CI median 17 min (p90 23).
- PR open → merged p90 for non-fast-lane PRs: 228 min before the fast-lane experiment; 1,109 min on Nov 12;
  369 min on Nov 13. Queue failure rate 7.1% on Nov 12 (baseline 2–3%), 2.5% on Nov 13.
- An approval-gated delivery run blocked the push lane for 4h23m (issue #1841).
- Homelab pilot: 96/96 jobs passed, 7-second median wait, end-to-end 2–10x faster (actionlint 342s → 31s),
  but Bazel steps ~25% slower than on hosted runners.

### Homelab runner incidents (verified, Oct 20 – Nov 10)
- Oct 20: runner controller got no DNS replies (Cilium identity issue, root cause unknown) + image lacked bazel; ~1.5h stall.
- Oct 31: cache uploads from homelab to GitHub's cache at ~1.8 MB/s vs ~300 MB/s from hosted; jobs hit the 45-min timeout.
- Nov 5: dead queue entries' runs held all 8 runners; watcher's 240s canary wait flipped fallback by mistake under load.
- Nov 6: cache restores ~10 MB/s (median 318s vs ~60s hosted); 3 of 17 hung until timeout.
- Nov 7: runners lost contact with GitHub.
- Nov 8: NFS fsGroup chown kept pods stuck ~50 min; the GC job deleted files inside cached repos, so every queue
  job failed (issue #4429, still open).
- Nov 9–10: a corrupted Bazelisk binary on the NFS volume (EIO) for over an hour.
- Nov 10: batch size 10 made 60+ first-wave jobs block position 1 (priority inversion); went back to 3.
- Image repeatedly missing tools (bazel, shellcheck, node, gh, rustc, Android SDK, Ruby libs) — found one at a time.
- Still open: queued jobs are not re-routed when fallback flips; worst-case failover gap ~14 min; NAS is a single
  point of failure; macOS and Docker jobs cannot move to the homelab.

### Mac-specific pain (verified)
- Free plan allows at most 5 concurrent macOS jobs; 20 macOS job definitions compete for them.
- Swift tests using a barrier deadlock on the 3-core hosted Mac (issue #4534); timing tests flake under load
  (issues #4529, #2712, #2903, #2942) and eject PRs from the queue.
- Xcode pinned at 27.0 because the preview image's macOS is too old for 27.2 (issues #4068/#4069).
- Nov 13: a PR waited on a single Mac build; another was ejected by a macOS Bazel download failure.

### Tried before (verified)
Worked: affected-target planning with a dependency map stored in git refs (queue planning 5–10 min → 5–7 s);
pruning dead caches; LLVM extract cache by content hash; CI fills the BuildBuddy cache; skipping after-merge
re-test; small jobs skip without taking a runner; release PRs skip PR tests; agent fast lane (kept, but it moved
failures into the queue).
Failed/reverted: remote cache on cold lanes (zero hits — remote-exec and cache-only action keys differ);
target-determinator (never beat a full sweep, then selected wrong targets); HEADGREEN queue grouping (GitHub
cancelled checks on earlier entries, left commits on main with un-rerunnable cancelled checks); queue batch 10.
Abandoned: "verified-run" — record a laptop BuildBuddy test run as a GitHub status so CI can skip; recorded 0
times in 14 days (agents never ran it).

### External facts (web search, 2026-11-13; check before relying)
- GitHub's merge queue accepts required checks from any CI provider: it sends a `merge_group` webhook and/or the
  CI must run on pushes to `gh-readonly-queue/<base>/*` branches and post a status/check for that commit.
- Buildkite supports `merge_group` natively and has self-hosted agents (Buildkite itself is a paid SaaS control
  plane; free tier limits not checked).
- BuildBuddy Workflows is a Bazel-focused CI that posts GitHub status checks and supports the merge queue via
  `gh-readonly-queue/*` triggers; its free-tier limits were not found.
- Tekton Pipelines-as-Code can build queue branches via push triggers (Konflux pattern); native merge_group
  support is a proposal, not shipped. Woodpecker CI support for merge queues: unknown.
- macOS self-hosted runners: Tart (Apple Silicon VMs) + ephemeral GitHub runner is the common pattern
  (Tartelet, Graftery, Cilicon, Orchard for multi-host). Apple's licence limits each Mac host to 2 concurrent macOS VMs.
- GitHub proposed a $0.002/min fee for self-hosted runners from March 2026, then postponed it; reports say public
  repos are excluded. Status today unconfirmed.

### Not yet known
- Whether a Mac (e.g. a Mac mini) can be dedicated full-time to builds.
- The maintainer's numeric target. Working proxy: p90 approval→merge and merge→installable release.
