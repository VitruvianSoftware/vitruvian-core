load("//tools/delivery:defs.bzl", "delivery")
load("//tools/pulumi:defs.bzl", "pulumi_project")

pulumi_project(
    name = "tabula-build",
    dir = "tabula/infra/build",
)

# Delivery unit (delivery-orchestrator PHASE 2, Wave B2): the cross-env
# Artifact Registry + build SA in the shared infra-pipeline project — the
# stack the `tabula-build` job's WIF binding depends on.
#
# ONE RUNG named "shared", which resolves the github_environment pattern to
# foundation-proj-shared (the stage-4 projects SA that owns the infra-pipeline
# project; the build SA this stack CREATES cannot be the identity that applies
# it). The Pulumi STACK it applies is "production" — that is baked into the
# transcribed step, exactly as the legacy job spells it, because the stack name
# and the rung name are different facts here.
delivery(
    name = "tabula-build-stack",
    environments = ["shared"],
    extra_paths = [
        "tabula/infra/build/",
        "\\.github/workflows/tabula-build-stack\\.yaml",
    ],
    github_environment = "foundation-proj-{env}",
    kind = "pulumi",
    legacy_job = "deploy",
    legacy_workflow = ".github/workflows/tabula-build-stack.yaml",
    render = "transcribed",
    run = "//tabula/infra/build:up",
)
