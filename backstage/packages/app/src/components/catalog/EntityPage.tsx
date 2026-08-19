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

import React from "react";
import { Button, Grid } from "@material-ui/core";
import {
  EntityLayout,
  EntityAboutCard,
  EntityDependsOnComponentsCard,
  EntityDependsOnResourcesCard,
  EntityHasComponentsCard,
  EntityHasResourcesCard,
  EntityHasSubcomponentsCard,
  EntityHasSystemsCard,
  EntityLinksCard,
  EntitySwitch,
  isComponentType,
  isKind,
} from "@backstage/plugin-catalog";
import {
  EntityUserProfileCard,
  EntityGroupProfileCard,
  EntityMembersListCard,
  EntityOwnershipCard,
} from "@backstage/plugin-org";
import { EntityTechdocsContent } from "@backstage/plugin-techdocs";
import {
  EntityGithubActionsContent,
  EntityRecentGithubActionsRunsCard,
  isGithubActionsAvailable,
} from "@backstage-community/plugin-github-actions";
import { EntityCatalogGraphCard } from "@backstage/plugin-catalog-graph";
import {
  EntityKubernetesContent,
  isKubernetesAvailable,
} from "@backstage/plugin-kubernetes";
import {
  EntityGrafanaDashboardsCard,
  isDashboardSelectorAvailable,
} from "@backstage-community/plugin-grafana";
import { DeployWorkflowRunsCard } from "./DeployWorkflowRunsCard";
import { isDeployWorkflowAvailable } from "./deployWorkflowRuns";
import {
  EntityArgoCDContent,
  EntityArgoCDOverviewCard,
  isArgocdAvailable,
} from "@roadiehq/backstage-plugin-argo-cd";

const defaultEntityPage = (
  <EntityLayout>
    <EntityLayout.Route path="/" title="Overview">
      <Grid container spacing={3} alignItems="stretch">
        <Grid item md={6}>
          <EntityAboutCard variant="gridItem" />
        </Grid>
        <Grid item md={6} xs={12}>
          <EntityCatalogGraphCard variant="gridItem" height={400} />
        </Grid>
        <Grid item md={4} xs={12}>
          <EntityLinksCard />
        </Grid>
        {/* Recent CI runs, but only for entities that actually declare a
            github.com/project-slug -- rendering it unconditionally would show a
            permanently-empty card on every entity that has no repository. */}
        <EntitySwitch>
          <EntitySwitch.Case if={isGithubActionsAvailable}>
            <Grid item md={8} xs={12}>
              <EntityRecentGithubActionsRunsCard limit={5} />
            </Grid>
          </EntitySwitch.Case>
        </EntitySwitch>
        {/* Runs of the ONE workflow that deploys this component, for entities
            that name it. The upstream card above cannot narrow: it takes only
            `limit` and keys off github.com/project-slug, so in this monorepo it
            shows every component the same unrelated runs. */}
        <EntitySwitch>
          <EntitySwitch.Case if={isDeployWorkflowAvailable}>
            <Grid item md={8} xs={12}>
              <DeployWorkflowRunsCard limit={5} />
            </Grid>
          </EntitySwitch.Case>
        </EntitySwitch>
        {/* Grafana dashboards for this entity. Guarded on the
            grafana/dashboard-selector annotation for the same reason as the CI
            card above: unguarded it renders an empty box on every entity.
            Note there is deliberately no EntityGrafanaAlertsCard -- that card
            only reads Grafana-MANAGED alert rules, and this cluster's 42 rules
            are datasource-managed (evaluated by Prometheus), so it would be
            permanently empty. See docs/backstage-grafana.md. */}
        <EntitySwitch>
          {/* Wrapped in Boolean(): despite the `is` prefix, the plugin's
              isDashboardSelectorAvailable returns `string | undefined` (the
              annotation value), while EntitySwitch.Case expects a boolean
              predicate. It would coerce at runtime, but the cast keeps the
              types honest. */}
          <EntitySwitch.Case
            if={(entity) => Boolean(isDashboardSelectorAvailable(entity))}
          >
            <Grid item md={6} xs={12}>
              <EntityGrafanaDashboardsCard />
            </Grid>
          </EntitySwitch.Case>
        </EntitySwitch>
        {/* Deployment state at a glance: sync + health per ArgoCD Application.
            Unlike isDashboardSelectorAvailable, isArgocdAvailable already
            returns a boolean, so it needs no Boolean() wrapper. It is true when
            the entity carries argocd/app-name, argocd/app-selector, or
            argocd/project-name -- entities deployed some other way (Cloud Run,
            GitHub Pages) simply never render this. */}
        <EntitySwitch>
          <EntitySwitch.Case if={isArgocdAvailable}>
            <Grid item md={6} xs={12}>
              <EntityArgoCDOverviewCard />
            </Grid>
          </EntitySwitch.Case>
        </EntitySwitch>
      </Grid>
    </EntityLayout.Route>
    {/* `if` is what keeps this honest: without it the tab renders for every
        entity -- including Users and Groups -- and fails at the API call
        instead of simply not being offered. */}
    <EntityLayout.Route
      path="/ci-cd"
      title="CI/CD"
      if={isGithubActionsAvailable}
    >
      <EntityGithubActionsContent />
    </EntityLayout.Route>
    <EntityLayout.Route path="/docs" title="Docs">
      <EntityTechdocsContent />
    </EntityLayout.Route>
    {/*
      Sync history and revision detail -- what git commit is actually live, and
      whether the last sync succeeded. Same `if` discipline as the CI/CD and
      Kubernetes tabs: gate the tab on the annotation so entities ArgoCD does
      not deploy are never offered a tab that can only fail.
    */}
    <EntityLayout.Route
      path="/argocd"
      title="Deployments"
      if={isArgocdAvailable}
    >
      <EntityArgoCDContent />
    </EntityLayout.Route>
    {/*
      Live workload state: pods, health, images, events. `if` gates the tab on
      the entity actually declaring a kubernetes annotation, so components that
      do not run in the cluster (CLIs, libraries, Cloud Run services) do not get
      an empty tab promising data that will never arrive.
    */}
    <EntityLayout.Route
      path="/kubernetes"
      title="Kubernetes"
      if={isKubernetesAvailable}
    >
      <EntityKubernetesContent refreshIntervalMs={30000} />
    </EntityLayout.Route>
  </EntityLayout>
);

const componentPage = defaultEntityPage;

const systemPage = (
  <EntityLayout>
    <EntityLayout.Route path="/" title="Overview">
      <Grid container spacing={3} alignItems="stretch">
        <Grid item md={6}>
          <EntityAboutCard variant="gridItem" />
        </Grid>
        <Grid item md={6} xs={12}>
          <EntityCatalogGraphCard variant="gridItem" height={400} />
        </Grid>
        <Grid item md={6}>
          <EntityHasComponentsCard variant="gridItem" />
        </Grid>
        <Grid item md={6}>
          <EntityHasResourcesCard variant="gridItem" />
        </Grid>
      </Grid>
    </EntityLayout.Route>
  </EntityLayout>
);

const userPage = (
  <EntityLayout>
    <EntityLayout.Route path="/" title="Overview">
      <Grid container spacing={3}>
        <Grid item xs={12} md={6}>
          <EntityUserProfileCard variant="gridItem" />
        </Grid>
        <Grid item xs={12} md={6}>
          <EntityOwnershipCard variant="gridItem" />
        </Grid>
      </Grid>
    </EntityLayout.Route>
  </EntityLayout>
);

const groupPage = (
  <EntityLayout>
    <EntityLayout.Route path="/" title="Overview">
      <Grid container spacing={3}>
        <Grid item xs={12} md={6}>
          <EntityGroupProfileCard variant="gridItem" />
        </Grid>
        <Grid item xs={12} md={6}>
          <EntityOwnershipCard variant="gridItem" />
        </Grid>
        <Grid item xs={12}>
          <EntityMembersListCard />
        </Grid>
      </Grid>
    </EntityLayout.Route>
  </EntityLayout>
);

export const entityPage = (
  <EntitySwitch>
    <EntitySwitch.Case if={isKind("component")} children={componentPage} />
    <EntitySwitch.Case if={isKind("system")} children={systemPage} />
    <EntitySwitch.Case if={isKind("user")} children={userPage} />
    <EntitySwitch.Case if={isKind("group")} children={groupPage} />
    <EntitySwitch.Case children={defaultEntityPage} />
  </EntitySwitch>
);
