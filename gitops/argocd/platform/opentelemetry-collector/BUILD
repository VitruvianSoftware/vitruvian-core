load("@aspect_rules_py//py:defs.bzl", "py_test")
load("//tools/gitops:defs.bzl", "gitops_manifest")

gitops_manifest(
    name = "opentelemetry-collector",
    manifests = ["applicationset.yaml"],
)

py_test(
    name = "component_names_test",
    size = "small",
    srcs = ["component_names_test.py"],
    data = ["applicationset.yaml"],
    main = "component_names_test.py",
    deps = ["@pip//pyyaml"],
)
