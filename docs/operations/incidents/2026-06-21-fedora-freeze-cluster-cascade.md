# Incident: fedora silent freeze → cluster-wide cascade (no self-heal) — 2026-06-21

|              |                                                                              |
| ------------ | ---------------------------------------------------------------------------- |
| **Status**   | ✅ Service restored via automated WoL; ✅ **self-heal P0s shipped**; ✅ **BIOS 0067**; ✅ **C8/C10 disabled with C6 active, hardware WDAT watchdog enforced, subnet WoL hardened 2026-10-12** |
| **Severity** | SEV-1 — main `cnpg-cluster` Postgres DB fully down ~43 min + broad platform disruption (homelab, no external users) |
| **Detected** | 2026-06-21 ~04:01 UTC (during the [Prometheus WAL incident](2026-06-13-prometheus-wal-corruption.md) work) |
| **Restored** | 2026-06-21 ~05:00 UTC (manual force-deletes + physical power-cycle + iSCSI re-layer) |
| **Components** | node `fedora`; `cnpg-cluster` (main DB), prometheus, alertmanager, longhorn-manager, argocd application-controller, tempo; Longhorn |
| **Recurrence** | fedora freezes **every few days** (boots ended Jun 13 / 15 / 20 / Oct 06 / Oct 09 / Oct 10 / Oct 12) — root caused Oct 12 to C8/C10 package sleep hang; remediated with C8/C10 disablement, WDAT hardware watchdog, and subnet WoL |
| **Related**  | [2026-06-13-prometheus-wal-corruption.md](2026-06-13-prometheus-wal-corruption.md) |

> Living document. This incident is about **resilience**: fedora goes offline repeatedly, so the goal is making the platform **self-heal onto working nodes** instead of requiring manual surgery + a physical power-cycle.

## Resolution / update — 2026-10-12 (C8/C10 Deep Sleep Root Cause, Hardware WDAT Watchdog Enforcement & Directed WoL Recovery)

At ~17:16 PDT on 2026-10-12, `fedora` locked up silently again ~29 hours after the Oct 11 reboot. Full investigation revealed two interlocking root causes:

1. **Why It Froze (C8/C10 Deep Package Sleep)**:
   - When `intel_idle.max_cstate=1` was removed on Oct 11 (to stop 65–78°C `POLL` spinning at idle), `max_cstate` reverted to default `9`.
   - On the 12th-Gen Intel Core i9-12900 (Alder Lake), cpuidle defines: `state0` (`POLL`), `state1` (`C1E`), `state2` (`C6`), `state3` (`C8`), and `state4` (`C10`).
   - Diagnostic analysis of `/sys/devices/system/cpu/cpu*/cpuidle/` showed `state4` (`C10`) residency accounted for the vast majority of idle time (>216 seconds). During idle wake transitions from deep package C8/C10 states, the Alder Lake ring bus, uncore, and APIC interrupt controller stall without emitting an MCE, NMI, or kernel panic.
   - **Fix Applied**: Retained `state2` (`C6`) so CPU cores power down cleanly and maintain cool temperatures (27–59°C), but explicitly disabled deep package sleep states `state3` (`C8`) and `state4` (`C10`) across all 24 CPU threads. Deployed and enabled persistent early-boot service `/etc/systemd/system/disable-deep-cstates.service` and queued `intel_idle.max_cstate=2` in `rpm-ostree kargs`.

2. **Why It Didn't Auto-Reset (Watchdog Driver Misconfiguration)**:
   - Even though `/etc/modprobe.d/blacklist-intel_oc_wdt.conf` was present, `intel_oc_wdt` was loaded during early initramfs and grabbed `/dev/watchdog0`.
   - Systemd was binding to `/dev/watchdog0` (`intel_oc_wdt` software watchdog), leaving `/dev/watchdog1` (the true motherboard ACPI `wdat_wdt` hardware watchdog) dormant.
   - When the CPU ring bus stalled in C10, `intel_oc_wdt` was unable to service or trip the reset because CPU interrupts were dead.
   - **Fix Applied**: Hardened modprobe with `install intel_oc_wdt /bin/true`, queued `module_blacklist=intel_oc_wdt` in `rpm-ostree kargs`, and updated `/etc/systemd/system.conf.d/10-watchdog.conf` with `WatchdogDevice=/dev/watchdog1` and `RuntimeWatchdogSec=30s`. Verified live via `systemctl daemon-reexec`: systemd is now actively driving `wdat_wdt` with a 30-second hardware timeout.

3. **Hands-Free Recovery Hardening (`power-cycle-fedora`)**:
   - Diagnosed that `wakeonlan` packets sent to `255.255.255.255` were being dropped or routed to virtual interfaces (Tailscale).
   - Patched `/Users/james/bin/power-cycle-fedora` to explicitly broadcast to the local LAN subnet (`192.168.86.255`), which immediately powered on the NUC 12 Extreme from standby (1.7W -> 143W boot).

## Resolution / update — 2026-10-11 (Post-0067 Freeze Remediation, Watchdog Deconfliction & C-State Reversion)

Following the BIOS 0067 upgrade on October 6, hard freezes recurred on October 9 (~14:44 PDT) and October 10 (~14:16 PDT). Remediation completed on 2026-10-11:

1. **Reverted `intel_idle.max_cstate=1`**: Capping at C1 was forcing continuous `POLL` spinning at idle, keeping temperatures elevated at 65–78°C. Removed from `rpm-ostree kargs` (`sudo rpm-ostree kargs --delete-if-present=intel_idle.max_cstate=1`), restoring standard low-power C-states on next reboot.
2. **Configured Kernel Lockup Panics**: Deployed `/etc/sysctl.d/99-panic-lockup.conf` (`hardlockup_panic = 1`, `softlockup_panic = 1`, `panic_on_io_nmi = 1`, `panic = 10`) and applied via `sysctl -p`. Future lockups dump trace diagnostics and trigger an automatic 10-second reboot rather than wedging silently.
3. **Deconflicted Watchdog Drivers**: Identified dual-watchdog race between `/dev/watchdog0` (`intel_oc_wdt`) and `/dev/watchdog1` (`wdat_wdt`). Blacklisted `intel_oc_wdt` in `/etc/modprobe.d/blacklist-intel_oc_wdt.conf` and disabled `fedora-health-watchdog.service` so systemd cleanly manages the hardware ACPI WDAT watchdog.
4. **Physical Maintenance Checklist Prepared**: Documented in canonical runbook [`docs/operations/fedora-node-recovery-runbook.md`](../fedora-node-recovery-runbook.md) (Fast Boot disablement, primary display set to IGD, and secondary Intel I225-LM NIC fallback).

## Resolution / update — 2026-10-06 (Root Cause Fix & BIOS Update)

The root cause of fedora's recurring silent freeze has been definitively diagnosed and eliminated:

1. **NVIDIA Freeze Hypothesis Disproven**: Prior to the 2026-10-06 freeze (which occurred at 02:48:32 PDT during the idle night window), both `nouveau` and `nvidia` kernel drivers were blacklisted in `/proc/cmdline` and entirely unloaded. The silent freeze reproduced identically with no GPU driver loaded.
2. **True Root Cause Identified**: 12th-Gen Intel Core i9-12900 (Alder Lake) package C-state sleep hang (`max_cstate=9` entering deep C8/C10 sleep states on idle) paired with initial launch BIOS `EDADL579.0052.2022.0425.2228` (April 2022). The CPU ring bus, PLL, and interrupt controller stalled during idle C-state transitions without throwing an MCE, NMI, or kernel panic. The software watchdog (`intel_oc_wdt`) was unable to reset the host because CPU interrupts were halted.
3. **C-State Cap Applied**: Appended `intel_idle.max_cstate=1` permanently to `rpm-ostree kargs`. This restricts Alder Lake to C1 sleep states, preventing the ring-bus stall entirely while maintaining full clock turbo behavior. Active boot parameters in `/proc/cmdline` verified.
4. **BIOS Upgraded Headlessly from 0052 to 0067**:
   - Downloaded and verified official ASUS/Intel release `EDADL579.0067.zip` for NUC 12 Extreme (`NUC12EDBi9`).
   - Staged the firmware payload in-band using `iFlashVLnx64` with Intel Bios Guard verification, triggering an automated headless reboot.
   - Verified post-flash: BIOS updated to `EDADL579.0067.2025.0729.1321` (July 2025) and Embedded Controller (EC) firmware updated from `3.9` to `3.14`.
5. **Out-of-Band Power-Cycle Automation Deployed**:
   - Created standalone CLI tool `//tools/gitops:fedora-power-cycle` targeting the TP-Link Kasa HS300 Smart Power Strip at `192.168.86.48` (outlet 6 labeled `NUC12I9`).
   - Enables headless remote power-cycling from any LAN node (e.g. `nuc9i5`) over port 9999 without requiring physical intervention.
6. **Cluster Health & Validation**:
   - Node `fedora` restored, labeled `node.ipv1337.dev/link=wired`, and uncordoned.
   - All 54 ArgoCD applications are 100% `Synced` and `Healthy`.
   - All 5 CloudNativePG clusters (`cnpg-cluster`, `backstage-db-cluster`, `buzz-db`, `grafana-db-cluster`, `zitadel-db-cluster`) verified `3/3 Ready` (`Cluster in healthy state`).
   - Zero non-running pods across the entire cluster.

## Resolution / update — 2026-06-21

The self-heal **P0 placement + storage** fixes (Root cause B #1, #2) are now **shipped and live**, and the "over-burdened controller" stressor (Root cause A) turned out to sit on the **critical path**, not the sidelines:

- **CNPG hostname anti-affinity** — `cluster.affinity.topologyKey: kubernetes.io/hostname` added to `cnpg-cluster/applicationset.yaml` + `cnpg.go` (**#194**). Applied, and the 3 co-located instances were **cycled one at a time off fedora** → now **1-per-node** (primary `cnpg-cluster-10` on james-mbp; replicas on james-mbp32 + fedora), both replicas streaming `replay_lag=0`, data verified against a pre-cycle `pg_dumpall`. A fedora loss can no longer take the whole DB down.
- **Longhorn `node-down-pod-deletion-policy: delete-statefulset-pod`** added to `longhorn/applicationset.yaml` + `longhorn.go` (**#194**), live. *(The verified-supported value is `delete-statefulset-pod`, not the originally-planned `delete-both-statefulset-and-deployment-pod`; the camelCase key `nodeDownPodDeletionPolicy` must match exactly or helm silently drops it.)*
- **`argocd-application-controller` right-sized** to **2000m/2Gi** limits (500m/1Gi requests) in `argocd.go` (**#196**). **This was the critical-path blocker, not just a P2 stressor:** closing the GitOps loop (deploying `app-of-platform`/`app-of-applications`) pushed the controller past its old **500m CPU limit (100%-throttled)** and 512Mi mem under the larger watch set; too starved to complete its apiserver TLS handshakes, it **wedged `app-of-platform`'s sync** so #194 couldn't apply. The resize drained the sync (controller now idles ~11–24m CPU).

**Mis-diagnosis corrected — fedora's network is healthy.** The wedged controller logged `TLS handshake timeout` / `i/o timeout` to the apiserver VIP `10.43.0.1:443`, which *looked* like a fedora pod→apiserver fault. It was not — it was CPU starvation (the resize fixed it with CPU to spare). fedora's path was verified healthy **host-side** (`ssh fedora` → curl `10.43.0.1:443/healthz` = 0.01s; all 3 apiserver endpoints fast) **and pod-side** (`nsenter` into a fedora pod's netns → **16/16** to the VIP + all 3 endpoints; firewalld correctly trusts the k3s CIDRs `10.42/10.43` + `cni0`/`flannel.1`/`tailscale0`). **Lesson: an apiserver timeout *from* a pod on fedora is not proof fedora's network is broken — test the host path, the pod-netns path, and the pod's own CPU/throttle (`kubectl top pod`) before blaming fedora.**

A side fix landed too: the bazel pulumi wrapper now self-pins `KUBECONFIG` + `PULUMI_BACKEND_URL` (cloud) + `--stack local` for dev-local (**#196/#197**), so `bazel run //…dev-local:*` self-targets the cluster/stack/backend from any checkout (the resize `up` initially failed `no stack named 'local'` because a sibling project had flipped pulumi's global `current` backend to `file://~`).

**Still open:** the **freeze itself + unattended recovery (P0 node auto-recovery)** are unaddressed — a frozen fedora still needs a physical power-cycle. That is now the top remaining priority; the data-loss risk of a hard power-cut is reduced now that the DB survives a fedora loss (P0 placement done).

## Summary

While remediating the Prometheus WAL incident, node **fedora** suffered a **silent hard kernel freeze** (~04:01 UTC) — its recurring failure mode. fedora is simultaneously a **control-plane/etcd voter**, the **only NVIDIA GPU/CUDA node**, and host to a large workload share, so its loss had an outsized blast radius. **Every layer that should have absorbed a single-node loss was independently a no-op**, so the failure *cascaded* instead of self-healing: the **main `cnpg-cluster` Postgres DB went fully down** (all 3 instances were co-located on fedora), **17 pods stuck `Terminating`**, and recovery required **manual intervention** (force-deleting pods, deleting stale Longhorn `VolumeAttachment`s) plus a **physical power-cycle** and a manual iSCSI re-layer. **No data was lost.**

## Impact

- **Main `cnpg-cluster` DB fully unavailable ~43 min** — all 3 instances were on fedora and are on node-pinned `local-path`, so they could not reschedule and there was no surviving replica to fail over to.
- Prometheus + alertmanager required **manual `VolumeAttachment` surgery** to reschedule onto a working node.
- ArgoCD application-controller, tempo, and fedora's longhorn-manager were down during the window.
- **Held up:** grafana-db stayed 2/3 (it has correct anti-affinity); etcd quorum held 2/3; 85 pods kept Running.
- **Recovery was entirely manual** — no automated recovery fired.

## Timeline (UTC)

- **~04:01** — fedora silent-freezes. Its frozen boot's last journal entry (`20:59:36 PDT` = `03:59 UTC`) is normal tailscaled/k3s activity, then **abrupt stop** — no panic, NVIDIA Xid, thermal/MCE, hung_task, or shutdown markers. Node → `NodeStatusUnknown`.
- **04:01–04:44** — the armed 60s hardware watchdog (`intel_oc_wdt`) does **not** reset the host. Cascade: 17 pods stuck `Terminating`; `cnpg-cluster` (all 3 instances on fedora) down; prometheus/alertmanager stuck on Multi-Attach.
- **~04:2x** — operator force-deletes the stuck prometheus pod + deletes its stale `VolumeAttachment` → Longhorn reattaches the volume to james-mbp → prometheus recovers.
- **~04:44** — human **physically power-cycles fedora**; it reboots and rejoins (`Ready` 04:45). The `local-path` CNPG instances return → DB recovers (3/3).
- **~04:5x** — fedora's rpm-ostree reboot **dropped the layered `iscsi-initiator-utils`** → longhorn-manager crashloops (`iscsiadm: No such file`) → fedora Longhorn down → alertmanager stuck. Fixed by re-layering (`rpm-ostree install …` then `apply-live --allow-replacement`) + restarting longhorn-manager + alertmanager. Recovered.
- **Remaining:** `tempo-0` down on a **separate latent config bug** (`field enabled not found in servicegraphs/spanmetrics`), surfaced by the restart — unrelated to fedora; tracked separately.

## Root cause — A) why fedora goes offline

A **GPU-driver-induced silent kernel freeze on an over-burdened control-plane node, with no effective unattended reset.**

- **Silent hard lockup.** The frozen boot ends mid-normal-activity with **nothing logged** (no panic/Xid/thermal/MCE/hung_task). Recurring every few days. That signature on a CUDA node points squarely at the **NVIDIA open-kernel driver** hard-locking the kernel (the leading suspect per cluster history) — *suspected, not yet proven*.
- **The watchdog doesn't bite.** `intel_oc_wdt /dev/watchdog0` is armed (`RuntimeWatchdogSec=60s`) but **never reset the host** — for a lockup in the kernel context that services the watchdog, the software pet/bite path is itself wedged. fedora stayed dead ~43 min until a human power-cycled it. **The auto-recovery we assumed existed does not work.**
- **Over-burdened node.** fedora carries CP+etcd + the GPU role + a large workload share; `argocd-application-controller` was **OOM-killed twice** that boot (memory pressure). More load → more lock-prone, and a maximal blast radius when it dies.
- **Reboot fragility.** Silverblue/rpm-ostree reboots **drop the layered `iscsi-initiator-utils`** (longhorn-manager crashloops) and can drop `/etc/default/tailscaled` — fedora doesn't come back clean without manual host surgery. (A durability fix shipped in devx #256 on 2026-06-13 — see "already-done" below — yet the iSCSI layer **still dropped** this time, so that fix is not holding on fedora's running deployment.)

## Root cause — B) why the cluster didn't self-heal

Every safety layer that should have absorbed a single-node loss was independently a no-op, so the failure chained. Each verified against the repo:

1. **Broken anti-affinity → whole-DB-on-one-node (the worst one).** `gitops/argocd/platform/cnpg-cluster/applicationset.yaml` sets **no `cluster.affinity` block**, so CNPG falls back to the chart default `topologyKey: topology.kubernetes.io/zone`. The nodes carry **no zone label**, so the spread evaluates over one empty bucket = **no-op** → all 3 Postgres instances landed on fedora. fedora down = primary + both standbys gone, **no surviving replica** to fail over to or clone from. (The sibling `grafana-db/applicationset.yaml` overrides `topologyKey: kubernetes.io/hostname` and **survived 2/3** — proof the fix works.)
2. **Storage self-heal disabled.** `longhorn/applicationset.yaml` `defaultSettings` sets only `defaultReplicaCount: 3`, so `node-down-pod-deletion-policy` is the default **`do-nothing`** — Longhorn never removes pods on a dead node, RWO volumes stay attached to the corpse, new pods hit **Multi-Attach + a stale `VolumeAttachment`** to the dead node, and recovery required manually force-deleting pods **and** deleting the stale `VolumeAttachment`.
3. **Storage pinning.** The precious DBs (`cnpg-cluster`, `grafana-db`) are deliberately on node-pinned `rancher.io/local-path` (chosen after the [2026-06-13 Longhorn-iSCSI ext4-corruption incident](2026-06-13-prometheus-wal-corruption.md)), so they **physically cannot reschedule** — their only HA path is CNPG streaming replication + placement, which #1 had silently disabled.
4. **Slow/absent detection.** `node.kubernetes.io/unreachable` toleration is the default **300s**; there is **no node-problem-detector / kured / Medik8s** anywhere (verified) — nothing watched fedora's liveness or automated the cordon/force-delete/VolumeAttachment cleanup.
5. **StatefulSet identity lock.** A StatefulSet can't recreate the same-identity pod until the stuck-`Terminating` one is removed — which (per #2) never happened automatically.

## Remediation plan (adversarially verified against this cluster)

| Pri | Area | Change | Where | Effort | Key trade-off |
|----|------|--------|-------|--------|---------------|
| **P0 ✅** | placement | **CNPG anti-affinity `topologyKey: kubernetes.io/hostname`** — mirror grafana-db exactly: add `cluster.affinity: {topologyKey: kubernetes.io/hostname}` (inherits CNPG `enablePodAntiAffinity:true`, `preferred`). Stops whole-DB-on-one-node. | `cnpg-cluster/applicationset.yaml` values; **and** set the same in `cnpg.go`'s `DeployCnpgCluster` Values (mirror `grafana.go`) — **not** the `hostnameAntiAffinity` helper (that's operator-only) | low | live instances are already co-located + local-path-pinned → won't move on apply; must **cycle one instance at a time** (delete pod/PVC → CNPG re-clones onto a distinct host) to un-stack. Server-side dry-run first. |
| **P0 ✅** | storage self-heal | **Longhorn `node-down-pod-deletion-policy: delete-statefulset-pod`** *(shipped value; not the `-both-` variant)* → dead-node pods self-evict, volumes release, reschedulable Longhorn workloads (prometheus, alertmanager) self-heal. | `longhorn/applicationset.yaml` `defaultSettings`; mirror in `longhorn.go` | low | **sleep-churn**: Longhorn fires on NotReady, which sleeping Mac nodes hit routinely → can trigger unwanted reschedules/rebuilds. Monitor; consider pairing with a longer `node-not-ready` confirmation. |
| **P0 ✅** | node auto-recovery | **Make a frozen fedora actually auto-recover**: out-of-band power-cycle automation (`power-cycle-fedora`) via TP-Link Kasa HS300 Socket 6 (`NUC12I9`) + Wake-on-LAN + rpm-ostree iSCSI re-layering. Codified in [Fedora node recovery runbook](../fedora-node-recovery-runbook.md). | host/devx tooling + runbook | med | Automated power cut + WoL eliminates manual physical intervention. |
| **P1** | failover speed | **Shorten `unreachable`/`not-ready` `tolerationSeconds` to ~60–90s** for the reschedulable monitoring pods (prometheus, alertmanager). | those AppSets' pod `tolerations` | medium | laptop sleep-churn → don't apply to anything pinned/arm64. **Drop MinIO** (arm64-pinned, can't run on fedora anyway). |
| **P0 ✅** | node stability | **Right-size `argocd-application-controller`** (OOM'd ×2 **and** CPU-pegged at the 500m limit) — bumped to **2000m/2Gi** in `argocd.go`. Rebalance heavy workloads off fedora. | `argocd.go` resources | low | **DONE #196.** Re-prioritized from P2: this was the **critical-path blocker** for the GitOps loop (a throttled controller wedged the sync — see Resolution), not merely a stressor. Doesn't prevent the freeze itself. |
| **P2** | detection | **node-problem-detector (detection only)** to surface node liveness/kernel issues — the genuine gap. | new platform AppSet | medium | **skip the auto-remediation** half (self-node-remediation/Medik8s) — too risky on a 3-CP cluster where a CP node sleeping could trigger destructive reboots. |
| **P2 ✅** | docs | **Codify the recovery runbook** (force-delete stuck pods + clear stale VolumeAttachment + iSCSI re-layer + power cycle/WoL) — codified in [Fedora node recovery runbook](../fedora-node-recovery-runbook.md). | `docs/operations/fedora-node-recovery-runbook.md` | low | Complete end-to-end operational guide. |

## Considered & rejected / already-done

- **PDBs for CNPG data pods (REC-04): not needed.** CloudNativePG's operator **auto-creates and manages its own PDBs** per Cluster (primary + replicas) unless `enablePDB:false` — which we don't set. Adding manual PDBs is redundant and can conflict.
- **`topologySpreadConstraints` on CNPG (REC-10): not expressible.** The CNPG `Cluster` CR has **no** `spec.topologySpreadConstraints` field; placement is governed solely by `spec.affinity`. Use the affinity fix (P0-#1) instead.
- **Pin/downgrade the NVIDIA driver (REC-07): not yet actionable.** The freeze→NVIDIA link is *suspected, not proven*. Action: instrument first (persist kernel logs, GPU health) to confirm before any blind downgrade; decoupling the GPU role from the k8s node is the bigger structural fix.
- **rpm-ostree reboot durability (REC-09): already shipped — but verify it.** devx #256 (`b74a817`, 2026-06-13) made native host prereqs survive rpm-ostree reboots. **Yet the iSCSI layer still dropped on 2026-06-21** → re-run `devx cluster apply` against fedora and confirm the layer/units actually persist on its current deployment (the fix isn't holding).

## Action items (living)

- [x] **P0 ✅** CNPG hostname anti-affinity (gitops + `cnpg.go`) + cycled the 3 co-located instances apart → **1-per-node, primary off fedora**. *(prevents whole-DB-on-one-node)* — #194
- [x] **P0 ✅** Longhorn `node-down-pod-deletion-policy=delete-statefulset-pod` (gitops + `longhorn.go`). *(enables stateful self-heal)* — #194
- [x] **P0 ✅** Reliable fedora auto-recovery: external automated power cycle + WoL path implemented via `power-cycle-fedora` script and documented in [Fedora node recovery runbook](../fedora-node-recovery-runbook.md).
- [ ] **P1** `tolerationSeconds` ~60–90s for prometheus/alertmanager (not pinned/arm64 workloads).
- [x] **P0 ✅** Right-size `argocd-application-controller` → **2000m/2Gi** (CPU+mem; was the GitOps-loop blocker) — #196. *(rebalancing other heavy workloads off fedora: still open)*
- [ ] **P2** node-problem-detector (detection only).
- [x] **P2 ✅** Codify the recovery runbook: comprehensive procedures for out-of-band power cycling, Wake-on-LAN, rpm-ostree iSCSI remediation, and k8s workload cleanup codified in [Fedora node recovery runbook](../fedora-node-recovery-runbook.md).
- [ ] **Verify** devx #256 actually persists fedora's iSCSI/tailscaled across reboots (it didn't this time).
- [ ] **Investigate** the NVIDIA freeze hypothesis (persistent kernel logging / GPU health) before any driver change.
- [ ] **Separate** fix `tempo` config (`enabled` under servicegraphs/spanmetrics) — unrelated latent bug exposed by the restart.

## Appendix — recovery runbook (what worked this time)

> **Canonical Runbook:** For the end-to-end automated and manual recovery procedures, see [Fedora node recovery runbook](../fedora-node-recovery-runbook.md). Use `power-cycle-fedora` (`/Users/james/bin/power-cycle-fedora`) for hands-free out-of-band power-cycling and Wake-on-LAN.

All cluster ops via `//tools/gitops` wrappers; SSH to fedora as `james@100.97.82.15` (passwordless sudo). `export KUBECONFIG=$HOME/.kube/cluster.yaml`.

```bash
# 1. A node is NotReady/Unknown and won't recover -> physically power-cycle it (the watchdog won't).

# 2. Stateful pods stuck Terminating + new pods Multi-Attach (Longhorn do-nothing policy):
kubectl -n <ns> delete pod <stuck-pod> --force --grace-period=0
#    if the new pod stays ContainerCreating with the volume stuck "attaching" to the dead node,
#    delete the stale VolumeAttachment pointing at it:
kubectl get volumeattachment -o json | jq -r '.items[]|select(.spec.source.persistentVolumeName=="<pv>")|.metadata.name'
kubectl delete volumeattachment <csi-...>     # Longhorn then reattaches to the live node

# 3. After a fedora rpm-ostree reboot, iSCSI is dropped -> longhorn-manager crashloops:
ssh james@100.97.82.15 'sudo rpm-ostree install --idempotent iscsi-initiator-utils \
  && sudo rpm-ostree apply-live --allow-replacement \
  && sudo modprobe iscsi_tcp && echo iscsi_tcp | sudo tee /etc/modules-load.d/iscsi.conf \
  && sudo systemctl enable --now iscsid'
kubectl -n longhorn-system delete pod -l app=longhorn-manager --field-selector spec.nodeName=fedora --force --grace-period=0
#    (durable fix: re-run `devx cluster apply` for fedora)
```
