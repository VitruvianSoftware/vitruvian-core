load("@aspect_rules_py//py:defs.bzl", "py_test")
load("//tools/gitops:defs.bzl", "gitops_manifest")

gitops_manifest(
    name = "thanos",
    manifests = ["applicationset.yaml"],
)

py_test(
    name = "thanos_values_test",
    size = "small",
    srcs = ["thanos_values_test.py"],
    data = ["applicationset.yaml"],
    main = "thanos_values_test.py",
    deps = ["@pip//pyyaml"],
)
