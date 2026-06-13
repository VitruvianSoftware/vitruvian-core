/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/* eslint-disable @typescript-eslint/no-explicit-any */
import { z } from "zod";
import { errorHandler, isSchemaDriftError } from "../../src/lib/errorHandler";

/** Minimal Fastify reply double that records the status + body. */
function makeReply() {
  const reply: any = {
    statusCode: undefined as number | undefined,
    body: undefined as unknown,
    code(c: number) {
      this.statusCode = c;
      return this;
    },
    send(b: unknown) {
      this.body = b;
      return this;
    },
  };
  return reply;
}

const request: any = { log: { error: jest.fn() } };

/** Shape of a Prisma "column does not exist" error (P2022). */
const prismaP2022 = () => ({
  name: "PrismaClientKnownRequestError",
  code: "P2022",
  message:
    "Invalid `prisma.backup.findMany()` invocation ... The column `(not available)` does not exist in the current database.",
});

describe("isSchemaDriftError", () => {
  it("matches Prisma P2022 (missing column) and P2021 (missing table)", () => {
    expect(isSchemaDriftError(prismaP2022())).toBe(true);
    expect(
      isSchemaDriftError({
        name: "PrismaClientKnownRequestError",
        code: "P2021",
      }),
    ).toBe(true);
  });

  it("does not match unrelated Prisma errors or plain errors", () => {
    expect(
      isSchemaDriftError({
        name: "PrismaClientKnownRequestError",
        code: "P2002",
      }),
    ).toBe(false);
    expect(isSchemaDriftError(new Error("boom"))).toBe(false);
    expect(isSchemaDriftError(null)).toBe(false);
    expect(isSchemaDriftError("nope")).toBe(false);
  });
});

describe("errorHandler", () => {
  beforeEach(() => jest.clearAllMocks());

  it("maps Zod validation errors to 400 with details", () => {
    const reply = makeReply();
    const zodErr = z.object({ name: z.string() }).safeParse({});
    // safeParse failure carries a ZodError instance.
    errorHandler((zodErr as any).error, request, reply);
    expect(reply.statusCode).toBe(400);
    expect(reply.body).toMatchObject({ error: "Bad Request" });
  });

  it("maps body-too-large to 413", () => {
    const reply = makeReply();
    errorHandler({ code: "FST_ERR_CTP_BODY_TOO_LARGE" } as any, request, reply);
    expect(reply.statusCode).toBe(413);
  });

  it("maps schema drift to a clean 503 and never leaks the raw Prisma message", () => {
    const reply = makeReply();
    errorHandler(prismaP2022() as any, request, reply);
    expect(reply.statusCode).toBe(503);
    expect(reply.body).toEqual({
      error: "Service Unavailable",
      message:
        "The service is temporarily unavailable. Please try again shortly.",
    });
    expect(JSON.stringify(reply.body)).not.toContain("does not exist");
    expect(JSON.stringify(reply.body)).not.toContain("prisma");
  });

  it("preserves intentional 4xx status and message", () => {
    const reply = makeReply();
    errorHandler(
      {
        statusCode: 404,
        name: "NotFoundError",
        message: "Workspace not found",
      } as any,
      request,
      reply,
    );
    expect(reply.statusCode).toBe(404);
    expect(reply.body).toMatchObject({ message: "Workspace not found" });
  });

  it("masks raw 5xx detail in production but exposes it elsewhere", () => {
    const prev = process.env.NODE_ENV;
    try {
      process.env.NODE_ENV = "production";
      const prodReply = makeReply();
      errorHandler(new Error("pg: relation broke") as any, request, prodReply);
      expect(prodReply.statusCode).toBe(500);
      expect(prodReply.body).toMatchObject({
        error: "Internal Server Error",
        message: "An unexpected error occurred",
      });

      process.env.NODE_ENV = "development";
      const devReply = makeReply();
      errorHandler(new Error("pg: relation broke") as any, request, devReply);
      expect(devReply.statusCode).toBe(500);
      expect(devReply.body).toMatchObject({ message: "pg: relation broke" });
    } finally {
      process.env.NODE_ENV = prev;
    }
  });
});
