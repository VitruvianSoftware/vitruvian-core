load("@aspect_rules_py//py:defs.bzl", "py_test")
load("//tools/gitops:defs.bzl", "gitops_manifest")

gitops_manifest(
    name = "envoy-gateway",
    manifests = ["applicationset.yaml"],
)

py_test(
    name = "envoyproxy_test",
    size = "small",
    srcs = ["envoyproxy_test.py"],
    data = ["gateway/envoyproxy.yaml"],
    main = "envoyproxy_test.py",
    deps = ["@pip//pyyaml"],
)
