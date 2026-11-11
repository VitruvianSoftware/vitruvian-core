# Src

## Overview
Component package providing implementation for `tools/osv-scan/src`.

## Interface
- `[jq.rs:JqVal]`
- `[jq.rs:parse_stream]`
- `[jq.rs:del_version]`
- `[jq.rs:same_without_version]`
- `[pyjson.rs:Py]`
- `[pyjson.rs:loads]`
- `[pyjson.rs:load_file]`
- `[pyjson.rs:open_error_traceback]`
- `[pyjson.rs:float_repr]`
- `[pyjson.rs:str_repr]`
- `[pypath.rs:PyError]`
- `[pypath.rs:join]`
- `[pypath.rs:split]`
- `[pypath.rs:normpath]`
- `[pypath.rs:abspath]`
- `[pypath.rs:realpath]`
- `[pyval.rs:TypeError]`
- `[pyval.rs:HKey]`
- `[pyval.rs:type_name]`
- `[pyval.rs:hkey]`

## Invariants
- [jq.rs:371]: `other => panic!("{other:?}"),`
- [jq.rs:423]: `assert!(parse_stream(bad.as_bytes()).is_none(), "{bad}");`
- [jq.rs:427]: `assert!(parse_stream(b"\xef\xbb\xbf{\"x\":1}").is_some());`
- [pypath.rs:226]: `assert!(`
- [pyval.rs:187]: `assert!(hkey(&Py::List(vec![])).is_err());`
- [pyval.rs:194]: `assert!(cmp_tuple(&a, &b).is_err());`
- [pyval.rs:197]: `assert!(iterate(&Py::Int(3)).is_err());`
- [scan.rs:65]: `"panic",`
- [text.rs:194]: `assert!(is_dep_manifest(yes.as_bytes()), "{yes}");`
- [text.rs:205]: `assert!(!is_dep_manifest(no.as_bytes()), "{no}");`

## Side Effects
- [scan.rs:394]: `let (_, mut o) = capture("git", &[b"fetch", b"--quiet", b"origin", &base_ref]...`

## Verification
- Run: `bazel test //tools/osv-scan/src/...`
