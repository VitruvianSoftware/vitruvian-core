# MinIO drive migration (move an erasure drive between nodes)

> **Do not merge the manifest change without running this.** The gitops change that
> drops `james-mbp` from the erasure set (`gitops/argocd/platform/minio-amd64/applicationset.yaml`)
> makes `minio-amd64-1` **unschedulable the moment ArgoCD syncs it** — the pod's new
> nodeAffinity excludes `james-mbp` while its PVC is still bound to a PV pinned there.
> That is expected and recoverable, but it puts the set at 3-of-4 drives until you
> finish the steps below. Merge only when someone can drive this through to the end.

Written for the 2026-09-02 move of drive 1 off `james-mbp` onto `nuc9i9`. The steps
generalise to any local-path erasure drive; substitute the ordinal and nodes.

## Why

`james-mbp` is a Lima VM on a 2019 Intel `MacBookPro16,2` running **thermally
throttled at ~29-39% of rated clock** (`pmset -g therm` → `CPU_Speed_Limit`,
sustained and worsening under load), 6 vCPUs over 4 physical cores. Its drive drew
0.67-1.62 cores against 0.096-0.135 on every other node for the identical job, and it
intermittently stopped answering peer data-path calls — dropping the set under read
quorum (`InsufficientReadQuorum` on `.minio.sys` IAM reads). A chronically slow drive
degrades the whole set, so three healthy nodes beat four with one sick one.

Rejected alternatives, so they are not re-litigated:

| option | why not |
|---|---|
| Move the drive to an arm64 node (`james-mbp32`) | MinIO **cannot mix architectures** — members validate a binary checksum and a mixed set fails to form (`has incorrect configuration: Expected MinIO binary checksum`), confirmed by a maintainer in [minio/minio#20605](https://github.com/minio/minio/discussions/20605). Bites at ≥3 nodes. True at any disk size. |
| Drop to 3 drives | MinIO's minimum for erasure coding is **4 drives**. Below that there is no erasure coding at all. |
| Put the 2nd drive on `fedora` | Only 63.4 GiB free; a drive is ~55 GiB and growing. `nuc9i5` (44.7 GiB) likewise. Only `nuc9i9` (772 GiB) has room. |

## Quorum math — read this before you start

The set is **one erasure set of 4 drives** (`/export/.minio.sys/format.json` →
`sets[0]` has 4 members) with **no explicit parity**, so MinIO's default `EC:2`
applies. Parity is exactly half the set, which triggers the `K+1` rule:

- **read quorum = 2**
- **write quorum = 3**

| drives up | reads | writes |
|---|---|---|
| 4 | ✅ | ✅ |
| 3 (during this migration) | ✅ | ✅ **zero margin** |
| 2 | ✅ | ❌ blocked |

**The whole migration runs at 3 drives with no margin.** Lose one more drive mid-heal
and the store goes read-only, which stops Thanos block uploads (`thanos` is ~53G of
the ~55G store). Do not run this alongside any other node work.

## Preconditions

```bash
export KUBECONFIG=~/.kube/config

# 1. All 4 drives currently up, and quorum clean for at least 15 min.
kubectl -n minio get pods -o wide
for p in 0 1 2 3; do
  echo -n "minio-amd64-$p: "
  kubectl -n minio logs minio-amd64-$p --since=15m | grep -c InsufficientReadQuorum
done   # every count must be 0

# 2. nuc9i9 has room (needs ~55 GiB + growth headroom; expect ~770 GiB free).
ssh -o ProxyCommand='nc -X 5 -x localhost:1055 %h %p' james@100.86.106.117 'df -h /'

# 3. Record the current drive size, so you can tell when the heal is done.
kubectl -n minio exec minio-amd64-0 -- du -sh /export
```

**Stop if** any count is non-zero, or a node is NotReady. Fix that first — you cannot
afford to start this at 3 drives.

## Steps

### 1. Merge the manifest change

Merging is what starts the clock: ArgoCD (`app-of-platform`, `automated` +
`selfHeal`) applies the new affinity within ~3 min, the StatefulSet rolls, and
`minio-amd64-1` goes **Pending** — its PVC is bound to a PV pinned to the
now-excluded `james-mbp`.

```bash
kubectl -n minio get pod minio-amd64-1 -o wide      # expect Pending
kubectl -n minio describe pod minio-amd64-1 | tail -20
# expect: "node(s) didn't match Pod's node affinity/selector" or a volume-node conflict
```

You are now at **3 of 4 drives**. Proceed without pausing.

### 2. Create the target directory on nuc9i9

The replacement PV is a **static** `local` volume, so unlike a provisioned one its
directory is not created for you. MinIO runs as uid/gid **1000** (`fsGroup: 1000`,
`fsGroupChangePolicy: OnRootMismatch`), so own it accordingly.

```bash
ssh -o ProxyCommand='nc -X 5 -x localhost:1055 %h %p' james@100.86.106.117 '
  sudo mkdir -p /var/lib/rancher/k3s/storage/minio-amd64-1-nuc9i9 &&
  sudo chown 1000:1000 /var/lib/rancher/k3s/storage/minio-amd64-1-nuc9i9 &&
  sudo chmod 0770 /var/lib/rancher/k3s/storage/minio-amd64-1-nuc9i9 &&
  ls -ld /var/lib/rancher/k3s/storage/minio-amd64-1-nuc9i9'
```

The directory **must be empty**. MinIO treats a non-empty unknown directory as a
foreign drive and will refuse to heal into it.

### 3. Delete the old PVC and PV

> **This destroys the old drive's data.** The existing PV's
> `persistentVolumeReclaimPolicy` is **`Delete`**, so removing the PVC deletes the
> backing directory on `james-mbp`. That is intended — the drive is rebuilt from
> parity — but it means **there is no going back to the old copy** after this step.
> The other 3 drives hold the data; that is what makes this safe.

```bash
kubectl -n minio get pvc export-minio-amd64-1 -o jsonpath='{.spec.volumeName}{"\n"}'  # note it
kubectl -n minio delete pvc export-minio-amd64-1
kubectl get pv | grep -c minio          # confirm the old PV is gone (reclaim=Delete)
```

### 4. Pre-bind a nuc9i9-pinned PV + PVC

**This is the step that makes placement deterministic.** Soft anti-affinity does not
choose *which* node doubles up, and the scheduler cannot see local disk — these PVCs
request `10Gi` while holding ~55G, because local-path does not enforce size. Left to
the scheduler, drive 1 could land on `nuc9i5` (44.7 GiB free) and fill it. Binding the
PVC to a PV that is pinned to `nuc9i9` forces the pod to follow the volume.

Capacity stays `10Gi` to match the StatefulSet's `volumeClaimTemplate` request —
`volumeClaimTemplates` are **immutable**, so this cannot be made honest without
recreating the StatefulSet. Reclaim policy is `Retain` (not `Delete`) so a stray PVC
deletion cannot silently wipe the rebuilt drive.

```bash
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-amd64-1-nuc9i9
spec:
  capacity:
    storage: 10Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-path
  local:
    path: /var/lib/rancher/k3s/storage/minio-amd64-1-nuc9i9
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values: [nuc9i9]
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: export-minio-amd64-1
  namespace: minio
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: local-path
  resources:
    requests:
      storage: 10Gi
  volumeName: minio-amd64-1-nuc9i9
YAML

kubectl -n minio get pvc export-minio-amd64-1   # expect Bound to minio-amd64-1-nuc9i9
```

### 5. Let the pod reschedule

```bash
kubectl -n minio delete pod minio-amd64-1 --ignore-not-found
kubectl -n minio get pod minio-amd64-1 -o wide -w    # expect NODE=nuc9i9, then Running
```

**VERIFY the node is `nuc9i9`.** If it landed anywhere else, the PVC did not bind to
your PV — stop and re-check step 4 rather than letting a 55 GiB heal run onto a full
disk.

### 6. Heal

MinIO auto-heals a drive it recognises as empty-but-formatted. Watch it rather than
assuming:

```bash
kubectl -n minio exec minio-amd64-0 -- mc admin heal --recursive --verbose local/ 2>&1 | tail -20
# or watch the drive fill toward the ~55 GiB the others hold
watch -n30 "kubectl -n minio exec minio-amd64-1 -- du -sh /export"
```

Heal traffic crosses the cluster network for ~55 GiB. Expect this to take a while and
to load `nuc9i9`; that is normal.

## Verification (all must pass)

```bash
# 1. Four drives, three nodes, two on nuc9i9
kubectl -n minio get pods -o wide

# 2. Drive 1 has caught up with its peers
for p in 0 1 2 3; do echo -n "minio-amd64-$p: "; kubectl -n minio exec minio-amd64-$p -- du -sh /export; done

# 3. Quorum clean
for p in 0 1 2 3; do
  echo -n "minio-amd64-$p: "
  kubectl -n minio logs minio-amd64-$p --since=15m | grep -c InsufficientReadQuorum
done   # all 0

# 4. The erasure set still lists 4 members
kubectl -n minio exec minio-amd64-0 -- cat /export/.minio.sys/format.json

# 5. Consumers healthy — thanos is the one that actually writes
kubectl -n argocd get application minio-amd64 thanos -o custom-columns=\
'NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
```

Downstream, the two pods that were degraded *because* they sat on `james-mbp` should
recover on their own once it is no longer in the storage path — `redis-replicas-2`
and the third `buzz` replica (whose A3 git-store gate was timing out against the slow
drive). Confirm rather than assume.

## Rollback

**Before step 3** — revert the PR. ArgoCD restores hard 1-per-node anti-affinity and
`minio-amd64-1` reschedules onto `james-mbp` with its original PV intact. Clean.

**After step 3** — the old drive's directory is gone (reclaim `Delete`), so there is
no rollback *to it*. Roll forward instead: the remaining 3 drives are authoritative
and a heal onto any empty drive rebuilds the 4th. If `nuc9i9` turns out to be the
wrong target, repeat steps 2-5 pointing at a different node — you are still at 3-of-4
and writes still work.

**If you drop to 2 drives** at any point, the store is read-only. Do not attempt
further migration; restore the failed drive's node first.

## Aftercare

- `nuc9i9` is now a **write-availability SPOF**: losing it drops 2 of 4 drives and
  blocks writes. Accepted deliberately, because `james-mbp` was degrading the set
  unconditionally. Revert to hard 1-per-node if a 4th healthy amd64 node appears.
- The PVCs still request `10Gi` while holding ~55G. Correcting that needs a
  StatefulSet recreate; until then, **never trust the scheduler to know how big these
  drives are** when planning placement.
- `thanos` is ~53G of the ~55G store, under retention `raw 15d / 5m 90d / 1h 365d`
  (`gitops/argocd/platform/thanos/applicationset.yaml`). If capacity gets tight, that
  retention is the lever — not the drive count.
- `james-mbp` remains a cluster node running non-storage workloads while thermally
  throttled. That is a separate problem; this runbook only removes it from the
  storage path.
