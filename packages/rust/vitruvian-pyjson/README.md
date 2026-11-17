# vitruvian-pyjson

JSON as a bash script's `python3 -c 'print(json.load(...)[...])'` shows it:
`True`/`None`, `1e+20`, `['a', 1]`, keys in file order, the last of two equal
keys winning. Parses with serde_json. Used by the Rust ports of the npm
publishing scripts (npm-publish-audit, npm-trusted-publisher), which started
with byte-identical copies of it. Its known gaps are listed at the top of
`src/lib.rs`.
