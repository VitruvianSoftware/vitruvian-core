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
 * Test fixtures for API integration tests
 */

export const mockUser = {
  id: "123e4567-e89b-12d3-a456-426614174000",
  email: "test@example.com",
  name: "Test User",
  tier: "free",
  passwordHash: "$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5Qqe9lH7IaU5W", // "TestPassword123!"
};

export const mockWorkspace = {
  id: "223e4567-e89b-12d3-a456-426614174000",
  userId: mockUser.id,
  name: "Work",
  description: "Work-related tabs",
  color: "#0066CC",
  icon: "briefcase",
  position: 0,
};

export const mockTab = {
  id: "323e4567-e89b-12d3-a456-426614174000",
  workspaceId: mockWorkspace.id,
  url: "https://example.com",
  title: "Example Website",
  faviconUrl: "https://example.com/favicon.ico",
  position: 0,
  isPinned: false,
};

export const mockSession = {
  id: "423e4567-e89b-12d3-a456-426614174000",
  userId: mockUser.id,
  refreshTokenHash: "$2b$12$refreshtokenhash",
  deviceInfo: {
    browser: "Chrome",
    os: "Windows",
    version: "120.0.0",
  },
  ipAddress: "127.0.0.1",
};
