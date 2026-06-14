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
 * Workspace validation schemas using Zod
 */
import { z } from "zod";

/**
 * Tabs arrive in the extension's wire shape ({ favIconUrl, pinned, index }) —
 * Chrome's own field names — while the database uses { faviconUrl, isPinned,
 * position }. Zod strips unknown keys, so WITHOUT this mapping favicons, pin
 * state, and tab order would be silently discarded on every save.
 */
export const TabSchema = z.preprocess(
  (value) => {
    if (typeof value !== "object" || value === null) return value;
    const tab = value as Record<string, unknown>;
    return {
      ...tab,
      faviconUrl: tab.faviconUrl ?? tab.favIconUrl,
      isPinned: tab.isPinned ?? tab.pinned,
      position: tab.position ?? tab.index,
    };
  },
  z.object({
    // Tab id is non-identifying INPUT: the service always regenerates tab ids
    // server-side (see buildTabRows) and only reads this to stash the original
    // in metadata.clientTabId. It must tolerate everything a client legitimately
    // sends — a Chrome numeric id, a round-tripped server string id ("tab_..."),
    // or null/absent (a tab with no stable id, or an older client that
    // serialized a missing id as null). buildTabRows already guards `!== null`;
    // rejecting null *here* used to 400 the ENTIRE workspace PUT over one
    // ephemeral field, breaking every sync of an already-synced workspace.
    // .nullish() = .optional().nullable().
    id: z.union([z.string(), z.number()]).nullish(),
    // Not .url(): Chrome emits about:, chrome:, data: and other URIs that
    // must round-trip; an odd one must not reject the whole workspace PUT
    url: z.string().min(1),
    title: z.string().max(500).optional(),
    faviconUrl: z.string().optional().nullable(),
    // Optional so the service can default missing positions to the array index
    position: z.number().int().min(0).optional(),
    isPinned: z.boolean().default(false),
    groupId: z.string().optional().nullable(), // Stable TabGroup.id for persistence
    metadata: z.record(z.unknown()).default({}),
  }),
);

export const ResourceSchema = z.object({
  id: z.string().nullish(), // Client might send ID for update/sync (or null)
  title: z.string().max(500),
  // Not .url(): like TabSchema.url, a resource URL must round-trip even when it
  // is scheme-less or otherwise odd. A strict .url() here 400s the ENTIRE
  // workspace PUT over a single bad resource — wedging sync for every tab,
  // note, and task in that workspace (the same outage class as a rejected tab
  // id). The client normalizes new resource URLs (prepends https://); this
  // guard ensures one legacy bad row can never break the whole sync.
  url: z.string().min(1),
  // Drop .url() for the same reason: a favicon may be a relative path or an odd
  // URI and must never wedge the PUT.
  faviconUrl: z.string().optional().nullable(),
  position: z.number().int().min(0).optional(),
});

export const SectionSchema = z.object({
  id: z.string().nullish(), // tolerate null (sync may echo it); see TabSchema.id
  title: z.string().max(255),
  position: z.number().int().min(0).optional(),
  resources: z.array(ResourceSchema).optional(),
});

export const NoteSchema = z.object({
  id: z.string().nullish(), // tolerate null (sync may echo it); see TabSchema.id
  title: z.string().max(255),
  content: z.string(),
  position: z.number().int().min(0).optional(),
});

export const TaskSchema = z.object({
  id: z.string().nullish(), // tolerate null (sync may echo it); see TabSchema.id
  title: z.string().max(500),
  completed: z.boolean().default(false),
  position: z.number().int().min(0).optional(),
});

export const TabGroupSchema = z.object({
  id: z.string(),
  title: z.string().max(255).optional(),
  color: z.string().max(20),
  collapsed: z.boolean().default(false),
});

export const WorkspaceCreateSchema = z.object({
  name: z.string().min(1).max(255),
  description: z.string().optional().nullable(),
  color: z.string().max(7).optional().nullable(),
  icon: z.string().max(50).optional().nullable(),
  groupId: z.string().optional().nullable(),
  position: z.number().int().min(0).default(0),
  settings: z.record(z.unknown()).default({}),
  tabs: z.array(TabSchema).optional(),
  tabGroups: z.array(TabGroupSchema).optional(), // Chrome tab groups for restoration
  sections: z.array(SectionSchema).optional(),
  notes: z.array(NoteSchema).optional(),
  tasks: z.array(TaskSchema).optional(),
  resources: z.array(ResourceSchema).optional(),
});

export const WorkspaceUpdateSchema = z.object({
  name: z.string().min(1).max(255).optional(),
  description: z.string().optional().nullable(),
  color: z.string().max(7).optional().nullable(),
  icon: z.string().max(50).optional().nullable(),
  groupId: z.string().optional().nullable(),
  position: z.number().int().optional(),
  settings: z.record(z.unknown()).optional(),
  tabs: z.array(TabSchema).optional(),
  tabGroups: z.array(TabGroupSchema).optional(), // Chrome tab groups for restoration
  sections: z.array(SectionSchema).optional(),
  notes: z.array(NoteSchema).optional(),
  tasks: z.array(TaskSchema).optional(),
  resources: z.array(ResourceSchema).optional(),
  // Optimistic concurrency: version the client based this update on.
  // Absent -> legacy client, update is accepted unconditionally.
  baseVersion: z.number().int().min(0).optional(),
  // Protocol flags (never persisted as workspace data): when either is true
  // and an x-device-id header is present, the workspace's active-device lease
  // is assigned to that device.
  tabSync: z.boolean().optional(),
  claimActiveDevice: z.boolean().optional(),
});

export const WorkspaceSaveTabsSchema = z.object({
  tabs: z.array(TabSchema),
});

export const WorkspaceRestoreTabsSchema = z.object({
  workspaceId: z.string().uuid(),
  closeCurrentTabs: z.boolean().default(false),
});

export const TabMoveSchema = z.object({
  tabId: z.string().uuid(),
  targetWorkspaceId: z.string().uuid(),
  position: z.number().int().min(0).optional(),
});

export const TabReorderSchema = z.object({
  tabId: z.string().uuid(),
  newPosition: z.number().int().min(0),
});

export const TabBulkOperationSchema = z.object({
  tabIds: z.array(z.string().uuid()).min(1),
  operation: z.enum(["close", "suspend", "pin", "unpin"]),
});

export type TabInput = z.infer<typeof TabSchema>;
export type WorkspaceCreateInput = z.infer<typeof WorkspaceCreateSchema>;
export type WorkspaceUpdateInput = z.infer<typeof WorkspaceUpdateSchema>;
export type WorkspaceSaveTabsInput = z.infer<typeof WorkspaceSaveTabsSchema>;
export type WorkspaceRestoreTabsInput = z.infer<
  typeof WorkspaceRestoreTabsSchema
>;
export type TabMoveInput = z.infer<typeof TabMoveSchema>;
export type TabReorderInput = z.infer<typeof TabReorderSchema>;
export type TabBulkOperationInput = z.infer<typeof TabBulkOperationSchema>;
