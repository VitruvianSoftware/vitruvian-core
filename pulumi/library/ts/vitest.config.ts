import { defineConfig } from "vitest/config";

export default defineConfig({
    test: {
        globals: true,
        environment: "node",
        include: ["packages/**/*.test.ts"],
        coverage: {
            provider: "v8",
            include: ["packages/**/*.ts"],
            exclude: ["packages/**/index.ts", "packages/**/*.test.ts"],
        },
    },
});
