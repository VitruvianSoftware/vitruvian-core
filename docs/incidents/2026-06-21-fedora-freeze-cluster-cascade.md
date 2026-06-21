# Incident: fedora silent freeze → cluster-wide cascade (no self-heal) — 2026-06-21

|              |                                                                              |
| ------------ | ---------------------------------------------------------------------------- |
| **Status**   | ✅ Service restored (manually); 🔧 prevention tracked in Action Items below   |
| **Severity** | SEV-1 — main `cnpg-cluster` Postgres DB fully down ~43 min + broad platform disruption (homelab, no external users) |
| **Detected** | 2026-06-21 ~04:01 UTC (during the [Prometheus WAL incident](2026-06-13-prometheus-wal-corruption.md) work) |
| **Restored** | 2026-06-21 ~05:00 UTC (manual force-deletes + physical power-cycle + iSCSI re-layer) |
| **Components** | node `fedora`; `cnpg-cluster` (main DB), prometheus, alertmanager, longhorn-manager, argocd application-controller, tempo; Longhorn |
| **Recurrence** | fedora freezes **every few days** (boots ended Jun 13 / 15 / 20) — this is a pattern, not a one-off |
| **Related**  | [2026-06-13-prometheus-wal-corruption.md](2026-06-13-prometheus-wal-corruption.md) |

> Living document. This incident is about **resilience**: fedora goes offline repeatedly, so the goal is making the platform **self-heal onto working nodes** instead of requiring manual surgery + a physical power-cycle.

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
| **P0** | placement | **CNPG anti-affinity `topologyKey: kubernetes.io/hostname`** — mirror grafana-db exactly: add `cluster.affinity: {topologyKey: kubernetes.io/hostname}` (inherits CNPG `enablePodAntiAffinity:true`, `preferred`). Stops whole-DB-on-one-node. | `cnpg-cluster/applicationset.yaml` values; **and** set the same in `cnpg.go`'s `DeployCnpgCluster` Values (mirror `grafana.go`) — **not** the `hostnameAntiAffinity` helper (that's operator-only) | low | live instances are already co-located + local-path-pinned → won't move on apply; must **cycle one instance at a time** (delete pod/PVC → CNPG re-clones onto a distinct host) to un-stack. Server-side dry-run first. |
| **P0** | storage self-heal | **Longhorn `node-down-pod-deletion-policy: delete-both-statefulset-and-deployment-pod`** → dead-node pods self-evict, volumes release, reschedulable Longhorn workloads (prometheus, alertmanager) self-heal. | `longhorn/applicationset.yaml` `defaultSettings`; mirror in `longhorn.go` | low | **sleep-churn**: Longhorn fires on NotReady, which sleeping Mac nodes hit routinely → can trigger unwanted reschedules/rebuilds. Monitor; consider pairing with a longer `node-not-ready` confirmation. |
| **P0** | node auto-recovery | **Make a frozen fedora actually auto-recover**: a *real* hardware watchdog bite path (`iTCO_wdt`/NMI with pretimeout — the `intel_oc_wdt` software path wedges) **and/or** an external power-cycle path (smart plug + a tiny controller off-cluster). | host/devx provisioning (not a manifest) | high | a hard power-cut still risks ext4 corruption of fedora's local-path PVs → only safe once P0-#1 lands so a 2/3 replica set survives. Do P0-#1 **first**. |
| **P1** | failover speed | **Shorten `unreachable`/`not-ready` `tolerationSeconds` to ~60–90s** for the reschedulable monitoring pods (prometheus, alertmanager). | those AppSets' pod `tolerations` | medium | laptop sleep-churn → don't apply to anything pinned/arm64. **Drop MinIO** (arm64-pinned, can't run on fedora anyway). |
| **P2** | node stability | **Right-size `argocd-application-controller` memory** (it OOM'd ×2) — bump requests/limits in `argocd.go`. Rebalance heavy workloads off fedora. | `argocd.go` resources | low | doesn't prevent the freeze; reduces one stressor. |
| **P2** | detection | **node-problem-detector (detection only)** to surface node liveness/kernel issues — the genuine gap. | new platform AppSet | medium | **skip the auto-remediation** half (self-node-remediation/Medik8s) — too risky on a 3-CP cluster where a CP node sleeping could trigger destructive reboots. |
| **P2** | docs | **Codify the recovery runbook** (force-delete stuck pods + clear stale VolumeAttachment + iSCSI re-layer) — these are already one-liners with `//tools/gitops:delete`. | this doc's appendix + a runbook | low | risk of **false comfort** — a polished runbook must not de-prioritize the P0 prevention above. |

## Considered & rejected / already-done

- **PDBs for CNPG data pods (REC-04): not needed.** CloudNativePG's operator **auto-creates and manages its own PDBs** per Cluster (primary + replicas) unless `enablePDB:false` — which we don't set. Adding manual PDBs is redundant and can conflict.
- **`topologySpreadConstraints` on CNPG (REC-10): not expressible.** The CNPG `Cluster` CR has **no** `spec.topologySpreadConstraints` field; placement is governed solely by `spec.affinity`. Use the affinity fix (P0-#1) instead.
- **Pin/downgrade the NVIDIA driver (REC-07): not yet actionable.** The freeze→NVIDIA link is *suspected, not proven*. Action: instrument first (persist kernel logs, GPU health) to confirm before any blind downgrade; decoupling the GPU role from the k8s node is the bigger structural fix.
- **rpm-ostree reboot durability (REC-09): already shipped — but verify it.** devx #256 (`b74a817`, 2026-06-13) made native host prereqs survive rpm-ostree reboots. **Yet the iSCSI layer still dropped on 2026-06-21** → re-run `devx cluster apply` against fedora and confirm the layer/units actually persist on its current deployment (the fix isn't holding).

## Action items (living)

- [ ] **P0** CNPG hostname anti-affinity (gitops + `cnpg.go`) + carefully cycle the 3 co-located instances apart. *(prevents whole-DB-on-one-node)*
- [ ] **P0** Longhorn `node-down-pod-deletion-policy=delete-both-statefulset-and-deployment-pod` (gitops + `longhorn.go`). *(enables stateful self-heal)*
- [ ] **P0** Reliable fedora auto-recovery (hardware watchdog that bites, or external power-cycle automation). *(do after the anti-affinity fix)*
- [ ] **P1** `tolerationSeconds` ~60–90s for prometheus/alertmanager (not pinned/arm64 workloads).
- [ ] **P2** Bump `argocd-application-controller` memory; rebalance load off fedora.
- [ ] **P2** node-problem-detector (detection only).
- [ ] **Verify** devx #256 actually persists fedora's iSCSI/tailscaled across reboots (it didn't this time).
- [ ] **Investigate** the NVIDIA freeze hypothesis (persistent kernel logging / GPU health) before any driver change.
- [ ] **Separate** fix `tempo` config (`enabled` under servicegraphs/spanmetrics) — unrelated latent bug exposed by the restart.

## Appendix — recovery runbook (what worked this time)

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
