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

import { registerCatalogMcpActions } from "./actionsModule";

describe("registerCatalogMcpActions", () => {
  it("registers all 16 catalog, techdocs, search, scaffolder, and scorecards MCP actions", async () => {
    const registeredActions: Map<string, any> = new Map();

    const mockActionsRegistry: any = {
      register: jest.fn((options) => {
        registeredActions.set(options.name, options);
      }),
    };

    const mockDiscovery: any = {
      getBaseUrl: jest.fn().mockImplementation((pluginId: string) => {
        return Promise.resolve(`http://${pluginId}.local`);
      }),
      getExternalBaseUrl: jest.fn().mockResolvedValue("http://catalog.local"),
    };

    const mockAuth: any = {
      getPluginRequestToken: jest
        .fn()
        .mockResolvedValue({ token: "mock_token" }),
      isPrincipal: jest.fn().mockReturnValue(true),
    };

    const mockUserInfo: any = {
      getUserInfo: jest.fn().mockResolvedValue({
        userEntityRef: "user:default/test-user",
        ownershipEntityRefs: ["user:default/test-user", "group:default/team-a"],
      }),
    };

    const mockLogger: any = {
      info: jest.fn(),
      warn: jest.fn(),
      error: jest.fn(),
      debug: jest.fn(),
      child: jest.fn().mockReturnThis(),
    };

    const mockConfig: any = {
      has: jest.fn().mockReturnValue(false),
      getOptionalString: jest
        .fn()
        .mockReturnValue("https://backstage.vitruviansoftware.dev"),
      getOptionalConfigArray: jest.fn().mockReturnValue([]),
    };

    await registerCatalogMcpActions({
      actionsRegistry: mockActionsRegistry,
      discovery: mockDiscovery,
      auth: mockAuth,
      userInfo: mockUserInfo,
      logger: mockLogger,
      config: mockConfig,
    });

    // Should register 16 actions total
    expect(mockActionsRegistry.register).toHaveBeenCalledTimes(16);

    // 1. get_entities — list/filter entities
    const getEntitiesAction = registeredActions.get("get_entities");
    expect(getEntitiesAction).toBeDefined();
    expect(getEntitiesAction.title).toBe("Get Catalog Entities");
    expect(getEntitiesAction.attributes?.readOnly).toBe(true);
    expect(getEntitiesAction.attributes?.idempotent).toBe(true);

    // 2. get_entity_by_name — single entity lookup
    const getEntityByNameAction = registeredActions.get("get_entity_by_name");
    expect(getEntityByNameAction).toBeDefined();
    expect(getEntityByNameAction.title).toBe("Get Catalog Entity By Name");
    expect(getEntityByNameAction.attributes?.readOnly).toBe(true);
    expect(getEntityByNameAction.attributes?.idempotent).toBe(true);

    // 3. get_entity_facets — facet counts
    const getEntityFacetsAction = registeredActions.get("get_entity_facets");
    expect(getEntityFacetsAction).toBeDefined();
    expect(getEntityFacetsAction.title).toBe("Get Catalog Entity Facets");
    expect(getEntityFacetsAction.attributes?.readOnly).toBe(true);
    expect(getEntityFacetsAction.attributes?.idempotent).toBe(true);

    // 4. query_catalog_entities — advanced query with pagination/sorting
    const queryAction = registeredActions.get("query_catalog_entities");
    expect(queryAction).toBeDefined();
    expect(queryAction.title).toBe("Query Catalog Entities");
    expect(queryAction.attributes?.readOnly).toBe(true);
    expect(queryAction.attributes?.idempotent).toBe(true);

    // 5. get_catalog_model_description — catalog model reference
    const modelAction = registeredActions.get("get_catalog_model_description");
    expect(modelAction).toBeDefined();
    expect(modelAction.title).toBe("Get Catalog Model Description");
    expect(modelAction.attributes?.readOnly).toBe(true);

    // 6. validate_entity — validate entity YAML
    const validateAction = registeredActions.get("validate_entity");
    expect(validateAction).toBeDefined();
    expect(validateAction.title).toBe("Validate Entity");
    expect(validateAction.attributes?.readOnly).toBe(true);

    // 7. register_entity — register entity location (mutating)
    const registerAction = registeredActions.get("register_entity");
    expect(registerAction).toBeDefined();
    expect(registerAction.title).toBe("Register Entity");
    expect(registerAction.attributes?.readOnly).toBe(false);
    expect(registerAction.attributes?.idempotent).toBe(false);

    // 8. unregister_entity — remove entity location (destructive)
    const unregisterAction = registeredActions.get("unregister_entity");
    expect(unregisterAction).toBeDefined();
    expect(unregisterAction.title).toBe("Unregister Entity");
    expect(unregisterAction.attributes?.readOnly).toBe(false);
    expect(unregisterAction.attributes?.destructive).toBe(true);

    // 9. who_am_i — authenticated user identity
    const whoAmIAction = registeredActions.get("who_am_i");
    expect(whoAmIAction).toBeDefined();
    expect(whoAmIAction.title).toBe("Who Am I");
    expect(whoAmIAction.attributes?.readOnly).toBe(true);

    // 10. refresh_catalog_entity — instant re-sync
    const refreshAction = registeredActions.get("refresh_catalog_entity");
    expect(refreshAction).toBeDefined();
    expect(refreshAction.title).toBe("Refresh Catalog Entity");
    expect(refreshAction.attributes?.readOnly).toBe(false);
    expect(refreshAction.attributes?.idempotent).toBe(true);

    // 11. get_api_definition — raw API spec definition
    const apiDefAction = registeredActions.get("get_api_definition");
    expect(apiDefAction).toBeDefined();
    expect(apiDefAction.title).toBe("Get API Definition");
    expect(apiDefAction.attributes?.readOnly).toBe(true);
    expect(apiDefAction.attributes?.idempotent).toBe(true);

    // 12. get_techdocs_page — documentation content reader
    const techdocsAction = registeredActions.get("get_techdocs_page");
    expect(techdocsAction).toBeDefined();
    expect(techdocsAction.title).toBe("Get TechDocs Page");
    expect(techdocsAction.attributes?.readOnly).toBe(true);
    expect(techdocsAction.attributes?.idempotent).toBe(true);

    // 13. search_backstage — unified search across indices
    const searchAction = registeredActions.get("search_backstage");
    expect(searchAction).toBeDefined();
    expect(searchAction.title).toBe("Search Backstage");
    expect(searchAction.attributes?.readOnly).toBe(true);
    expect(searchAction.attributes?.idempotent).toBe(true);

    // 14. get_entity_scorecard — Level 3 Operational Maturity Scorecards
    const scorecardAction = registeredActions.get("get_entity_scorecard");
    expect(scorecardAction).toBeDefined();
    expect(scorecardAction.title).toBe("Get Entity Scorecard");
    expect(scorecardAction.attributes?.readOnly).toBe(true);
    expect(scorecardAction.attributes?.idempotent).toBe(true);

    // 15. execute_scaffolder_template — template execution
    const execTemplateAction = registeredActions.get(
      "execute_scaffolder_template",
    );
    expect(execTemplateAction).toBeDefined();
    expect(execTemplateAction.title).toBe("Execute Scaffolder Template");
    expect(execTemplateAction.attributes?.readOnly).toBe(false);
    expect(execTemplateAction.attributes?.idempotent).toBe(false);

    // 16. get_scaffolder_task — task status and output links
    const getTaskAction = registeredActions.get("get_scaffolder_task");
    expect(getTaskAction).toBeDefined();
    expect(getTaskAction.title).toBe("Get Scaffolder Task");
    expect(getTaskAction.attributes?.readOnly).toBe(true);
    expect(getTaskAction.attributes?.idempotent).toBe(true);

    // Verify all action names are Gemini-compatible (snake_case, no hyphens/dots)
    for (const [name] of registeredActions) {
      expect(name).toMatch(/^[a-zA-Z0-9_]+$/);
    }
  });

  describe("action handlers", () => {
    let registeredActions: Map<string, any>;
    let mockActionsRegistry: any;
    let mockDiscovery: any;
    let mockAuth: any;
    let mockUserInfo: any;
    let mockLogger: any;
    let mockConfig: any;
    let mockCatalogClient: any;

    beforeEach(async () => {
      registeredActions = new Map();
      mockActionsRegistry = {
        register: jest.fn((options) => {
          registeredActions.set(options.name, options);
        }),
      };
      mockDiscovery = {
        getBaseUrl: jest.fn().mockImplementation((pluginId: string) => {
          return Promise.resolve(`http://${pluginId}.local`);
        }),
        getExternalBaseUrl: jest.fn().mockResolvedValue("http://catalog.local"),
      };
      mockAuth = {
        getPluginRequestToken: jest
          .fn()
          .mockResolvedValue({ token: "mock_token" }),
        isPrincipal: jest.fn().mockReturnValue(true),
      };
      mockUserInfo = {
        getUserInfo: jest.fn().mockResolvedValue({
          userEntityRef: "user:default/test-user",
          ownershipEntityRefs: ["user:default/test-user"],
        }),
      };
      mockLogger = {
        info: jest.fn(),
        warn: jest.fn(),
        error: jest.fn(),
        debug: jest.fn(),
        child: jest.fn().mockReturnThis(),
      };
      mockConfig = {
        has: jest.fn().mockReturnValue(false),
        getOptionalString: jest
          .fn()
          .mockReturnValue("https://backstage.vitruviansoftware.dev"),
        getOptionalConfigArray: jest.fn().mockReturnValue([]),
      };
      mockCatalogClient = {
        refreshEntity: jest.fn().mockResolvedValue(undefined),
        getEntityByRef: jest.fn().mockImplementation(async (ref) => {
          const kind = typeof ref === "string" ? "Component" : ref.kind;
          const name = typeof ref === "string" ? ref : ref.name;
          const namespace =
            typeof ref === "string" ? "default" : (ref.namespace ?? "default");

          if (kind === "API") {
            return {
              apiVersion: "backstage.io/v1alpha1",
              kind: "API",
              metadata: { name, namespace },
              spec: {
                type: "openapi",
                lifecycle: "production",
                owner: "group:default/platform-team",
                definition:
                  "openapi: 3.0.0\ninfo:\n  title: Petstore\n  version: 1.0.0\n",
              },
            };
          }
          return {
            apiVersion: "backstage.io/v1alpha1",
            kind: "Component",
            metadata: {
              name,
              namespace,
              annotations: {
                "github.com/project-slug": "VitruvianSoftware/vitruvian-core",
                "argocd/app-name": "mcp-slack",
              },
            },
            spec: {
              type: "service",
              lifecycle: "production",
              owner: "group:default/platform-team",
            },
          };
        }),
      };

      await registerCatalogMcpActions({
        actionsRegistry: mockActionsRegistry,
        discovery: mockDiscovery,
        auth: mockAuth,
        userInfo: mockUserInfo,
        logger: mockLogger,
        config: mockConfig,
        catalogClient: mockCatalogClient,
      });
    });

    it("executes refresh_catalog_entity action successfully", async () => {
      const originalFetch = global.fetch;
      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        status: 200,
        text: async () => "",
      }) as any;

      try {
        const refreshAction = registeredActions.get("refresh_catalog_entity");
        const result = await refreshAction.action({
          input: { entity_ref: "component:default/mcp-slack" },
          credentials: {
            $$type: "@backstage/BackstageCredentials",
            principal: { type: "user", userEntityRef: "user:default/ipv1337" },
          },
        });

        expect(result.output).toEqual({
          message:
            "Refresh successfully scheduled for component:default/mcp-slack",
          entity_ref: "component:default/mcp-slack",
        });
      } finally {
        global.fetch = originalFetch;
      }
    });

    it("executes search_backstage with mocked fetch", async () => {
      const originalFetch = global.fetch;
      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          results: [
            {
              type: "software-catalog",
              document: {
                title: "mcp-slack",
                text: "MCP server exposing Slack tools",
                location: "/catalog/default/component/mcp-slack",
              },
            },
          ],
        }),
      }) as any;

      try {
        const searchAction = registeredActions.get("search_backstage");
        const result = await searchAction.action({
          input: { query: "slack", types: ["software-catalog"], limit: 5 },
          credentials: {
            $$type: "@backstage/BackstageCredentials",
            principal: { type: "user", userEntityRef: "user:default/ipv1337" },
          },
        });

        expect(result.output.results).toHaveLength(1);
        expect(result.output.results[0].title).toBe("mcp-slack");
      } finally {
        global.fetch = originalFetch;
      }
    });

    it("executes get_techdocs_page with mocked fetch", async () => {
      const originalFetch = global.fetch;
      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        text: async () =>
          "<h1>Documentation</h1><p>Welcome to mcp-slack docs</p>",
      }) as any;

      try {
        const techdocsAction = registeredActions.get("get_techdocs_page");
        const result = await techdocsAction.action({
          input: { name: "mcp-slack", path: "index.html" },
          credentials: {
            $$type: "@backstage/BackstageCredentials",
            principal: { type: "user", userEntityRef: "user:default/ipv1337" },
          },
        });

        expect(result.output).toEqual({
          entity_ref: "Component:default/mcp-slack",
          path: "index.html",
          content: "<h1>Documentation</h1><p>Welcome to mcp-slack docs</p>",
        });
      } finally {
        global.fetch = originalFetch;
      }
    });

    it("executes execute_scaffolder_template and get_scaffolder_task with mocked fetch", async () => {
      const originalFetch = global.fetch;
      global.fetch = jest
        .fn()
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({ id: "task-12345" }),
        })
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({
            id: "task-12345",
            status: "completed",
            createdAt: "2026-08-27T19:00:00Z",
            output: {
              links: [
                {
                  title: "Repository",
                  url: "https://github.com/VitruvianSoftware/new-service",
                },
              ],
            },
          }),
        }) as any;

      try {
        const execAction = registeredActions.get("execute_scaffolder_template");
        const execResult = await execAction.action({
          input: {
            template_ref: "template:default/bazel-go",
            values: { name: "new-service" },
          },
          credentials: {
            $$type: "@backstage/BackstageCredentials",
            principal: { type: "user", userEntityRef: "user:default/ipv1337" },
          },
        });

        expect(execResult.output.task_id).toBe("task-12345");
        expect(execResult.output.task_url).toContain(
          "/create/tasks/task-12345",
        );

        const getTaskAction = registeredActions.get("get_scaffolder_task");
        const taskResult = await getTaskAction.action({
          input: { task_id: "task-12345" },
          credentials: {
            $$type: "@backstage/BackstageCredentials",
            principal: { type: "user", userEntityRef: "user:default/ipv1337" },
          },
        });

        expect(taskResult.output.status).toBe("completed");
        expect(taskResult.output.output_links).toHaveLength(1);
        expect(taskResult.output.output_links[0].url).toBe(
          "https://github.com/VitruvianSoftware/new-service",
        );
      } finally {
        global.fetch = originalFetch;
      }
    });

    it("executes get_api_definition with mocked catalog fetch", async () => {
      const originalFetch = global.fetch;
      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          apiVersion: "backstage.io/v1alpha1",
          kind: "API",
          metadata: { name: "petstore-api", namespace: "default" },
          spec: {
            type: "openapi",
            lifecycle: "production",
            owner: "group:default/platform-team",
            definition:
              "openapi: 3.0.0\ninfo:\n  title: Petstore\n  version: 1.0.0\n",
          },
        }),
      }) as any;

      try {
        const apiAction = registeredActions.get("get_api_definition");
        const result = await apiAction.action({
          input: { name: "petstore-api", namespace: "default" },
          credentials: {
            $$type: "@backstage/BackstageCredentials",
            principal: { type: "user", userEntityRef: "user:default/ipv1337" },
          },
        });

        expect(result.output.entity_ref).toBe("api:default/petstore-api");
        expect(result.output.type).toBe("openapi");
        expect(result.output.definition).toContain("openapi: 3.0.0");
      } finally {
        global.fetch = originalFetch;
      }
    });

    it("executes get_entity_scorecard with mocked catalog fetch", async () => {
      const originalFetch = global.fetch;
      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          apiVersion: "backstage.io/v1alpha1",
          kind: "Component",
          metadata: {
            name: "mcp-slack",
            namespace: "default",
            annotations: {
              "github.com/project-slug": "VitruvianSoftware/vitruvian-core",
              "argocd/app-name": "mcp-slack",
            },
          },
          spec: {
            type: "service",
            lifecycle: "production",
            owner: "group:default/platform-team",
          },
        }),
      }) as any;

      try {
        const scorecardAction = registeredActions.get("get_entity_scorecard");
        const result = await scorecardAction.action({
          input: { entity_ref: "component:default/mcp-slack" },
          credentials: {
            $$type: "@backstage/BackstageCredentials",
            principal: { type: "user", userEntityRef: "user:default/ipv1337" },
          },
        });

        expect(result.output.entity_ref).toBe("component:default/mcp-slack");
        expect(result.output.archetype).toBe("service");
        expect(result.output.tracks).toBeDefined();
        expect(result.output.tracks.length).toBeGreaterThan(0);
      } finally {
        global.fetch = originalFetch;
      }
    });
  });
});
