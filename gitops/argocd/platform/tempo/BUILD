load("@aspect_rules_py//py:defs.bzl", "py_test")
load("//tools/gitops:defs.bzl", "gitops_manifest")

gitops_manifest(
    name = "tempo",
    manifests = ["applicationset.yaml"],
)

py_test(
    name = "tempo_values_test",
    size = "small",
    srcs = ["tempo_values_test.py"],
    data = ["applicationset.yaml"],
    main = "tempo_values_test.py",
    deps = ["@pip//pyyaml"],
)
