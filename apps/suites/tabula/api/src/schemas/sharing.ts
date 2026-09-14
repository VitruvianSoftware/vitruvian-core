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

/**
 * Sharing validation schemas (#139). Roles are a Zod union over lowercase
 * strings — the repo has no Prisma enums, so the DB column is VarChar(20) and
 * this is the single source of truth for the allowed values.
 */
import { z } from "zod";

/** A grantable role (never "owner" — ownership is implicit via Workspace.userId). */
export const GrantRoleSchema = z.enum(["view", "edit"]);

/** Share a space with a person by email. */
export const CollaboratorCreateSchema = z.object({
  email: z.string().email().max(255),
  role: GrantRoleSchema.default("view"),
});

/** Change an existing collaborator's role. */
export const CollaboratorUpdateSchema = z.object({
  role: GrantRoleSchema,
});

/** Mint a new share link. */
export const ShareLinkCreateSchema = z.object({
  role: GrantRoleSchema.default("view"),
  label: z.string().max(255).optional(),
  expiresAt: z.string().datetime().optional(),
});

/**
 * A share-link token carried in the request BODY (never the URL): tokens are
 * bearer secrets and a URL token leaks into access/proxy logs and Referer.
 */
export const ShareTokenSchema = z.object({
  token: z.string().min(1).max(128),
});

export type CollaboratorCreateInput = z.infer<typeof CollaboratorCreateSchema>;
export type CollaboratorUpdateInput = z.infer<typeof CollaboratorUpdateSchema>;
export type ShareLinkCreateInput = z.infer<typeof ShareLinkCreateSchema>;
export type ShareTokenInput = z.infer<typeof ShareTokenSchema>;
