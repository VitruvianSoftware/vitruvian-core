// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

pub const LAYER_PLATFORM_TOOLS: i32 = 0;
pub const LAYER_INFRA: i32 = 1;
pub const LAYER_SHARED_PACKAGES: i32 = 2;
pub const LAYER_APPS: i32 = 3;

pub fn layer_name(layer: i32) -> Option<&'static str> {
    match layer {
        LAYER_PLATFORM_TOOLS => Some("platform_tools"),
        LAYER_INFRA => Some("infra"),
        LAYER_SHARED_PACKAGES => Some("shared_packages"),
        LAYER_APPS => Some("apps"),
        _ => None,
    }
}

pub fn get_app_name(pkg_path: &str) -> String {
    let trimmed = pkg_path.trim_matches('/');
    let parts: Vec<&str> = trimmed.split('/').collect();
    if parts.len() >= 3 && parts[0] == "apps" {
        format!("{}/{}", parts[1], parts[2])
    } else if parts.len() >= 2 && parts[0] == "apps" {
        parts[1].to_string()
    } else if !parts.is_empty() && !parts[0].is_empty() {
        parts[0].to_string()
    } else {
        String::new()
    }
}

pub fn resolve_target_layer(pkg: &str, tags: &[&str]) -> (i32, String) {
    for tag in tags {
        match *tag {
            "@layer:platform_tools" | "layer:platform_tools" => {
                return (LAYER_PLATFORM_TOOLS, String::new());
            }
            "@layer:infra" | "layer:infra" => {
                return (LAYER_INFRA, String::new());
            }
            "@layer:shared_packages" | "layer:shared_packages" => {
                return (LAYER_SHARED_PACKAGES, String::new());
            }
            "@layer:apps" | "layer:apps" => {
                return (LAYER_APPS, get_app_name(pkg));
            }
            _ => {}
        }
    }

    if pkg.is_empty() || pkg.starts_with("tools") || pkg.starts_with(".aspect") {
        (LAYER_PLATFORM_TOOLS, String::new())
    } else if pkg.starts_with("infrastructure")
        || pkg.starts_with("pulumi")
        || pkg.starts_with("packages/pulumi")
        || pkg.starts_with("gitops")
    {
        (LAYER_INFRA, String::new())
    } else if pkg.starts_with("packages") {
        (LAYER_SHARED_PACKAGES, String::new())
    } else {
        (LAYER_APPS, get_app_name(pkg))
    }
}

pub fn validate_dependency(
    src_pkg: &str,
    src_tags: &[&str],
    dep_pkg: &str,
    dep_tags: &[&str],
) -> Vec<String> {
    let (src_layer, src_app) = resolve_target_layer(src_pkg, src_tags);
    let (dep_layer, dep_app) = resolve_target_layer(dep_pkg, dep_tags);
    let mut violations = Vec::new();

    if src_layer >= 0 && dep_layer > src_layer {
        violations.push(format!(
            "ARCHITECTURAL BOUNDARY VIOLATION [Downward-Only Layer Rule]:\n\
             \x20 Target:     {} (Layer {}: {})\n\
             \x20 Depends on: {} (Layer {}: {})\n\
             \x20 Constraint: A target in layer {} cannot depend on higher layer {}.",
            src_pkg,
            src_layer,
            layer_name(src_layer).unwrap_or("unknown"),
            dep_pkg,
            dep_layer,
            layer_name(dep_layer).unwrap_or("unknown"),
            layer_name(src_layer).unwrap_or("unknown"),
            layer_name(dep_layer).unwrap_or("unknown"),
        ));
    }

    if src_layer == LAYER_APPS
        && dep_layer == LAYER_APPS
        && !src_app.is_empty()
        && !dep_app.is_empty()
        && src_app != dep_app
    {
        violations.push(format!(
            "ARCHITECTURAL BOUNDARY VIOLATION [Inter-App Firewall Rule]:\n\
             \x20 Target:     {} (App: {})\n\
             \x20 Depends on: {} (App: {})\n\
             \x20 Constraint: Cross-application dependency between '{}' and '{}' is prohibited. \
             Move shared logic to //packages/.",
            src_pkg, src_app, dep_pkg, dep_app, src_app, dep_app,
        ));
    }

    violations
}

#[cfg(test)]
mod tests {
    use super::*;

    // --- layer_name ---

    #[test]
    fn layer_name_known() {
        assert_eq!(layer_name(LAYER_PLATFORM_TOOLS), Some("platform_tools"));
        assert_eq!(layer_name(LAYER_INFRA), Some("infra"));
        assert_eq!(layer_name(LAYER_SHARED_PACKAGES), Some("shared_packages"));
        assert_eq!(layer_name(LAYER_APPS), Some("apps"));
    }

    #[test]
    fn layer_name_unknown() {
        assert_eq!(layer_name(-1), None);
        assert_eq!(layer_name(4), None);
        assert_eq!(layer_name(99), None);
    }

    // --- get_app_name: test_boundaries.py assertions ---

    #[test]
    fn app_name_web_app() {
        assert_eq!(get_app_name("apps/web/gods-eye-view"), "web/gods-eye-view");
    }

    #[test]
    fn app_name_service_app() {
        assert_eq!(
            get_app_name("apps/services/tabula-api"),
            "services/tabula-api"
        );
    }

    #[test]
    fn app_name_mcp_app() {
        assert_eq!(get_app_name("apps/mcp/slack"), "mcp/slack");
    }

    #[test]
    fn app_name_suite_web() {
        assert_eq!(get_app_name("apps/suites/tabula/web"), "suites/tabula");
    }

    #[test]
    fn app_name_suite_api() {
        assert_eq!(get_app_name("apps/suites/tabula/api"), "suites/tabula");
    }

    #[test]
    fn app_name_firewall_collision() {
        assert_ne!(
            get_app_name("apps/web/gods-eye-view"),
            get_app_name("apps/web/analytics")
        );
    }

    // --- get_app_name: edge cases ---

    #[test]
    fn app_name_empty() {
        assert_eq!(get_app_name(""), "");
    }

    #[test]
    fn app_name_just_apps() {
        assert_eq!(get_app_name("apps"), "apps");
    }

    #[test]
    fn app_name_apps_web_only() {
        assert_eq!(get_app_name("apps/web"), "web");
    }

    #[test]
    fn app_name_leading_slash() {
        assert_eq!(get_app_name("/apps/web/foo"), "web/foo");
    }

    #[test]
    fn app_name_trailing_slash() {
        assert_eq!(get_app_name("apps/web/foo/"), "web/foo");
    }

    #[test]
    fn app_name_both_slashes() {
        assert_eq!(get_app_name("/apps/web/foo/"), "web/foo");
    }

    #[test]
    fn app_name_non_apps_prefix() {
        assert_eq!(get_app_name("tools/lint"), "tools");
    }

    #[test]
    fn app_name_single_segment() {
        assert_eq!(get_app_name("packages"), "packages");
    }

    // --- resolve_target_layer: path-based ---

    #[test]
    fn layer_empty_pkg() {
        assert_eq!(
            resolve_target_layer("", &[]),
            (LAYER_PLATFORM_TOOLS, String::new())
        );
    }

    #[test]
    fn layer_tools_prefix() {
        assert_eq!(
            resolve_target_layer("tools/lint", &[]),
            (LAYER_PLATFORM_TOOLS, String::new())
        );
    }

    #[test]
    fn layer_aspect_prefix() {
        assert_eq!(
            resolve_target_layer(".aspect/rules", &[]),
            (LAYER_PLATFORM_TOOLS, String::new())
        );
    }

    #[test]
    fn layer_infrastructure_prefix() {
        assert_eq!(
            resolve_target_layer("infrastructure/pulumi/platform", &[]),
            (LAYER_INFRA, String::new())
        );
    }

    #[test]
    fn layer_pulumi_prefix() {
        assert_eq!(
            resolve_target_layer("pulumi/something", &[]),
            (LAYER_INFRA, String::new())
        );
    }

    #[test]
    fn layer_packages_pulumi_prefix() {
        assert_eq!(
            resolve_target_layer("packages/pulumi/lib", &[]),
            (LAYER_INFRA, String::new())
        );
    }

    #[test]
    fn layer_gitops_prefix() {
        assert_eq!(
            resolve_target_layer("gitops/argocd", &[]),
            (LAYER_INFRA, String::new())
        );
    }

    #[test]
    fn layer_packages_prefix() {
        assert_eq!(
            resolve_target_layer("packages/design-system", &[]),
            (LAYER_SHARED_PACKAGES, String::new())
        );
    }

    #[test]
    fn layer_apps_prefix() {
        assert_eq!(
            resolve_target_layer("apps/web/gods-eye-view", &[]),
            (LAYER_APPS, "web/gods-eye-view".to_string())
        );
    }

    #[test]
    fn layer_unknown_top_level() {
        assert_eq!(
            resolve_target_layer("something/else", &[]),
            (LAYER_APPS, "something".to_string())
        );
    }

    // --- resolve_target_layer: tag overrides ---

    #[test]
    fn tag_override_platform_tools() {
        assert_eq!(
            resolve_target_layer("apps/web/foo", &["layer:platform_tools"]),
            (LAYER_PLATFORM_TOOLS, String::new())
        );
    }

    #[test]
    fn tag_override_platform_tools_at() {
        assert_eq!(
            resolve_target_layer("apps/web/foo", &["@layer:platform_tools"]),
            (LAYER_PLATFORM_TOOLS, String::new())
        );
    }

    #[test]
    fn tag_override_infra() {
        assert_eq!(
            resolve_target_layer("packages/foo", &["layer:infra"]),
            (LAYER_INFRA, String::new())
        );
    }

    #[test]
    fn tag_override_infra_at() {
        assert_eq!(
            resolve_target_layer("packages/foo", &["@layer:infra"]),
            (LAYER_INFRA, String::new())
        );
    }

    #[test]
    fn tag_override_shared_packages() {
        assert_eq!(
            resolve_target_layer("tools/something", &["layer:shared_packages"]),
            (LAYER_SHARED_PACKAGES, String::new())
        );
    }

    #[test]
    fn tag_override_shared_packages_at() {
        assert_eq!(
            resolve_target_layer("tools/something", &["@layer:shared_packages"]),
            (LAYER_SHARED_PACKAGES, String::new())
        );
    }

    #[test]
    fn tag_override_apps() {
        assert_eq!(
            resolve_target_layer("apps/web/foo", &["layer:apps"]),
            (LAYER_APPS, "web/foo".to_string())
        );
    }

    #[test]
    fn tag_override_apps_at() {
        assert_eq!(
            resolve_target_layer("apps/web/bar", &["@layer:apps"]),
            (LAYER_APPS, "web/bar".to_string())
        );
    }

    #[test]
    fn tag_unrecognised_ignored() {
        assert_eq!(
            resolve_target_layer("tools/lint", &["something-else"]),
            (LAYER_PLATFORM_TOOLS, String::new())
        );
    }

    #[test]
    fn tag_first_match_wins() {
        assert_eq!(
            resolve_target_layer("apps/web/foo", &["layer:infra", "layer:apps"]),
            (LAYER_INFRA, String::new())
        );
    }

    // --- validate_dependency: downward-only rule ---

    #[test]
    fn downward_ok_infra_to_platform() {
        let v = validate_dependency("infrastructure/x", &[], "tools/y", &[]);
        assert!(v.is_empty());
    }

    #[test]
    fn downward_ok_apps_to_packages() {
        let v = validate_dependency("apps/web/foo", &[], "packages/lib", &[]);
        assert!(v.is_empty());
    }

    #[test]
    fn downward_ok_same_layer() {
        let v = validate_dependency("packages/a", &[], "packages/b", &[]);
        assert!(v.is_empty());
    }

    #[test]
    fn downward_fail_platform_to_infra() {
        let v = validate_dependency("tools/lint", &[], "infrastructure/x", &[]);
        assert_eq!(v.len(), 1);
        assert!(v[0].contains("Downward-Only Layer Rule"));
    }

    #[test]
    fn downward_fail_platform_to_apps() {
        let v = validate_dependency("tools/lint", &[], "apps/web/foo", &[]);
        assert_eq!(v.len(), 1);
        assert!(v[0].contains("Downward-Only Layer Rule"));
    }

    #[test]
    fn downward_fail_shared_to_apps() {
        let v = validate_dependency("packages/lib", &[], "apps/web/foo", &[]);
        assert_eq!(v.len(), 1);
        assert!(v[0].contains("Downward-Only Layer Rule"));
    }

    #[test]
    fn downward_fail_infra_to_apps() {
        let v = validate_dependency("infrastructure/x", &[], "apps/web/foo", &[]);
        assert_eq!(v.len(), 1);
        assert!(v[0].contains("Downward-Only Layer Rule"));
    }

    // --- validate_dependency: inter-app firewall ---

    #[test]
    fn firewall_same_app_ok() {
        let v = validate_dependency(
            "apps/web/gods-eye-view/src",
            &[],
            "apps/web/gods-eye-view/lib",
            &[],
        );
        assert!(v.is_empty());
    }

    #[test]
    fn firewall_different_apps_fail() {
        let v = validate_dependency("apps/web/gods-eye-view", &[], "apps/web/analytics", &[]);
        assert_eq!(v.len(), 1);
        assert!(v[0].contains("Inter-App Firewall Rule"));
    }

    #[test]
    fn firewall_different_categories_fail() {
        let v = validate_dependency("apps/web/foo", &[], "apps/services/bar", &[]);
        assert_eq!(v.len(), 1);
        assert!(v[0].contains("Inter-App Firewall Rule"));
    }

    #[test]
    fn firewall_empty_src_app_no_trigger() {
        // "apps" alone yields app name "apps" which is non-empty, but it is the
        // same for both sides when both are "apps", so no violation.
        let v = validate_dependency("apps", &[], "apps", &[]);
        assert!(v.is_empty());
    }

    #[test]
    fn firewall_tag_override_avoids_firewall() {
        let v = validate_dependency(
            "apps/web/foo",
            &["layer:shared_packages"],
            "apps/web/bar",
            &[],
        );
        // src is now shared_packages (2), dep is apps (3) — downward violation, not firewall
        assert_eq!(v.len(), 1);
        assert!(v[0].contains("Downward-Only Layer Rule"));
        assert!(!v[0].contains("Inter-App Firewall Rule"));
    }

    // --- validate_dependency: both violations at once ---

    #[test]
    fn both_violations_possible() {
        // This cannot happen organically (downward requires src < dep, firewall
        // requires both == APPS), but confirm the logic is independent: a
        // platform_tools target cannot reach APPS *and* the firewall only fires
        // at layer 3 vs 3, so the two rules are mutually exclusive for
        // different-app cases. Verify no double-count on same-layer.
        let v = validate_dependency("apps/web/a", &[], "apps/web/b", &[]);
        assert_eq!(v.len(), 1); // only firewall, layers are equal
    }
}
