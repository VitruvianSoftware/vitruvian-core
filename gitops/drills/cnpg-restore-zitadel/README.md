# Restore drill: Zitadel's database

Rebuilds Zitadel's Postgres database from its MinIO backups into a throwaway
cluster, then checks what came back. It answers three questions:

1. **Do the backups restore at all?** A backup nobody has restored is a guess.
2. **How long does a restore take?** That is roughly how long sign-in is down
   if the live database is lost.
3. **How much data is lost?** The restore replays every change-log (WAL) file
   in MinIO. Anything the primary had not uploaded yet is gone.

It never touches the live database or its backups: the drill cluster reads
the backups and writes nothing back. See the safety notes in `cluster.yaml`.

## Run it

1. Start it:
   `bazel run //gitops/drills/cnpg-restore-zitadel:apply`
2. Watch the restored cluster until its phase is `Cluster in healthy state`:
   `bazel run //tools/gitops:get -- cluster.postgresql.cnpg.io zitadel-db-restore-drill -n zitadel`
   If it stalls, read its events and the restore pod's log:
   `bazel run //tools/gitops:events -- -n zitadel`
   `bazel run //tools/gitops:logs -- -n zitadel -l cnpg.io/cluster=zitadel-db-restore-drill --all-containers`
3. Read the comparison the verify job prints (live first, then restored):
   `bazel run //tools/gitops:logs -- -n zitadel job/zitadel-db-restore-drill-verify`
4. Write the results in the table below.
5. Remove it. This deletes the scratch cluster **and its disk**, which is
   intended:
   `bazel run //gitops/drills/cnpg-restore-zitadel:delete`

While it runs, the drill is a second CNPG cluster in the `zitadel` namespace.
The database alerts treat it like any other cluster, so expect nothing from
them unless the restore goes wrong. Delete it within the hour, or
`CNPGBackupMetricsMissing` fires for it (it has no backups, by design).

## Results

| Date (UTC) | Restore time | Data lost | Rows match? | Notes |
| --- | --- | --- | --- | --- |
| 2026-11-12 23:12 | 3m46s | none seen | yes | First drill. The verify job's last query hit CNPG's post-recovery restart; the job now retries. |
| 2026-11-12 23:17 | 3m53s | none seen | yes | Second run with the retrying job. All checks passed. |

What the 2026-11-12 drills showed:

- **The backups restore.** Both copies came up healthy from MinIO alone.
- **The change log replays, not just the nightly backup.** The newest event in
  both copies was from 20:14 UTC, about 20 hours after that day's 00:00 base
  backup. So the restore replayed archived WAL on top of the base backup.
- **Nothing was missing.** Live and restored copies had the same 151 tables,
  the same 3,082 rows in `eventstore.events2`, and the same newest event.
- **Caveat: the data-loss window wasn't tested.** Zitadel wrote nothing between
  20:14 and the drill (23:12), so every change had long been archived. A busy
  database could lose up to `archive_timeout` (5 minutes) of the newest
  changes, plus however long archiving had been failing (`CNPGWALArchivingFailing`
  alerts on that). Measuring the real window needs a write just before a drill.
- **Scale caveat: this database is small** (about 25 MB). Most of the ~4
  minutes is fixed start-up work, not copying data. A larger database will take
  longer; time each one before relying on this number. How the 4 minutes splits
  between start-up, download and replay wasn't measured.
- **Restore time is not outage time.** Pointing Zitadel at a restored copy
  (changing `zitadel-db-cluster-rw` or Zitadel's database host) isn't covered
  here and adds to it.

- **Restore time**: from the cluster's creation to `Cluster in healthy state`.
- **Data lost**: the newest event in the live database at verify time, minus
  the newest event in the restored copy. Zitadel writes events continuously,
  so part of this gap is events written after the restore finished. That part
  isn't loss; see the notes for the split.
