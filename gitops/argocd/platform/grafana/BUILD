load("@aspect_rules_js//js:defs.bzl", "js_library")
load("//tools/gitops:defs.bzl", "gitops_manifest")

gitops_manifest(
    name = "grafana",
    manifests = ["applicationset.yaml"],
)

# The backend's workload-identity test checks Grafana's GCP wiring here.
js_library(
    name = "applicationset",
    srcs = ["applicationset.yaml"],
    visibility = ["//apps/web/backstage/packages/backend:__pkg__"],
)
