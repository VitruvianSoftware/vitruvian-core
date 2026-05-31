# Python dependency versions

See [Dependency Versioning & the One Version Rule](index.md) for the concepts referenced here.

## How this repo resolves them

Python third-party packages come from `rules_python`'s `pip.parse` extension in `MODULE.bazel`,
which reads a single locked requirements file into one hub repo (by default `@pip`):

```python
pip.parse(
    hub_name = "pip",
    python_version = "3.12",
    requirements_lock = "//requirements:all.txt",
)
```

Targets depend on `@pip//<package>`. This is a **flat** resolver: the lock pins exactly one
version of each distribution, and every Python target in the repo builds against it.

## Two apps, different versions

You don't get two versions out of one hub. If two apps declare incompatible constraints in the
shared requirements, the lock either **fails to resolve** or silently settles on one version and
the other app breaks at import. A lagging transitive dependency (a package whose metadata caps
`X<2` while another app needs `X>=2`) pins the whole hub the same way.

## If you truly need different versions

Give the divergent app its **own hub** with its own lock — `rules_python` supports any number:

```python
# MODULE.bazel — a second, independent pip closure
pip.parse(
    hub_name = "pip_legacy",
    python_version = "3.12",
    requirements_lock = "//requirements:legacy.txt",
)
use_repo(pip, "pip", "pip_legacy")
```

```python
# That app's BUILD targets resolve against the second hub:
py_binary(
    name = "legacy_app",
    srcs = ["main.py"],
    deps = ["@pip_legacy//flask"],   # its own Flask version
)
```

The two apps now have independent version sets. This works cleanly only when they end up in
**separate** `py_binary`/interpreters — a single interpreter still can't import two versions of
one module. If they must share a process, vendor the laggard or converge.

## Inspect / detect

```bash
# What does the resolved lock contain?
grep -i "<package>" requirements/all.txt

# Re-resolve to see a conflict surface (uv/pip-tools):
uv pip compile requirements/all.in   # or: ./tools/repin
```
