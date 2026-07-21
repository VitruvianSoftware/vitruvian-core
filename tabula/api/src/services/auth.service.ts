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

import { User } from "../generated/prisma/client";
import { getWorkOS, getWorkOSClientId } from "../lib/workos";
import { prisma } from "../lib/prisma";
import {
  generateRefreshToken,
  hashRefreshToken,
  refreshTokenExpiry,
} from "../lib/auth";

/** Minimal user identity used to mint a fresh access token. */
export interface SessionUser {
  id: string;
  email: string;
  tier: string;
}

export class AuthService {
  /**
   * Generate the WorkOS authorization URL
   */
  static async getAuthorizationUrl() {
    const [workos, clientId] = await Promise.all([
      getWorkOS(),
      getWorkOSClientId(),
    ]);
    return workos.userManagement.getAuthorizationUrl({
      clientId,
      provider: "authkit",
      redirectUri: `${process.env.API_URL || "http://localhost:8080/api/v1"}/auth/callback`,
    });
  }

  /**
   * Exchange code for user and sync with database
   * Returns user from DB plus profile picture from WorkOS (not stored)
   */
  static async authenticateAndSyncUser(
    code: string,
  ): Promise<User & { picture?: string }> {
    const [workos, clientId] = await Promise.all([
      getWorkOS(),
      getWorkOSClientId(),
    ]);
    const { user: workosUser } =
      await workos.userManagement.authenticateWithCode({
        clientId,
        code,
      });

    const { email, firstName, lastName, profilePictureUrl } = workosUser;

    if (!email) {
      throw new Error("User email not provided by WorkOS");
    }

    const name =
      firstName && lastName
        ? `${firstName} ${lastName}`
        : firstName || email.split("@")[0];

    // Sync user to local database
    const user = await prisma.user.upsert({
      where: { email },
      update: {
        lastLoginAt: new Date(),
      },
      create: {
        email,
        name,
        lastLoginAt: new Date(),
      },
    });

    // Return user with profile picture (from WorkOS, not stored in DB)
    return {
      ...user,
      picture: profilePictureUrl ?? undefined,
    };
  }

  /**
   * Create a server-side session for a user and return the raw refresh token.
   * Only the SHA-256 hash of the token is persisted, so a DB leak does not
   * expose usable refresh tokens. The raw token is shown to the client once.
   */
  static async createSession(
    userId: string,
    deviceInfo?: Record<string, unknown>,
  ): Promise<{ refreshToken: string; expiresAt: Date }> {
    const refreshToken = generateRefreshToken();
    const expiresAt = refreshTokenExpiry();

    await prisma.session.create({
      data: {
        userId,
        refreshTokenHash: hashRefreshToken(refreshToken),
        deviceInfo: deviceInfo ? (deviceInfo as object) : undefined,
        expiresAt,
      },
    });

    return { refreshToken, expiresAt };
  }

  /**
   * Rotate a refresh token: validate it against a live (non-expired) session,
   * issue a brand-new refresh token, re-read the user's CURRENT tier from the
   * DB (so plan downgrades take effect within an access-token lifetime), and
   * return the data needed to mint a fresh access token.
   *
   * Returns null when the token is unknown or expired (the caller maps that to
   * 401). Rotation invalidates the presented token, so a stolen-and-replayed
   * refresh token stops working once the legitimate client refreshes.
   */
  static async rotateRefreshToken(refreshToken: string): Promise<{
    user: SessionUser;
    refreshToken: string;
    expiresAt: Date;
  } | null> {
    if (!refreshToken) return null;

    const session = await prisma.session.findFirst({
      where: { refreshTokenHash: hashRefreshToken(refreshToken) },
      include: { user: true },
    });

    if (!session || !session.user) return null;
    if (session.expiresAt && session.expiresAt.getTime() <= Date.now()) {
      // Expired session: clean it up and reject.
      await prisma.session
        .delete({ where: { id: session.id } })
        .catch(() => undefined);
      return null;
    }

    const newRefreshToken = generateRefreshToken();
    const expiresAt = refreshTokenExpiry();

    await prisma.session.update({
      where: { id: session.id },
      data: {
        refreshTokenHash: hashRefreshToken(newRefreshToken),
        expiresAt,
        lastActiveAt: new Date(),
      },
    });

    return {
      user: {
        id: session.user.id,
        email: session.user.email,
        tier: session.user.tier,
      },
      refreshToken: newRefreshToken,
      expiresAt,
    };
  }

  /**
   * Invalidate a session server-side (logout). Deletes the Session row matching
   * the refresh token so the token can no longer be rotated. Returns true when a
   * session was removed. Idempotent: an unknown token returns false.
   */
  static async revokeRefreshToken(refreshToken: string): Promise<boolean> {
    if (!refreshToken) return false;
    const result = await prisma.session.deleteMany({
      where: { refreshTokenHash: hashRefreshToken(refreshToken) },
    });
    return result.count > 0;
  }
}
