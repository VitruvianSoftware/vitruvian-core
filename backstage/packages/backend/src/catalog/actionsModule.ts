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
  UserInfoService,
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
}: {
  actionsRegistry: ActionsRegistryService;
  discovery: DiscoveryService;
  auth: AuthService;
  userInfo: UserInfoService;
  logger: LoggerService;
}) {
  const catalogClient = new CatalogClient({ discoveryApi: discovery });

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
          items: z.array(z.any()).describe("List of matched catalog entities"),
          total_items: z
            .number()
            .describe("Total number of entities matching the query"),
          has_more: z
            .boolean()
            .describe("Whether more entities are available"),
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

      if (
        !entity ||
        typeof entity !== "object" ||
        Array.isArray(entity)
      ) {
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
          input.location ??
            "url:https://localhost/entity-validator",
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
          location_id: z
            .string()
            .describe("The ID of the registered location"),
          entities: z
            .array(z.any())
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
        throw new Error(
          `Invalid location URL: ${input.location_url}`,
        );
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
            .describe(
              "The entity ref of the user, e.g. user:default/jane.doe",
            ),
          ownership_entity_refs: z
            .array(z.string())
            .describe(
              "Entity refs that the user claims ownership through (groups, etc.)",
            ),
          entity: z
            .any()
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
      },
      async init({ actionsRegistry, discovery, auth, userInfo, logger }) {
        await registerCatalogMcpActions({
          actionsRegistry,
          discovery,
          auth,
          userInfo,
          logger,
        });
      },
    });
  },
});
