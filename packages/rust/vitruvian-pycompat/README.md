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
(agent-app, merge-queue-stats, sync-downloads, pulumi, design-system-android,
lint-naming, release-scope, sdk-codegen, sync-site-tools). Before changing one,
run the tests of every tool that depends on it:

```
bazel test $(bazel query 'rdeps(//..., //packages/rust/vitruvian-pycompat)' --output=label 2>/dev/null | grep _test)
```
- `unicode_tables`: Python 3.12's character classes on Unicode 15.0.0
  (whitespace, decimal digits, digits, word characters, printable, case
  ignorable), shared by every port that needs them.
