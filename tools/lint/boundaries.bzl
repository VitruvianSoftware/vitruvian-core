# Copyright (c) 2026 VitruvianSoftware
#
# Compile-time architectural boundary aspect enforcing layer hierarchy
# (:platform_tools -> :infra -> :shared_packages -> :apps) and the inter-app firewall.

load(
    "//tools/boundaries:package_groups.bzl",
    "LAYER_APPS",
    "LAYER_INFRA",
    "LAYER_NAMES",
    "LAYER_PLATFORM_TOOLS",
    "LAYER_SHARED_PACKAGES",
)

BoundaryInfo = provider(
    "Propagates target layer and boundary validation status",
    fields = {
        "layer": "int: layer level (0=platform_tools, 1=infra, 2=shared_packages, 3=apps)",
        "app": "string: application name if layer is apps, else empty string",
        "violations": "depset of string: formatted violation messages",
    },
)

def _get_app_name(pkg_path):
    """Extracts application name from package path (first path component)."""
    parts = pkg_path.split("/")
    if len(parts) > 0 and parts[0]:
        return parts[0]
    return ""

def _resolve_target_layer(target, ctx):
    """Determines layer and app name from target tags and package path."""
    tags = getattr(ctx.rule.attr, "tags", []) if ctx else []

    # 1. Explicit tags override path inference
    for tag in tags:
        if tag in ("@layer:platform_tools", "layer:platform_tools"):
            return LAYER_PLATFORM_TOOLS, ""
        elif tag in ("@layer:infra", "layer:infra"):
            return LAYER_INFRA, ""
        elif tag in ("@layer:shared_packages", "layer:shared_packages"):
            return LAYER_SHARED_PACKAGES, ""
        elif tag in ("@layer:apps", "layer:apps"):
            return LAYER_APPS, _get_app_name(target.label.package)

    # 2. Path-based inference for first-party workspace targets
    pkg = target.label.package
    if not pkg or pkg.startswith("tools") or pkg.startswith("githooks") or pkg.startswith(".aspect"):
        return LAYER_PLATFORM_TOOLS, ""
    elif pkg.startswith("infrastructure") or pkg.startswith("pulumi") or pkg.startswith("gitops"):
        return LAYER_INFRA, ""
    elif pkg.startswith("packages") or pkg.startswith("architecture"):
        return LAYER_SHARED_PACKAGES, ""
    else:
        # Default to application tier for top-level component packages
        return LAYER_APPS, _get_app_name(pkg)

def _boundary_aspect_impl(target, ctx):
    # Skip external dependencies (rules_*, npm, maven, etc.)
    if target.label.workspace_name != "":
        return [BoundaryInfo(layer = -1, app = "", violations = depset())]

    src_layer, src_app = _resolve_target_layer(target, ctx)
    violations = []

    # Dependency attributes to patrol
    dep_attrs = ["deps", "runtime_deps", "data", "embed", "plugins"]

    for attr_name in dep_attrs:
        if not hasattr(ctx.rule.attr, attr_name):
            continue
        attr_val = getattr(ctx.rule.attr, attr_name)
        deps_list = attr_val if type(attr_val) == "list" else [attr_val]

        for dep in deps_list:
            if not hasattr(dep, "label"):
                continue

            # Skip external deps
            if dep.label.workspace_name != "":
                continue

            if BoundaryInfo in dep:
                dep_info = dep[BoundaryInfo]
                dep_layer = dep_info.layer
                dep_app = dep_info.app
            else:
                dep_layer, dep_app = _resolve_target_layer(dep, None)

            # Invariant 1: Downward-only dependencies (src_layer >= dep_layer)
            if src_layer >= 0 and dep_layer > src_layer:
                violations.append(
                    "ARCHITECTURAL BOUNDARY VIOLATION [Downward-Only Layer Rule]:\n" +
                    "  Target:     %s (Layer %d: %s)\n" % (target.label, src_layer, LAYER_NAMES.get(src_layer, "unknown")) +
                    "  Depends on: %s (Layer %d: %s)\n" % (dep.label, dep_layer, LAYER_NAMES.get(dep_layer, "unknown")) +
                    "  Constraint: A target in layer %s cannot depend on higher layer %s." % (
                        LAYER_NAMES.get(src_layer, "unknown"),
                        LAYER_NAMES.get(dep_layer, "unknown"),
                    ),
                )

            # Invariant 2: Inter-App Firewall (Apps cannot depend on other apps)
            if src_layer == LAYER_APPS and dep_layer == LAYER_APPS:
                if src_app != "" and dep_app != "" and src_app != dep_app:
                    violations.append(
                        "ARCHITECTURAL BOUNDARY VIOLATION [Inter-App Firewall Rule]:\n" +
                        "  Target:     %s (App: %s)\n" % (target.label, src_app) +
                        "  Depends on: %s (App: %s)\n" % (dep.label, dep_app) +
                        "  Constraint: Cross-application dependency between '%s' and '%s' is prohibited. Move shared logic to //packages/." % (
                            src_app,
                            dep_app,
                        ),
                    )

    # Produce validation report artifact
    report_file = ctx.actions.declare_file(target.label.name + ".boundary_report")
    if violations:
        content = "\n\n".join(violations) + "\n"
    else:
        content = "OK: %s satisfies architectural boundary constraints.\n" % target.label

    ctx.actions.write(
        output = report_file,
        content = content,
    )

    all_violations = depset(violations)

    return [
        BoundaryInfo(
            layer = src_layer,
            app = src_app,
            violations = all_violations,
        ),
        OutputGroupInfo(
            rules_lint_human = depset([report_file]),
            rules_lint_report = depset([report_file]),
        ),
    ]

boundary_aspect = aspect(
    implementation = _boundary_aspect_impl,
    attr_aspects = ["deps", "runtime_deps", "data", "embed", "plugins"],
    doc = "Validates architectural layer boundaries and inter-app isolation.",
)
