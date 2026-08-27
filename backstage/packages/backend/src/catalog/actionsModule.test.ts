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
  it("registers all catalog MCP actions with the ActionsRegistry", async () => {
    const registeredActions: Map<string, any> = new Map();

    const mockActionsRegistry: any = {
      register: jest.fn((options) => {
        registeredActions.set(options.name, options);
      }),
    };

    const mockDiscovery: any = {
      getBaseUrl: jest.fn().mockResolvedValue("http://catalog.local"),
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

    await registerCatalogMcpActions({
      actionsRegistry: mockActionsRegistry,
      discovery: mockDiscovery,
      auth: mockAuth,
      userInfo: mockUserInfo,
      logger: mockLogger,
    });

    // Should register 9 actions total
    expect(mockActionsRegistry.register).toHaveBeenCalledTimes(9);

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

    // Verify all action names are Gemini-compatible (snake_case, no hyphens/dots)
    for (const [name] of registeredActions) {
      expect(name).toMatch(/^[a-zA-Z0-9_]+$/);
    }
  });
});
