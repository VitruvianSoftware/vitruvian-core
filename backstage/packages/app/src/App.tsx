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
import { Navigate, Route } from "react-router-dom";
import { apiDocsPlugin, ApiExplorerPage } from "@backstage/plugin-api-docs";
import {
  CatalogEntityPage,
  CatalogIndexPage,
  catalogPlugin,
} from "@backstage/plugin-catalog";
import {
  CatalogImportPage,
  catalogImportPlugin,
} from "@backstage/plugin-catalog-import";
import { ScaffolderPage, scaffolderPlugin } from "@backstage/plugin-scaffolder";
import { orgPlugin } from "@backstage/plugin-org";
import { SearchPage } from "@backstage/plugin-search";
import {
  TechDocsIndexPage,
  techdocsPlugin,
  TechDocsReaderPage,
} from "@backstage/plugin-techdocs";
import { TechDocsAddons } from "@backstage/plugin-techdocs-react";
import { ReportIssue } from "@backstage/plugin-techdocs-module-addons-contrib";
import { UserSettingsPage } from "@backstage/plugin-user-settings";
import { apis } from "./apis";
import { entityPage } from "./components/catalog/EntityPage";
import { searchPage } from "./components/search/SearchPage";
import { Root } from "./components/Root";
import {
  AlertDisplay,
  OAuthRequestDialog,
  SignInPage,
} from "@backstage/core-components";
import { createApp } from "@backstage/app-defaults";
import { AppRouter, FlatRoutes } from "@backstage/core-app-api";
import { CatalogGraphPage } from "@backstage/plugin-catalog-graph";
import { RequirePermission } from "@backstage/plugin-permission-react";
import { catalogEntityCreatePermission } from "@backstage/plugin-catalog-common";
import { githubAuthApiRef } from "@backstage/core-plugin-api";
import {
  vitruvianDarkTheme,
  vitruvianLightTheme,
} from "./theme/vitruvianTheme";
import DarkModeIcon from "@material-ui/icons/Brightness4";
import LightModeIcon from "@material-ui/icons/Brightness7";

const app = createApp({
  apis,
  bindRoutes({ bind }) {
    bind(catalogPlugin.externalRoutes, {
      createComponent: scaffolderPlugin.routes.root,
      viewTechDoc: techdocsPlugin.routes.docRoot,
      createFromTemplate: scaffolderPlugin.routes.selectedTemplate,
    });
    bind(apiDocsPlugin.externalRoutes, {
      registerApi: catalogImportPlugin.routes.importPage,
    });
    bind(scaffolderPlugin.externalRoutes, {
      registerComponent: catalogImportPlugin.routes.importPage,
      viewTechDoc: techdocsPlugin.routes.docRoot,
    });
    bind(orgPlugin.externalRoutes, {
      catalogIndex: catalogPlugin.routes.catalogIndex,
    });
  },
  components: {
    SignInPage: (props) => (
      <SignInPage
        {...props}
        auto
        providers={[
          "guest",
          {
            id: "github-auth-provider",
            title: "GitHub",
            message: "Sign in using GitHub",
            apiRef: githubAuthApiRef,
          },
        ]}
      />
    ),
  },
  themes: [
    {
      id: "vitruvian-dark",
      title: "Vitruvian Dark",
      variant: "dark",
      icon: <DarkModeIcon />,
      theme: vitruvianDarkTheme,
    },
    {
      id: "vitruvian-light",
      title: "Vitruvian Light",
      variant: "light",
      icon: <LightModeIcon />,
      theme: vitruvianLightTheme,
    },
  ],
});

const routes = (
  <FlatRoutes>
    <Route path="/" element={<Navigate to="catalog" />} />
    <Route path="/catalog" element={<CatalogIndexPage />} />
    <Route
      path="/catalog/:namespace/:kind/:name"
      element={<CatalogEntityPage />}
    >
      {entityPage}
    </Route>
    <Route path="/docs" element={<TechDocsIndexPage />} />
    <Route
      path="/docs/:namespace/:kind/:name/*"
      element={<TechDocsReaderPage />}
    >
      <TechDocsAddons>
        <ReportIssue />
      </TechDocsAddons>
    </Route>
    <Route path="/create" element={<ScaffolderPage />} />
    <Route path="/api-docs" element={<ApiExplorerPage />} />
    <Route
      path="/catalog-import"
      element={
        <RequirePermission permission={catalogEntityCreatePermission}>
          <CatalogImportPage />
        </RequirePermission>
      }
    />
    <Route path="/search" element={<SearchPage />}>
      {searchPage}
    </Route>
    <Route path="/settings" element={<UserSettingsPage />} />
    <Route path="/catalog-graph" element={<CatalogGraphPage />} />
  </FlatRoutes>
);

export default app.createRoot(
  <>
    <AlertDisplay />
    <OAuthRequestDialog />
    <AppRouter>
      <Root>{routes}</Root>
    </AppRouter>
  </>,
);
