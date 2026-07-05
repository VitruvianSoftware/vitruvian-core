/**
 * Copyright 2026 Vitruvian Software
 *
 * Shared test utilities for Pulumi TS foundation unit tests.
 * Sets up Pulumi mocking before each test suite.
 */

import * as pulumi from "@pulumi/pulumi";

/**
 * Sets up Pulumi mocks for unit testing. Must be called before
 * importing any Pulumi component modules.
 */
export function setupPulumiMocks(): void {
    pulumi.runtime.setMocks({
        newResource: (args: pulumi.runtime.MockResourceArgs): {
            id: string;
            state: Record<string, any>;
        } => {
            // Return the inputs as outputs with a mock ID
            const state: Record<string, any> = {
                ...args.inputs,
            };

            // Simulate computed outputs for common GCP resource types
            switch (args.type) {
                case "gcp:organizations/project:Project":
                    state["projectId"] = args.inputs["projectId"] || "mock-project-id";
                    state["number"] = "123456789";
                    break;
                case "random:index/randomString:RandomString":
                    state["result"] = "abcd";
                    break;
                case "random:index/randomId:RandomId":
                    state["hex"] = "a1b2";
                    break;
                case "gcp:organizations/folder:Folder":
                    state["name"] = args.inputs["displayName"] || "mock-folder";
                    break;
            }

            return {
                id: `${args.name}-id`,
                state,
            };
        },
        call: (_args: pulumi.runtime.MockCallArgs): Record<string, any> => {
            return {};
        },
    });
}
