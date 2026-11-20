# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/gitops:defs.bzl", "gitops_manifest")
load("//tools/pytest:defs.bzl", "py_test")

# gazelle:ignore

gitops_manifest(
    name = "headscale",
    manifests = [
        "applicationset.yaml",
        "backendtrafficpolicy.yaml",
        "certificate.yaml",
        "configmap-edge.yaml",
        "configmap-headplane.yaml",
        "configmap-key-exporter.yaml",
        "configmap-policy.yaml",
        "daemonset-node-agent.yaml",
        "deployment-edge-tunnel.yaml",
        "deployment-headplane.yaml",
        "deployment-key-exporter.yaml",
        "deployment-subnet-router.yaml",
        "dnsendpoint.yaml",
        "httproute-headplane.yaml",
        "httproute.yaml",
        "pvc-headplane.yaml",
        "service-headplane.yaml",
        "service-key-exporter.yaml",
        "service-policy-sync.yaml",
    ],
)

DATA_FILES = [
    "policy.hujson",
    "//:.github/actions/homelab-tunnel-setup/action.yml",
    "//:.github/actions/zitadel-tunnel-setup/action.yml",
    "//gitops/argocd/platform/envoy-gateway:gateway/envoyproxy.yaml",
    "applicationset.yaml",
    "backendtrafficpolicy.yaml",
    "certificate.yaml",
    "configmap-edge.yaml",
    "configmap-headplane.yaml",
    "configmap-policy.yaml",
    "daemonset-node-agent.yaml",
    "deployment-edge-tunnel.yaml",
    "deployment-subnet-router.yaml",
    "dnsendpoint.yaml",
    "httproute.yaml",
    "service-key-exporter.yaml",
    "service-policy-sync.yaml",
]

rust_library(
    name = "headscale_values_lib",
    srcs = [
        "src/lib.rs",
    ],
    crate_name = "headscale_values",
    edition = "2021",
    deps = [
        "//tools/gitops/values-yaml:values_yaml",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "policy-configmap",
    srcs = ["src/policy_configmap.rs"],
    edition = "2021",
    visibility = ["//visibility:public"],
    deps = [":headscale_values_lib"],
)

rust_binary(
    name = "render-check",
    srcs = ["src/render_check.rs"],
    data = ["applicationset.yaml"],
    edition = "2021",
    visibility = ["//visibility:public"],
    deps = [
        ":headscale_values_lib",
        "@crates//:serde_json",
    ],
)

rust_test(
    name = "headscale_values_test",
    size = "small",
    crate = ":headscale_values_lib",
    data = DATA_FILES,
    edition = "2021",
)

rust_test(
    name = "policy_configmap_drift_test",
    size = "small",
    srcs = ["src/policy_configmap_drift_test.rs"],
    data = [
        "configmap-policy.yaml",
        "policy.hujson",
    ],
    edition = "2021",
    deps = [":headscale_values_lib"],
)

rust_test(
    name = "policy_lockout_guard_test",
    size = "small",
    srcs = ["src/policy_lockout_guard_test.rs"],
    data = ["policy.hujson"],
    edition = "2021",
    deps = [":headscale_values_lib"],
)

rust_test(
    name = "policy_sync_test",
    size = "small",
    srcs = ["src/policy_sync_test.rs"],
    data = [
        "applicationset.yaml",
        "configmap-policy.yaml",
        "service-policy-sync.yaml",
    ],
    edition = "2021",
    deps = [":headscale_values_lib"],
)

# exporter.py, run straight out of configmap-key-exporter.yaml.
py_test(
    name = "key_exporter_test",
    size = "small",
    srcs = ["key_exporter_test.py"],
    data = ["configmap-key-exporter.yaml"],
)
