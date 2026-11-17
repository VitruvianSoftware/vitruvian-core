# vitruvian-pycompat

Python's behaviour where Rust's differs, for the tools in this repo that were
ported from Python and must print exactly what the Python printed:

- `pystr`: what counts as whitespace or a decimal digit, how `repr()` quotes a
  string, how floats print, how `round()` breaks ties.
- `json`: `json.loads` and `json.dumps` with their defaults.
- `argparse`: a parser of optionals only, with argparse's help, usage and
  errors.

Standard library only, so a tool can link it whatever crate hub it uses.

These modules started as byte-identical copies in several tools
(agent-app, merge-queue-stats, sync-downloads, pulumi). Before changing one,
run the tests of every tool that depends on it:

```
bazel test $(bazel query 'rdeps(//..., //packages/rust/vitruvian-pycompat)' --output=label 2>/dev/null | grep _test)
```

Known gap: `pystr`'s printable test (used by `repr()`) is an approximation.
It treats unassigned code points such as U+0378 as printable, where Python
escapes them.
