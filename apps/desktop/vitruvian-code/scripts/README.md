# Scripts

## Overview
Release signing, notarization, and stapling helpers for the standalone `VitruvianSoftware/vitruvian-code` workflow (`sign-and-notarize.sh`).

## Notarization that cannot hang the release

Each notary submission gets 10 minutes (`NOTARY_ATTEMPT_SECONDS`), and the script
tries up to three times (`NOTARY_ATTEMPTS`). An attempt that hangs or loses the
network is stopped and tried again. If Apple already gave it a submission id,
the retry waits on that same submission instead of uploading again. A verdict
of Invalid or Rejected is final and is not retried.

`notary-submit_test.sh` (`bazel test //apps/desktop/vitruvian-code:notary_submit_test`)
checks this with a fake notarytool.
