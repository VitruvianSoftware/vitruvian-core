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

import { resolve } from "path";
import Router from "express-promise-router";
import type { CatalogClient } from "@backstage/catalog-client";
import type {
  LoggerService,
  RootConfigService,
} from "@backstage/backend-plugin-api";
import type { Entity } from "@backstage/catalog-model";
import { evaluateEntityScorecard } from "./evaluator";

export type RouterOptions = {
  catalogClient?: CatalogClient;
  logger: LoggerService;
  config?: RootConfigService;
  repoRoot?: string;
  githubToken?: string;
};

export async function createScorecardRouter(
  options: RouterOptions,
): Promise<ReturnType<typeof Router>> {
  const router = Router();
  const repoRoot = options.repoRoot ?? resolve(__dirname, "../../../../..");
  let githubToken =
    options.githubToken ?? process.env.GITHUB_TOKEN ?? process.env.GH_TOKEN;

  if (!githubToken && options.config) {
    try {
      if (options.config.has("integrations.github")) {
        const githubConfigs = options.config.getOptionalConfigArray(
          "integrations.github",
        );
        githubToken = githubConfigs?.[0]?.getOptionalString("token");
      }
    } catch {
      // In smoke tests or standalone runs with minimal config schemas, ignore
    }
  }

  router.get("/entities/:kind/:namespace/:name", async (req, res) => {
    const { kind, namespace, name } = req.params;
    const entityRef = `${kind}:${namespace}/${name}`;

    try {
      let entity: Entity | undefined;
      if (options.catalogClient) {
        entity = await options.catalogClient.getEntityByRef(entityRef);
      }

      if (!entity) {
        // Construct fallback entity object if client is not wired in local test
        entity = {
          apiVersion: "backstage.io/v1alpha1",
          kind: kind.charAt(0).toUpperCase() + kind.slice(1),
          metadata: {
            name,
            namespace,
          },
          spec: {},
        };
      }

      const scorecard = await evaluateEntityScorecard(
        entity,
        repoRoot,
        githubToken,
      );
      res.json(scorecard);
    } catch (e) {
      options.logger.error(
        `Scorecard evaluation failed for ${entityRef}: ${e}`,
      );
      res.status(500).json({ error: String(e) });
    }
  });

  router.post("/evaluate", async (req, res) => {
    try {
      const entity = req.body as Entity;
      if (!entity || !entity.metadata?.name) {
        res.status(400).json({ error: "Invalid entity payload" });
        return;
      }
      const scorecard = await evaluateEntityScorecard(
        entity,
        repoRoot,
        githubToken,
      );
      res.json(scorecard);
    } catch (e) {
      options.logger.error(`Scorecard evaluation failed: ${e}`);
      res.status(500).json({ error: String(e) });
    }
  });

  return router;
}
