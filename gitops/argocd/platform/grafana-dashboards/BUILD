load("@aspect_rules_js//js:defs.bzl", "js_library")
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

# The shipped dashboards, whose tags the backend's dashboard-selector test
# checks catalog annotations against.
js_library(
    name = "backstage_backend_test_data",
    srcs = glob(["*.json"]),
    visibility = ["//apps/web/backstage/packages/backend:__pkg__"],
)
