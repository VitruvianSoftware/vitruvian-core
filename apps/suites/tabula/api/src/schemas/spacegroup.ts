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
 * SpaceGroup validation schemas using Zod
 */
import { z } from "zod";

export const SpaceGroupCreateSchema = z.object({
  title: z.string().min(1).max(255),
  collapsed: z.boolean().default(false),
  position: z.number().int().min(0).default(0),
  color: z
    .string()
    .regex(/^#[0-9A-Fa-f]{6}$/)
    .optional()
    .nullable(),
});

export const SpaceGroupUpdateSchema = z.object({
  title: z.string().min(1).max(255).optional(),
  collapsed: z.boolean().optional(),
  position: z.number().int().min(0).optional(),
  color: z
    .string()
    .regex(/^#[0-9A-Fa-f]{6}$/)
    .optional()
    .nullable(),
  // Optimistic concurrency: version the client based this update on.
  // Absent -> legacy client, update is accepted unconditionally.
  baseVersion: z.number().int().min(0).optional(),
});

export type SpaceGroupCreateInput = z.infer<typeof SpaceGroupCreateSchema>;
export type SpaceGroupUpdateInput = z.infer<typeof SpaceGroupUpdateSchema>;
