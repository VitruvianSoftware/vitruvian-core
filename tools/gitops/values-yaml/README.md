# values-yaml

The YAML reader the `gitops/argocd/platform/*` value tests share: it parses
YAML (block and flow style, anchors, multi-document files) into
`serde_json::Value` and finds a test's data files in its Bazel runfiles.

Each platform package used to carry its own byte-identical copy as
`src/yaml.rs`; they now re-export this crate under the same name
(`pub use gitops_values_yaml as yaml;`), so their tests are unchanged.
