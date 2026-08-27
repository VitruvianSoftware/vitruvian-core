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
  it("registers catalog MCP actions with the ActionsRegistry", async () => {
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
      logger: mockLogger,
    });

    expect(mockActionsRegistry.register).toHaveBeenCalledTimes(3);

    // 1. Check get_entities action
    const getEntitiesAction = registeredActions.get("get_entities");
    expect(getEntitiesAction).toBeDefined();
    expect(getEntitiesAction.title).toBe("Get Catalog Entities");
    expect(getEntitiesAction.attributes?.readOnly).toBe(true);
    expect(getEntitiesAction.attributes?.idempotent).toBe(true);

    // 2. Check get_entity_by_name action
    const getEntityByNameAction = registeredActions.get("get_entity_by_name");
    expect(getEntityByNameAction).toBeDefined();
    expect(getEntityByNameAction.title).toBe("Get Catalog Entity By Name");
    expect(getEntityByNameAction.attributes?.readOnly).toBe(true);
    expect(getEntityByNameAction.attributes?.idempotent).toBe(true);

    // 3. Check get_entity_facets action
    const getEntityFacetsAction = registeredActions.get("get_entity_facets");
    expect(getEntityFacetsAction).toBeDefined();
    expect(getEntityFacetsAction.title).toBe("Get Catalog Entity Facets");
    expect(getEntityFacetsAction.attributes?.readOnly).toBe(true);
    expect(getEntityFacetsAction.attributes?.idempotent).toBe(true);
  });
});
