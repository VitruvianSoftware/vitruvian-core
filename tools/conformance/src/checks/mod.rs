// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! All conformance check functions, ported from check.sh.

mod app;
mod catalog;
mod ci;
mod delivery;
mod governance;
mod iac;
mod labels;
mod security;
mod versions;

use crate::Context;

pub fn run_all(ctx: &Context) {
    versions::check_go(ctx);
    versions::check_node(ctx);
    versions::check_pnpm(ctx);
    versions::stale_sweep(ctx);
    versions::doc_sync(ctx);
    if ctx.is_dead() {
        return;
    }
    versions::check_pnpm_pin(ctx);

    catalog::check_catalog(ctx);
    catalog::check_standalone_workspace_deps(ctx);
    catalog::catalog_orphan_sweep(ctx);
    catalog::advisory_catalog(ctx);

    app::check_app_visibility(ctx);
    app::check_app_metadata(ctx);
    app::check_techdocs(ctx);

    ci::check_merge_queue(ctx);
    ci::check_postsubmit_concurrency(ctx);
    ci::check_job_timeouts(ctx);
    ci::check_sweep_backstop(ctx);
    ci::check_cache_save(ctx);
    ci::check_goproxy_fallback(ctx);

    iac::check_zitadel_import(ctx);
    iac::check_pulumi_project_names(ctx);
    iac::check_pulumi_project_renames(ctx);
    iac::check_custom_domain_zone(ctx);
    iac::check_release_please_packages(ctx);
    iac::check_copybara_infra_exclude(ctx);
    iac::check_copybara_version_maps(ctx);
    iac::check_copybara_export_triggers(ctx);
    iac::check_copybara_component_lists(ctx);

    iac::check_release_infra_exclude(ctx);
    delivery::check_no_local_paths(ctx);
    ci::check_ci_gate_lists_match(ctx);
    delivery::check_deploy_sequencer_gate(ctx);
    delivery::check_deploy_durable_base(ctx);
    delivery::check_delivery(ctx);
    delivery::check_deleted_workflow_references(ctx);

    governance::check_renovate_schedule(ctx);
    governance::check_chart_owned_crds(ctx);
    governance::check_project_kind_allowlist(ctx);
    governance::check_oci_base_registry(ctx);
    governance::check_backstage_prometheus_graphs(ctx);
    governance::check_backstage_prometheus_alerts(ctx);

    governance::check_naming_conventions(ctx);
    governance::check_owners(ctx);
    governance::check_root_directories(ctx);
    governance::check_preview_governance(ctx);
    governance::check_lab_hostnames_served(ctx);

    security::check_checkout_credentials(ctx);
    security::check_dependabot_action_coverage(ctx);
    security::check_action_sha_pins(ctx);
    security::check_gitleaks_allowlist_paths(ctx);
    security::check_guard_review_paths(ctx);
}

/// The workflow-label check alone: `bazel run //tools/conformance:workflow-labels`.
/// Not part of run_all (see the note in labels.rs on where it runs).
pub fn run_workflow_labels(ctx: &Context) {
    labels::check_workflow_labels(ctx);
}
