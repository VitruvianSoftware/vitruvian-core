# Scripts

## Overview
Release signing, notarization, and stapling helpers for the standalone `VitruvianSoftware/vitruvian-code` workflow (`sign-and-notarize.sh`).

## Notarization that cannot hang the release

Each notary submission gets 10 minutes (`NOTARY_ATTEMPT_SECONDS`), and the script
tries up to three times (`NOTARY_ATTEMPTS`). All attempts in one run of the
script share 20 minutes (`NOTARY_BUDGET_SECONDS`). A release runs the script
twice, so repeated hangs still end inside the package job's 60-minute limit.

- **Hang or network error:** stopped (TERM, then KILL, for xcrun and its
  notarytool) and tried again. If Apple already gave it a submission id, the
  retry waits on that same submission instead of uploading again.
- **Verdict:** Invalid or Rejected is final and is not retried.
- **While waiting:** the log prints a line every minute.
- **Logs on failure:** fetching Apple's log is bounded to two minutes.

`notary-submit_test.sh` (`bazel test //apps/desktop/vitruvian-code:notary_submit_test`)
checks all of this with a fake notarytool, including the time each case takes.
