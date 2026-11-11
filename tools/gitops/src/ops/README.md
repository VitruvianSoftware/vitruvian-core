# Ops

## Overview
Component package providing implementation for `tools/gitops/src/ops`.

## Interface
- `[backstage.rs:py_json_str]`
- `[backstage.rs:main]`
- `[bw_backup.rs:sealed_secrets_keys]`
- `[bw_backup.rs:argocd_secret]`
- `[cicd_smoke.rs:sign]`
- `[cicd_smoke.rs:iso_utc]`
- `[cicd_smoke.rs:awk_ge_1]`
- `[cicd_smoke.rs:main]`
- `[common.rs:Res]`
- `[common.rs:LICENSE_HEADER]`
- `[common.rs:SEALED_DIR]`
- `[common.rs:BAZEL_RUN_ONLY]`
- `[common.rs:prog]`
- `[common.rs:diag]`
- `[common.rs:say]`
- `[common.rs:warn]`
- `[common.rs:die]`
- `[common.rs:arg]`
- `[common.rs:param]`
- `[common.rs:default_kubeconfig]`

## Invariants
- [bw_backup.rs:410]: `format!("ERROR: item created but attachment '{}' did not persist \u{2014} Bit...`
- [crypto.rs:213]: `assert!(b64decode(b"c2V*").is_err());`
- [crypto.rs:214]: `assert!(b64decode(b"c2V").is_err());`
- [jq.rs:426]: `assert!(!field_r(b"nope", "status").1);`
- [jq.rs:427]: `assert!(!field_r(br#""s""#, "status").1);`
- [jq.rs:442]: `assert!(has_attachment(item, "k.json"));`
- [mod.rs:134]: `assert!(seen.insert(*name), "duplicate tool {}", name);`
- [mod.rs:135]: `assert!(name`
- [mod.rs:138]: `assert!(script.ends_with(".sh"));`
- [seal.rs:482]: `assert!(has_sealed_value(good.as_bytes(), "K"));`

## Side Effects
- [backstage.rs:151]: `/// `curl ARGS` (fed `body` on stdin when given), its stdout read here as the`
- [backstage.rs:152]: `/// python that followed it in the pipeline did; curl's status and output.`
- [backstage.rs:153]: `fn curl(line: u32, args: &[&[u8]], body: Option<&[u8]>) -> (i32, Vec<u8>) {`
- [bw_backup.rs:125]: `let mut ch = match encode.spawn() {`
- [bw_backup.rs:143]: `let (st2, created) = match create.spawn() {`
- [cicd_smoke.rs:118]: `"localhost:9090/api/v1/query?query={}",`
- [cicd_smoke.rs:126]: `b"exec",`
- [cicd_smoke.rs:148]: `errs.extend_from_slice(b"jq: error (at <stdin>:0): Cannot parse the query res...`
- [common.rs:340]: `match c.spawn() {`
- [common.rs:422]: `match c.spawn() {`

## Verification
- Run: `bazel test //tools/gitops/src/ops/...`
