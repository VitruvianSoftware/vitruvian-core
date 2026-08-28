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
import {
  AuthService,
  DiscoveryService,
  LoggerService,
  RootConfigService,
  UserInfoService,
  coreServices,
  createBackendModule,
} from "@backstage/backend-plugin-api";
import {
  ActionsRegistryService,
  actionsRegistryServiceRef,
} from "@backstage/backend-plugin-api/alpha";
import { CatalogClient } from "@backstage/catalog-client";
import { parseEntityRef } from "@backstage/catalog-model";
import { evaluateEntityScorecard } from "../scorecards/evaluator";

/**
 * Registers Backstage Software Catalog, TechDocs, Scaffolder, Search, and
 * Scorecards actions into the ActionsRegistry (alpha.actionsRegistryServiceRef).
 *
 * All action names use snake_case and all schemas avoid z.any(), z.union(),
 * anyOf, and oneOf to remain compatible with Google Gemini's
 * FunctionDeclaration validator (^[a-zA-Z0-9_]{1,64}$, strict JSON Schema).
 */
export async function registerCatalogMcpActions({
  actionsRegistry,
  discovery,
  auth,
  userInfo,
  logger,
  config,
  catalogClient: customCatalogClient,
  repoRoot: optionsRepoRoot,
  githubToken: optionsGithubToken,
}: {
  actionsRegistry: ActionsRegistryService;
  discovery: DiscoveryService;
  auth: AuthService;
  userInfo: UserInfoService;
  logger: LoggerService;
  config?: RootConfigService;
  catalogClient?: CatalogClient;
  repoRoot?: string;
  githubToken?: string;
}) {
  const catalogClient =
    customCatalogClient ?? new CatalogClient({ discoveryApi: discovery });

  logger.info("Registering Catalog MCP actions in ActionsRegistry");

  // ─── Read-Only Actions ───────────────────────────────────────────────

  // Action: get_entities
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
            .record(z.string())
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
          items: z
            .array(z.record(z.unknown()))
            .describe("List of matched catalog entities"),
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

  // Action: get_entity_by_name
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
            .record(z.unknown())
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

  // Action: get_entity_facets
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
            .record(z.string())
            .optional()
            .describe("Optional entity filter"),
        }),
      output: (z) =>
        z.object({
          facets: z
            .record(z.array(z.record(z.unknown())))
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

  // Action: query_catalog_entities
  // Gemini-safe re-implementation of upstream query-catalog-entities.
  // Differences from upstream:
  //   - Snake_case name (Gemini requires ^[a-zA-Z0-9_]+$)
  //   - orderFields uses z.array(z.object) instead of z.union (Gemini rejects anyOf/oneOf)
  //   - filter uses z.record(z.string()) instead of predicate schema (Gemini rejects nested $all/$any/$not)
  actionsRegistry.register({
    name: "query_catalog_entities",
    title: "Query Catalog Entities",
    description: `Query entities from the Backstage Software Catalog with pagination, sorting, full-text search, and field selection.

Queryable entity fields include: kind, metadata.name, metadata.namespace, metadata.title, metadata.description, metadata.tags, metadata.annotations.*, metadata.labels.*, spec.type, spec.lifecycle, spec.owner, spec.system, spec.dependsOn, spec.providesApis, spec.consumesApis.

Relations can be queried via "relations.<type>" e.g. "relations.ownedby: user:default/jane-doe". Common relation types: ownedBy/ownerOf, dependsOn/dependencyOf, providesApi/apiProvidedBy, consumesApi/apiConsumedBy, parentOf/childOf, memberOf/hasMember, partOf/hasPart.

When querying for entity relationships, prefer using relations over spec fields. For example, use "relations.ownedby" instead of "spec.owner" to find entities owned by a particular group or user.`,
    attributes: {
      readOnly: true,
      idempotent: true,
    },
    schema: {
      input: (z) =>
        z.object({
          filter: z
            .record(z.string())
            .optional()
            .describe(
              "Key-value filter. Keys are entity field paths, values are strings to match. Example: { 'kind': 'Component', 'spec.type': 'service' }",
            ),
          fields: z
            .array(z.string())
            .optional()
            .describe(
              "Specific fields to include in the response. Each entry is a dot-separated path, e.g. 'spec.type'. If omitted, all fields are returned.",
            ),
          limit: z
            .number()
            .optional()
            .describe("Maximum number of entities to return at a time."),
          offset: z
            .number()
            .optional()
            .describe("Number of entities to skip before returning results."),
          order_by: z
            .array(
              z.object({
                field: z
                  .string()
                  .describe(
                    "Field to order by, e.g. 'metadata.name' or 'spec.type'.",
                  ),
                order: z.string().describe("Sort order: 'asc' or 'desc'."),
              }),
            )
            .optional()
            .describe("Ordering criteria for the results."),
          full_text_search: z
            .string()
            .optional()
            .describe("Full text search term to filter entities by."),
          cursor: z
            .string()
            .optional()
            .describe(
              "Cursor for pagination. Use the nextPageCursor from a previous response.",
            ),
        }),
      output: (z) =>
        z.object({
          items: z
            .array(z.record(z.unknown()))
            .describe("List of matched catalog entities"),
          total_items: z
            .number()
            .describe("Total number of entities matching the query"),
          has_more: z.boolean().describe("Whether more entities are available"),
          next_page_cursor: z
            .string()
            .optional()
            .describe("Cursor to fetch the next page of results"),
        }),
    },
    async action({ input, credentials }) {
      const { token } = await auth.getPluginRequestToken({
        onBehalfOf: credentials,
        targetPluginId: "catalog",
      });

      const response = await catalogClient.queryEntities(
        {
          filter: input.filter,
          fields: input.fields,
          limit: input.limit,
          offset: input.offset,
          orderFields: input.order_by?.map((o) => ({
            field: o.field,
            order: o.order as "asc" | "desc",
          })),
          fullTextFilter: input.full_text_search
            ? { term: input.full_text_search }
            : undefined,
          cursor: input.cursor,
        },
        { token },
      );

      return {
        output: {
          items: response.items,
          total_items: response.totalItems,
          has_more: !!response.pageInfo.nextCursor,
          next_page_cursor: response.pageInfo.nextCursor,
        },
      };
    },
  });

  // Action: get_catalog_model_description
  // Returns a human-readable description of the Backstage catalog model.
  // Rather than pulling in the full upstream describeCatalogModel() with its
  // dependency tree, we return a comprehensive static description of the
  // standard Backstage model that the MCP client (Gemini) can use as context.
  actionsRegistry.register({
    name: "get_catalog_model_description",
    title: "Get Catalog Model Description",
    description:
      "Returns a description of the Backstage catalog data model including entity kinds, fields, relations, and queryable attributes.",
    attributes: {
      readOnly: true,
      idempotent: true,
    },
    schema: {
      input: (z) => z.object({}),
      output: (z) =>
        z.object({
          description: z
            .string()
            .describe(
              "Markdown description of the catalog model including entity kinds, spec fields, and relations.",
            ),
        }),
    },
    async action() {
      return {
        output: {
          description: CATALOG_MODEL_DESCRIPTION,
        },
      };
    },
  });

  // Action: validate_entity
  // Validates entity JSON content against the catalog schema.
  actionsRegistry.register({
    name: "validate_entity",
    title: "Validate Entity",
    description:
      "Validate entity JSON content against the Backstage catalog schema. Returns whether the entity is valid and any validation errors. Provide the entity as a JSON string with apiVersion, kind, metadata, and spec fields.",
    attributes: {
      readOnly: true,
      idempotent: true,
    },
    schema: {
      input: (z) =>
        z.object({
          entity_json: z
            .string()
            .describe(
              "Entity JSON content to validate. Must include apiVersion, kind, metadata (with name), and spec.",
            ),
          location: z
            .string()
            .optional()
            .describe(
              "Optional location URL reference for the entity, e.g. https://github.com/org/repo/blob/main/catalog-info.yaml",
            ),
        }),
      output: (z) =>
        z.object({
          is_valid: z.boolean().describe("Whether the entity is valid"),
          errors: z.array(z.string()).describe("Array of validation errors"),
        }),
    },
    async action({ input, credentials }) {
      const { token } = await auth.getPluginRequestToken({
        onBehalfOf: credentials,
        targetPluginId: "catalog",
      });

      // Parse JSON
      let entity: Record<string, unknown>;
      try {
        entity = JSON.parse(input.entity_json);
      } catch (jsonError) {
        return {
          output: {
            is_valid: false,
            errors: [
              `JSON parse error: ${jsonError instanceof Error ? jsonError.message : String(jsonError)}`,
            ],
          },
        };
      }

      if (!entity || typeof entity !== "object" || Array.isArray(entity)) {
        return {
          output: {
            is_valid: false,
            errors: [
              "Parsed JSON is not a valid entity object (must be a non-null, non-array object)",
            ],
          },
        };
      }

      try {
        const result = await catalogClient.validateEntity(
          entity as Parameters<typeof catalogClient.validateEntity>[0],
          input.location ?? "url:https://localhost/entity-validator",
          { token },
        );

        if (result.valid) {
          return {
            output: {
              is_valid: true,
              errors: [],
            },
          };
        }

        return {
          output: {
            is_valid: false,
            errors: result.errors?.map(
              (e: { message?: string }) => e.message ?? String(e),
            ) ?? ["Unknown validation error"],
          },
        };
      } catch (error) {
        return {
          output: {
            is_valid: false,
            errors: [
              `Validation failed: ${error instanceof Error ? error.message : String(error)}`,
            ],
          },
        };
      }
    },
  });

  // Action: register_entity
  // Registers a new entity location in the catalog.
  actionsRegistry.register({
    name: "register_entity",
    title: "Register Entity",
    description:
      "Register a new entity in the Backstage catalog by providing a URL to its catalog-info.yaml file. This is a mutating operation.",
    attributes: {
      readOnly: false,
      idempotent: false,
    },
    schema: {
      input: (z) =>
        z.object({
          location_url: z
            .string()
            .describe(
              "URL to the catalog-info.yaml file, e.g. https://github.com/org/repo/blob/main/catalog-info.yaml",
            ),
        }),
      output: (z) =>
        z.object({
          location_id: z.string().describe("The ID of the registered location"),
          entities: z
            .array(z.record(z.unknown()))
            .describe("Entities discovered from the location"),
        }),
    },
    async action({ input, credentials }) {
      const { token } = await auth.getPluginRequestToken({
        onBehalfOf: credentials,
        targetPluginId: "catalog",
      });

      // Validate URL
      try {
        new URL(input.location_url);
      } catch {
        throw new Error(`Invalid location URL: ${input.location_url}`);
      }

      const result = await catalogClient.addLocation(
        { type: "url", target: input.location_url },
        { token },
      );

      return {
        output: {
          location_id: result.location.id,
          entities: result.entities,
        },
      };
    },
  });

  // Action: unregister_entity
  // Removes a registered entity location from the catalog.
  actionsRegistry.register({
    name: "unregister_entity",
    title: "Unregister Entity",
    description:
      "Unregister an entity location from the Backstage catalog by its location ID. This is a destructive operation that removes the location and its associated entities.",
    attributes: {
      readOnly: false,
      idempotent: true,
      destructive: true,
    },
    schema: {
      input: (z) =>
        z.object({
          location_id: z
            .string()
            .describe("The location ID of the entity to unregister"),
        }),
      output: (z) => z.object({}),
    },
    async action({ input, credentials }) {
      const { token } = await auth.getPluginRequestToken({
        onBehalfOf: credentials,
        targetPluginId: "catalog",
      });

      await catalogClient.removeLocationById(input.location_id, {
        token,
      });

      return {
        output: {},
      };
    },
  });

  // Action: who_am_i
  // Returns the authenticated user's catalog entity and identity info.
  actionsRegistry.register({
    name: "who_am_i",
    title: "Who Am I",
    description:
      "Returns the catalog entity and user info for the currently authenticated user. Use this to identify who is using the MCP tools.",
    attributes: {
      readOnly: true,
      idempotent: true,
    },
    schema: {
      input: (z) => z.object({}),
      output: (z) =>
        z.object({
          user_entity_ref: z
            .string()
            .describe("The entity ref of the user, e.g. user:default/jane.doe"),
          ownership_entity_refs: z
            .array(z.string())
            .describe(
              "Entity refs that the user claims ownership through (groups, etc.)",
            ),
          entity: z
            .record(z.unknown())
            .nullable()
            .describe(
              "The full catalog entity for the authenticated user, or null if not found",
            ),
        }),
    },
    async action({ credentials }) {
      if (!auth.isPrincipal(credentials, "user")) {
        throw new Error("This action requires user credentials");
      }

      const { userEntityRef } = credentials.principal;

      const [info, entityResult] = await Promise.all([
        userInfo.getUserInfo(credentials),
        (async () => {
          try {
            const { token } = await auth.getPluginRequestToken({
              onBehalfOf: credentials,
              targetPluginId: "catalog",
            });
            return await catalogClient.getEntityByRef(userEntityRef, {
              token,
            });
          } catch {
            return null;
          }
        })(),
      ]);

      return {
        output: {
          user_entity_ref: info.userEntityRef,
          ownership_entity_refs: info.ownershipEntityRefs,
          entity: entityResult ?? null,
        },
      };
    },
  });

  // ─── NEW IDEAL MCP ACTIONS ──────────────────────────────────────────

  // Action: refresh_catalog_entity
  actionsRegistry.register({
    name: "refresh_catalog_entity",
    title: "Refresh Catalog Entity",
    description:
      "Trigger an immediate re-fetch and re-processing of a catalog entity from its source location in git, without waiting for background refresh cycles.",
    attributes: {
      readOnly: false,
      idempotent: true,
    },
    schema: {
      input: (z) =>
        z.object({
          entity_ref: z
            .string()
            .describe(
              "Entity reference to refresh, e.g. 'component:default/mcp-slack' or 'component:devx'",
            ),
        }),
      output: (z) =>
        z.object({
          message: z.string().describe("Status message"),
          entity_ref: z.string().describe("The refreshed entity reference"),
        }),
    },
    async action({ input, credentials }) {
      const { token } = await auth.getPluginRequestToken({
        onBehalfOf: credentials,
        targetPluginId: "catalog",
      });

      await catalogClient.refreshEntity(input.entity_ref, { token });

      return {
        output: {
          message: `Refresh successfully scheduled for ${input.entity_ref}`,
          entity_ref: input.entity_ref,
        },
      };
    },
  });

  // Action: get_api_definition
  actionsRegistry.register({
    name: "get_api_definition",
    title: "Get API Definition",
    description:
      "Retrieve the full raw or parsed API specification (OpenAPI, AsyncAPI, GraphQL, gRPC) for an API entity in the catalog.",
    attributes: {
      readOnly: true,
      idempotent: true,
    },
    schema: {
      input: (z) =>
        z.object({
          name: z.string().describe("API entity name, e.g. 'order-api'"),
          namespace: z
            .string()
            .optional()
            .default("default")
            .describe("Entity namespace (default: 'default')"),
        }),
      output: (z) =>
        z.object({
          entity_ref: z.string().describe("The full API entity ref"),
          type: z
            .string()
            .describe("API definition type, e.g. 'openapi', 'graphql', 'grpc'"),
          definition: z.string().describe("Raw API definition text"),
          lifecycle: z.string().optional().describe("API lifecycle status"),
          owner: z.string().optional().describe("API owner entity ref"),
        }),
    },
    async action({ input, credentials }) {
      const { token } = await auth.getPluginRequestToken({
        onBehalfOf: credentials,
        targetPluginId: "catalog",
      });

      const namespace = input.namespace ?? "default";
      const entity = await catalogClient.getEntityByRef(
        {
          kind: "API",
          name: input.name,
          namespace,
        },
        { token },
      );

      if (!entity) {
        throw new Error(
          `API entity 'api:${namespace}/${input.name}' not found in catalog`,
        );
      }

      const spec = entity.spec as
        | {
            type?: string;
            definition?: string;
            lifecycle?: string;
            owner?: string;
          }
        | undefined;

      return {
        output: {
          entity_ref: `api:${namespace}/${input.name}`,
          type: spec?.type ?? "unknown",
          definition: spec?.definition ?? "",
          lifecycle: spec?.lifecycle,
          owner: spec?.owner,
        },
      };
    },
  });

  // Action: get_techdocs_page
  actionsRegistry.register({
    name: "get_techdocs_page",
    title: "Get TechDocs Page",
    description:
      "Retrieve the rendered documentation content (HTML/text) for a catalog entity from Backstage TechDocs.",
    attributes: {
      readOnly: true,
      idempotent: true,
    },
    schema: {
      input: (z) =>
        z.object({
          name: z.string().describe("Entity name"),
          kind: z
            .string()
            .optional()
            .default("Component")
            .describe("Entity kind (default: 'Component')"),
          namespace: z
            .string()
            .optional()
            .default("default")
            .describe("Entity namespace (default: 'default')"),
          path: z
            .string()
            .optional()
            .default("index.html")
            .describe("Relative documentation path (default: 'index.html')"),
        }),
      output: (z) =>
        z.object({
          entity_ref: z.string().describe("The entity reference"),
          path: z.string().describe("Documentation page path"),
          content: z.string().describe("Page content text/html"),
        }),
    },
    async action({ input, credentials }) {
      const { token } = await auth.getPluginRequestToken({
        onBehalfOf: credentials,
        targetPluginId: "techdocs",
      });

      const kind = (input.kind ?? "Component").toLowerCase();
      const namespace = input.namespace ?? "default";
      const name = input.name;
      const path = (input.path ?? "index.html").replace(/^\/+/, "");

      const techdocsBaseUrl = await discovery.getBaseUrl("techdocs");
      const docsUrl = `${techdocsBaseUrl}/static/docs/${namespace}/${kind}/${name}/${path}`;

      const res = await fetch(docsUrl, {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      });

      if (!res.ok) {
        if (res.status === 404) {
          throw new Error(
            `TechDocs page '${path}' not found for ${kind}:${namespace}/${name} (HTTP 404). Documentation may not have been built yet.`,
          );
        }
        throw new Error(
          `Failed to fetch TechDocs for ${kind}:${namespace}/${name}: HTTP ${res.status} ${res.statusText}`,
        );
      }

      const content = await res.text();
      return {
        output: {
          entity_ref: `${input.kind ?? "Component"}:${namespace}/${name}`,
          path,
          content,
        },
      };
    },
  });

  // Action: search_backstage
  actionsRegistry.register({
    name: "search_backstage",
    title: "Search Backstage",
    description:
      "Execute a unified full-text search query across Backstage indices (Software Catalog, TechDocs, Templates).",
    attributes: {
      readOnly: true,
      idempotent: true,
    },
    schema: {
      input: (z) =>
        z.object({
          query: z.string().describe("Search query term"),
          types: z
            .array(z.string())
            .optional()
            .describe(
              "Optional document types to filter by (e.g. ['software-catalog', 'techdocs'])",
            ),
          limit: z
            .number()
            .optional()
            .describe("Maximum number of results to return (default: 10)"),
        }),
      output: (z) =>
        z.object({
          results: z.array(
            z.object({
              title: z.string().describe("Result title"),
              text: z.string().describe("Result text / snippet"),
              location: z.string().describe("Resource link location"),
              type: z.string().describe("Document type"),
            }),
          ),
        }),
    },
    async action({ input, credentials }) {
      const { token } = await auth.getPluginRequestToken({
        onBehalfOf: credentials,
        targetPluginId: "search",
      });

      const searchBaseUrl = await discovery.getBaseUrl("search");
      const params = new URLSearchParams();
      params.set("term", input.query);
      if (input.types && input.types.length > 0) {
        for (const t of input.types) {
          params.append("types[]", t);
        }
      }
      if (input.limit) {
        params.set("pageLimit", String(input.limit));
      }

      const res = await fetch(`${searchBaseUrl}/query?${params.toString()}`, {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      });

      if (!res.ok) {
        throw new Error(`Search failed: HTTP ${res.status} ${res.statusText}`);
      }

      const data = (await res.json()) as {
        results?: Array<{
          type?: string;
          document?: {
            title?: string;
            text?: string;
            location?: string;
          };
        }>;
      };

      const results = (data.results ?? []).map((r) => ({
        title: r.document?.title ?? "",
        text: r.document?.text ?? "",
        location: r.document?.location ?? "",
        type: r.type ?? "unknown",
      }));

      return {
        output: {
          results,
        },
      };
    },
  });

  // Action: get_entity_scorecard
  actionsRegistry.register({
    name: "get_entity_scorecard",
    title: "Get Entity Scorecard",
    description:
      "Evaluate Level 3 Operational Maturity Scorecards, Golden Path checks, and governance diagnostics for a catalog entity.",
    attributes: {
      readOnly: true,
      idempotent: true,
    },
    schema: {
      input: (z) =>
        z.object({
          entity_ref: z
            .string()
            .describe(
              "Entity reference, e.g. 'component:default/mcp-slack' or 'component:devx'",
            ),
        }),
      output: (z) =>
        z.object({
          entity_ref: z.string().describe("The evaluated entity ref"),
          archetype: z.string().describe("Component archetype"),
          tier: z.string().describe("Overall achieved maturity tier"),
          percentage: z
            .number()
            .describe("Overall compliance score percentage"),
          passed_checks: z.number().describe("Number of passed checks"),
          total_checks: z.number().describe("Total number of evaluated checks"),
          tracks: z.array(
            z.object({
              id: z.string().describe("Track ID"),
              name: z.string().describe("Track name"),
              tier: z.string().describe("Track achieved tier"),
              checks: z.array(
                z.object({
                  id: z.string().describe("Check ID"),
                  title: z.string().describe("Check title"),
                  status: z.string().describe("Check status (passed, failed)"),
                  message: z.string().describe("Check diagnostic message"),
                }),
              ),
            }),
          ),
        }),
    },
    async action({ input, credentials }) {
      const { token } = await auth.getPluginRequestToken({
        onBehalfOf: credentials,
        targetPluginId: "catalog",
      });

      let parsedRef: { kind: string; namespace: string; name: string };
      try {
        parsedRef = parseEntityRef(input.entity_ref, {
          defaultKind: "Component",
          defaultNamespace: "default",
        });
      } catch {
        parsedRef = {
          kind: "Component",
          namespace: "default",
          name: input.entity_ref,
        };
      }

      const entity = await catalogClient.getEntityByRef(parsedRef, { token });
      if (!entity) {
        throw new Error(
          `Entity '${input.entity_ref}' not found in catalog for scorecard evaluation`,
        );
      }

      const repoRoot = optionsRepoRoot ?? resolve(__dirname, "../../../../..");
      let githubToken =
        optionsGithubToken ?? process.env.GITHUB_TOKEN ?? process.env.GH_TOKEN;

      if (!githubToken && config) {
        try {
          if (config.has("integrations.github")) {
            const githubConfigs = config.getOptionalConfigArray(
              "integrations.github",
            );
            githubToken = githubConfigs?.[0]?.getOptionalString("token");
          }
        } catch {
          // ignore in standalone runs
        }
      }

      const scorecard = await evaluateEntityScorecard(
        entity,
        repoRoot,
        githubToken,
      );

      const allChecks = Object.values(scorecard.tracks).flatMap(
        (t) => t.checks,
      );
      const passedChecks = allChecks.filter(
        (c) => c.status === "passed",
      ).length;
      const totalChecks = allChecks.length;

      return {
        output: {
          entity_ref: `${parsedRef.kind.toLowerCase()}:${parsedRef.namespace}/${parsedRef.name}`,
          archetype: scorecard.archetype,
          tier: scorecard.overallTier,
          percentage: scorecard.overallScore,
          passed_checks: passedChecks,
          total_checks: totalChecks,
          tracks: Object.values(scorecard.tracks).map((t) => ({
            id: t.id,
            name: t.title,
            tier: t.level,
            checks: t.checks.map((c) => ({
              id: c.id,
              title: c.title,
              status: c.status,
              message: c.message,
            })),
          })),
        },
      };
    },
  });

  // Action: execute_scaffolder_template
  actionsRegistry.register({
    name: "execute_scaffolder_template",
    title: "Execute Scaffolder Template",
    description:
      "Execute an automated Scaffolder template workflow in Backstage to stamp a new service, repository, or blueprint.",
    attributes: {
      readOnly: false,
      idempotent: false,
    },
    schema: {
      input: (z) =>
        z.object({
          template_ref: z
            .string()
            .describe(
              "Template entity reference, e.g. 'template:default/bazel-go' or 'template:default/k8s-canary-microservice'",
            ),
          values: z
            .record(z.unknown())
            .describe(
              "Input parameter values matching the template's required schema",
            ),
          secrets: z
            .record(z.string())
            .optional()
            .describe(
              "Optional secret values required by the template (e.g. USER_OAUTH_TOKEN)",
            ),
        }),
      output: (z) =>
        z.object({
          task_id: z.string().describe("The ID of the spawned scaffolder task"),
          task_url: z
            .string()
            .describe("Direct URL to view the running task in Backstage UI"),
        }),
    },
    async action({ input, credentials }) {
      const { token } = await auth.getPluginRequestToken({
        onBehalfOf: credentials,
        targetPluginId: "scaffolder",
      });

      const scaffolderBaseUrl = await discovery.getBaseUrl("scaffolder");
      const appBaseUrl =
        config?.getOptionalString("app.baseUrl") ??
        "https://backstage.vitruviansoftware.dev";

      const res = await fetch(`${scaffolderBaseUrl}/v2/tasks`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          templateRef: input.template_ref,
          values: input.values,
          secrets: input.secrets ?? {},
        }),
      });

      if (!res.ok) {
        const errorText = await res.text();
        throw new Error(
          `Failed to execute scaffolder template: HTTP ${res.status} ${res.statusText} — ${errorText}`,
        );
      }

      const data = (await res.json()) as { id: string };
      return {
        output: {
          task_id: data.id,
          task_url: `${appBaseUrl}/create/tasks/${data.id}`,
        },
      };
    },
  });

  // Action: get_scaffolder_task
  actionsRegistry.register({
    name: "get_scaffolder_task",
    title: "Get Scaffolder Task",
    description:
      "Inspect the live status, execution progress, output links, and errors of a Backstage Scaffolder task.",
    attributes: {
      readOnly: true,
      idempotent: true,
    },
    schema: {
      input: (z) =>
        z.object({
          task_id: z
            .string()
            .describe("The ID of the scaffolder task to inspect"),
        }),
      output: (z) =>
        z.object({
          task_id: z.string().describe("Scaffolder task ID"),
          status: z
            .string()
            .describe(
              "Current task status (open, processing, completed, failed, cancelled)",
            ),
          created_at: z
            .string()
            .optional()
            .describe("Task creation ISO timestamp"),
          created_by: z
            .string()
            .optional()
            .describe("User ref who triggered the task"),
          output_links: z
            .array(
              z.object({
                title: z.string().describe("Link title"),
                url: z
                  .string()
                  .describe("Link URL (e.g. created PR or repository)"),
              }),
            )
            .optional()
            .describe("Links generated by template execution"),
          error: z
            .string()
            .optional()
            .describe("Failure reason if task failed"),
        }),
    },
    async action({ input, credentials }) {
      const { token } = await auth.getPluginRequestToken({
        onBehalfOf: credentials,
        targetPluginId: "scaffolder",
      });

      const scaffolderBaseUrl = await discovery.getBaseUrl("scaffolder");
      const res = await fetch(
        `${scaffolderBaseUrl}/v2/tasks/${input.task_id}`,
        {
          headers: {
            Authorization: `Bearer ${token}`,
          },
        },
      );

      if (!res.ok) {
        throw new Error(
          `Failed to fetch scaffolder task '${input.task_id}': HTTP ${res.status} ${res.statusText}`,
        );
      }

      const task = (await res.json()) as {
        id: string;
        status: string;
        createdAt?: string;
        createdBy?: string;
        output?: {
          links?: Array<{ title?: string; url?: string }>;
        };
        error?: {
          message?: string;
        };
      };

      const outputLinks = (task.output?.links ?? []).map((l) => ({
        title: l.title ?? "Link",
        url: l.url ?? "",
      }));

      return {
        output: {
          task_id: task.id,
          status: task.status,
          created_at: task.createdAt,
          created_by: task.createdBy,
          output_links: outputLinks,
          error: task.error?.message,
        },
      };
    },
  });
}

/**
 * Static catalog model description matching the standard Backstage model.
 * Returned by the get_catalog_model_description action.
 */
const CATALOG_MODEL_DESCRIPTION = `# Backstage Catalog Model

## Entity Reference Format
Entities are referenced as \`kind:namespace/name\`, e.g. \`component:default/my-service\`.
The namespace defaults to "default" and can be omitted: \`component:my-service\`.

## Common Metadata Fields
All entities share these metadata fields:
- \`metadata.name\` — unique name within kind+namespace (required)
- \`metadata.namespace\` — grouping namespace, default is "default"
- \`metadata.title\` — human-readable display name
- \`metadata.description\` — human-readable description
- \`metadata.tags\` — string array for classification (e.g. ["java", "production"])
- \`metadata.labels\` — key-value pairs for filtering
- \`metadata.annotations\` — key-value metadata (e.g. "github.com/project-slug")
- \`metadata.links\` — external links with url, title, and optional icon

## Entity Kinds

### Component
A piece of software (service, website, library, etc.).
- \`spec.type\` — "service", "website", "library", etc.
- \`spec.lifecycle\` — "experimental", "production", "deprecated"
- \`spec.owner\` — entity reference to the owner (group or user)
- \`spec.system\` — entity reference to the system it belongs to
- \`spec.subcomponentOf\` — parent component reference
- \`spec.providesApis\` — APIs this component provides
- \`spec.consumesApis\` — APIs this component consumes
- \`spec.dependsOn\` — resources or components this depends on

### API
An API definition (OpenAPI, AsyncAPI, GraphQL, gRPC).
- \`spec.type\` — "openapi", "asyncapi", "graphql", "grpc"
- \`spec.lifecycle\` — "experimental", "production", "deprecated"
- \`spec.owner\` — owner entity reference
- \`spec.system\` — system entity reference
- \`spec.definition\` — the API definition content

### System
A collection of components and APIs that form a logical unit.
- \`spec.owner\` — owner entity reference
- \`spec.domain\` — domain entity reference

### Domain
A grouping of systems that share business purpose.
- \`spec.owner\` — owner entity reference

### Resource
Infrastructure a component depends on (database, S3 bucket, etc.).
- \`spec.type\` — "database", "s3-bucket", etc.
- \`spec.owner\` — owner entity reference
- \`spec.system\` — system entity reference
- \`spec.dependsOn\` — other resources this depends on
- \`spec.dependencyOf\` — components that depend on this

### Group
An organizational unit (team, department, etc.).
- \`spec.type\` — "team", "business-unit", "product-area"
- \`spec.profile\` — displayName, email, picture
- \`spec.parent\` — parent group entity reference
- \`spec.children\` — child group entity references
- \`spec.members\` — user entity references

### User
A person (employee, contractor, etc.).
- \`spec.profile\` — displayName, email, picture
- \`spec.memberOf\` — group entity references

### Location
A reference to other entity definition files.
- \`spec.type\` — "url", "file"
- \`spec.target\` — single target location
- \`spec.targets\` — multiple target locations

### Template
A scaffolder template for creating new components.
- \`spec.type\` — "service", "website", "library", etc.
- \`spec.owner\` — owner entity reference
- \`spec.parameters\` — template input parameters
- \`spec.steps\` — template execution steps
- \`spec.output\` — output of the template

## Entity Relations
Relations are stored in the "relations" array. Common relation types:
- \`ownedBy\` / \`ownerOf\` — ownership
- \`dependsOn\` / \`dependencyOf\` — dependencies
- \`providesApi\` / \`apiProvidedBy\` — API provision
- \`consumesApi\` / \`apiConsumedBy\` — API consumption
- \`parentOf\` / \`childOf\` — hierarchy
- \`memberOf\` / \`hasMember\` — group membership
- \`partOf\` / \`hasPart\` — system/domain membership

Relations can be queried via "relations.<type>" e.g. "relations.ownedby: user:default/jane-doe".
The value must be a valid entity reference.
When querying for entity relationships, prefer using relations over spec fields.`;

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
        userInfo: coreServices.userInfo,
        logger: coreServices.logger,
        config: coreServices.rootConfig,
      },
      async init({
        actionsRegistry,
        discovery,
        auth,
        userInfo,
        logger,
        config,
      }) {
        await registerCatalogMcpActions({
          actionsRegistry,
          discovery,
          auth,
          userInfo,
          logger,
          config,
        });
      },
    });
  },
});
