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

import {
  AuthService,
  DiscoveryService,
  LoggerService,
  coreServices,
  createBackendModule,
} from "@backstage/backend-plugin-api";
import {
  ActionsRegistryService,
  actionsRegistryServiceRef,
} from "@backstage/backend-plugin-api/alpha";
import { CatalogClient } from "@backstage/catalog-client";

/**
 * Registers Backstage Software Catalog actions into the ActionsRegistry
 * (alpha.actionsRegistryServiceRef).
 */
export async function registerCatalogMcpActions({
  actionsRegistry,
  discovery,
  auth,
  logger,
}: {
  actionsRegistry: ActionsRegistryService;
  discovery: DiscoveryService;
  auth: AuthService;
  logger: LoggerService;
}) {
  const catalogClient = new CatalogClient({ discoveryApi: discovery });

  logger.info("Registering Catalog MCP actions in ActionsRegistry");

  // Action: catalog.get_entities
  actionsRegistry.register({
    name: "get_entities",
    title: "Get Catalog Entities",
    description:
      "List and filter entities from the Backstage Software Catalog (Components, Systems, APIs, Resources, Users, Groups).",
    attributes: {
      readOnly: true,
      idempotent: true,
    },
    schema: {
      input: (z) =>
        z.object({
          filter: z
            .record(z.any())
            .optional()
            .describe(
              "Optional filter expression, e.g. { 'kind': 'Component', 'spec.type': 'service' }",
            ),
          fields: z
            .array(z.string())
            .optional()
            .describe("Optional fields to return for each entity"),
          limit: z
            .number()
            .optional()
            .describe("Maximum number of entities to return"),
          offset: z
            .number()
            .optional()
            .describe("Offset for paginated catalog results"),
        }),
      output: (z) =>
        z.object({
          items: z.array(z.any()).describe("List of matched catalog entities"),
        }),
    },
    async action({ input, credentials }) {
      const { token } = await auth.getPluginRequestToken({
        onBehalfOf: credentials,
        targetPluginId: "catalog",
      });

      const response = await catalogClient.getEntities(
        {
          filter: input.filter,
          fields: input.fields,
          limit: input.limit,
          offset: input.offset,
        },
        { token },
      );

      return {
        output: {
          items: response.items,
        },
      };
    },
  });

  // Action: catalog.get_entity_by_name
  actionsRegistry.register({
    name: "get_entity_by_name",
    title: "Get Catalog Entity By Name",
    description:
      "Look up a single entity in the Backstage Software Catalog by its kind, name, and optional namespace.",
    attributes: {
      readOnly: true,
      idempotent: true,
    },
    schema: {
      input: (z) =>
        z.object({
          kind: z
            .string()
            .describe(
              "Entity kind (e.g. Component, System, API, Resource, User, Group, Template, Location)",
            ),
          name: z.string().describe("Entity name"),
          namespace: z
            .string()
            .optional()
            .default("default")
            .describe("Entity namespace (default: 'default')"),
        }),
      output: (z) =>
        z.object({
          entity: z
            .any()
            .nullable()
            .describe("The resolved entity object, or null if not found"),
        }),
    },
    async action({ input, credentials }) {
      const { token } = await auth.getPluginRequestToken({
        onBehalfOf: credentials,
        targetPluginId: "catalog",
      });

      const entity = await catalogClient.getEntityByRef(
        {
          kind: input.kind,
          name: input.name,
          namespace: input.namespace ?? "default",
        },
        { token },
      );

      return {
        output: {
          entity: entity ?? null,
        },
      };
    },
  });

  // Action: catalog.get_entity_facets
  actionsRegistry.register({
    name: "get_entity_facets",
    title: "Get Catalog Entity Facets",
    description:
      "Retrieve facet counts (e.g. count by kind, lifecycle, owner, system) across Backstage Software Catalog entities.",
    attributes: {
      readOnly: true,
      idempotent: true,
    },
    schema: {
      input: (z) =>
        z.object({
          facets: z
            .array(z.string())
            .describe(
              "List of entity fields to aggregate (e.g. ['kind', 'spec.type', 'spec.lifecycle', 'spec.owner'])",
            ),
          filter: z
            .record(z.any())
            .optional()
            .describe("Optional entity filter"),
        }),
      output: (z) =>
        z.object({
          facets: z
            .record(z.array(z.any()))
            .describe("Aggregated facet counts"),
        }),
    },
    async action({ input, credentials }) {
      const { token } = await auth.getPluginRequestToken({
        onBehalfOf: credentials,
        targetPluginId: "catalog",
      });

      const response = await catalogClient.getEntityFacets(
        {
          facets: input.facets,
          filter: input.filter,
        },
        { token },
      );

      return {
        output: {
          facets: response.facets,
        },
      };
    },
  });
}

/**
 * Backend module that registers Catalog actions for MCP.
 */
export const catalogModuleMcpActions = createBackendModule({
  pluginId: "catalog",
  moduleId: "mcp-actions",
  register(reg) {
    reg.registerInit({
      deps: {
        actionsRegistry: actionsRegistryServiceRef,
        discovery: coreServices.discovery,
        auth: coreServices.auth,
        logger: coreServices.logger,
      },
      async init({ actionsRegistry, discovery, auth, logger }) {
        await registerCatalogMcpActions({
          actionsRegistry,
          discovery,
          auth,
          logger,
        });
      },
    });
  },
});
