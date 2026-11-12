load("//tools/delivery:defs.bzl", "delivery")
load("//tools/pulumi:defs.bzl", "pulumi_project")

pulumi_project(
    name = "vitruvian-tabs-build",
    dir = "apps/suites/vitruvian-tabs/infra/build",
)

# Delivery unit (delivery-orchestrator PHASE 2, Wave B2): the cross-env
# Artifact Registry + build SA in the shared infra-pipeline project — the
# stack the `vitruvian-tabs-build` job's WIF binding depends on.
#
# ONE RUNG named "shared", which resolves the github_environment pattern to
# foundation-proj-shared (the stage-4 projects SA that owns the infra-pipeline
# project; the build SA this stack CREATES cannot be the identity that applies
# it). The Pulumi STACK it applies is "production" — that is baked into the
# transcribed step, exactly as the legacy job spells it, because the stack name
# and the rung name are different facts here.
delivery(
    name = "vitruvian-tabs-build-stack",
    app = "vitruvian-tabs",
    environments = ["shared"],
    extra_paths = [
        "apps/suites/vitruvian-tabs/infra/build/",
    ],
    github_environment = "foundation-proj-{env}",
    kind = "pulumi",
    # Called tabula-build-stack (app tabula) until #4631; its earlier deploys ran under that name.
    renamed_from = "tabula-build-stack",
    renamed_from_app = "tabula",
    render = "transcribed",
    run = "//apps/suites/vitruvian-tabs/infra/build:up",
)
