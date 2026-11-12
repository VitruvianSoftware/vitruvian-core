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
 * Workspace-related types shared across extension and web dashboard
 */

export interface Tab {
  id?: number;
  url: string;
  title: string;
  favIconUrl?: string;
  pinned?: boolean;
  active?: boolean;
  index?: number;
  groupId?: string; // Stable TabGroup.id (UUID) for persistence
  chromeGroupId?: number; // Chrome's ephemeral group ID (session tracking only)
}

export interface Resource {
  id: string;
  title: string;
  url: string;
  faviconUrl?: string;
  createdAt: number;
  order?: number;
}

export interface Section {
  id: string;
  title: string;
  resources: Resource[];
  order?: number;
}

export interface Note {
  id: string;
  title: string;
  content: string;
  updatedAt: number;
  createdAt?: number;
}

export interface Task {
  id: string;
  title: string;
  completed: boolean;
  dueDate?: number;
  createdAt: number;
}

/**
 * Chrome Tab Group metadata for persistence across workspace switches.
 * Uses stable UUIDs for persistence, with Chrome's ephemeral IDs stored
 * separately for session tracking.
 */
export interface TabGroup {
  id: string; // Stable UUID for persistence (e.g., "tg_1234567890_abc123")
  chromeGroupId?: number; // Chrome's ephemeral group ID (session tracking only)
  title?: string; // User-assigned group name
  color: string; // grey | blue | red | yellow | green | pink | purple | cyan | orange
  collapsed: boolean; // Whether group is collapsed in Chrome
}

export interface Workspace {
  id: string;
  name: string;
  description?: string;
  color?: string;
  icon?: string;
  groupId?: string; // Space group ID (for sidebar organization)
  position: number;
  tabs: Tab[];
  tabGroups?: TabGroup[]; // Chrome tab groups for restoration (optional for backward compatibility)
  resources: Resource[];
  sections: Section[];
  notes: Note[];
  tasks: Task[];
  createdAt: number;
  updatedAt: number;
  /** Server-assigned optimistic-concurrency version; undefined until first successful sync */
  version?: number;
  /** Device currently live-syncing this workspace's tabs (advisory lease, server-maintained) */
  activeDeviceId?: string | null;
  activeDeviceSeenAt?: string | null;
}

export interface SpaceGroup {
  id: string;
  title: string;
  color?: string;
  collapsed: boolean;
  position: number;
  createdAt: number;
  updatedAt: number;
  /** Server-assigned optimistic-concurrency version; undefined until first successful sync */
  version?: number;
}

export interface WorkspaceCreateInput {
  name: string;
  description?: string;
  color?: string;
  icon?: string;
}

export interface WorkspaceUpdateInput {
  name?: string;
  description?: string;
  color?: string;
  icon?: string;
  tabs?: Tab[];
  sections?: Section[];
}
