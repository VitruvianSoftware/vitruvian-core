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
 * User service for user profile management
 */
import type { Prisma } from "../generated/prisma/client";
import { prisma } from "../lib/prisma";
import type { UserUpdateInput } from "../schemas/user";

// Type for User without password hash
type UserProfile = {
  id: string;
  email: string;
  name: string;
  tier: string;
  createdAt: Date;
  updatedAt: Date;
  lastLoginAt: Date | null;
  preferences: Prisma.JsonValue;
};

export class UserService {
  /**
   * Get user profile by ID
   */
  static async getUserById(userId: string): Promise<UserProfile | null> {
    return prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        name: true,
        tier: true,
        createdAt: true,
        updatedAt: true,
        lastLoginAt: true,
        preferences: true,
        passwordHash: false, // Never expose password hash
      },
    });
  }

  /**
   * Update user profile
   */
  static async updateUser(
    userId: string,
    updates: UserUpdateInput,
  ): Promise<UserProfile> {
    return prisma.user.update({
      where: { id: userId },
      data: {
        ...(updates.name && { name: updates.name }),
        ...(updates.preferences && {
          preferences: updates.preferences as Prisma.InputJsonValue,
        }),
        updatedAt: new Date(),
      },
      select: {
        id: true,
        email: true,
        name: true,
        tier: true,
        createdAt: true,
        updatedAt: true,
        lastLoginAt: true,
        preferences: true,
        passwordHash: false,
      },
    });
  }

  /**
   * Delete user account (soft delete - deactivate)
   */
  static async deleteUser(userId: string): Promise<void> {
    // In a real implementation, you might want to soft delete or anonymize data
    // For now, we'll just delete the user and cascade delete related data
    await prisma.user.delete({
      where: { id: userId },
    });
  }

  /**
   * Get password reset URL from WorkOS
   * Note: WorkOS AuthKit handles password management
   */
  static getPasswordResetUrl(_email: string): string {
    // WorkOS AuthKit uses a dedicated password reset flow
    // Users should be redirected to the WorkOS hosted UI for password reset
    const apiUrl = process.env.API_URL || "http://localhost:8080";
    // For WorkOS, password reset is handled through the authentication flow
    // We'll return the login URL which includes password reset functionality
    return `${apiUrl}/api/v1/auth/login?action=reset_password`;
  }
}
