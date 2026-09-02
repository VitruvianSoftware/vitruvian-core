load("//tools/gitops:defs.bzl", "gitops_manifest")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "grafana-dashboards-files",
    srcs = glob([
        "*.json",
        "*.yaml",
    ]),
)

gitops_manifest(
    name = "grafana-dashboards",
    manifests = ["kustomization.yaml"],
)
