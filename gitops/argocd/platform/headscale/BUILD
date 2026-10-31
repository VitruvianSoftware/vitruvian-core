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

load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")
load("//tools/gitops:defs.bzl", "gitops_manifest")

# gazelle:ignore

gitops_manifest(
    name = "headscale",
    manifests = [
        "applicationset.yaml",
        "backendtrafficpolicy.yaml",
        "certificate.yaml",
        "configmap-edge.yaml",
        "configmap-headplane.yaml",
        "daemonset-node-agent.yaml",
        "deployment-edge-tunnel.yaml",
        "deployment-headplane.yaml",
        "deployment-subnet-router.yaml",
        "dnsendpoint.yaml",
        "httproute-headplane.yaml",
        "httproute.yaml",
        "pvc-headplane.yaml",
        "service-headplane.yaml",
    ],
)

DATA_FILES = [
    "applicationset.yaml",
    "backendtrafficpolicy.yaml",
    "certificate.yaml",
    "configmap-edge.yaml",
    "configmap-headplane.yaml",
    "daemonset-node-agent.yaml",
    "deployment-edge-tunnel.yaml",
    "deployment-subnet-router.yaml",
    "dnsendpoint.yaml",
    "httproute.yaml",
]

rust_library(
    name = "headscale_values_lib",
    srcs = [
        "src/lib.rs",
        "src/yaml.rs",
    ],
    crate_name = "headscale_values",
    edition = "2021",
    deps = [
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
