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
 * User routes for profile management
 */
import { FastifyInstance } from "fastify";
import { UserService } from "../services/user.service";
import { authenticateUser } from "../middleware/auth";
import { UserUpdateSchema, PasswordResetRequestSchema } from "../schemas/user";

export async function userRoutes(fastify: FastifyInstance) {
  /**
   * GET /api/v1/users/me
   * Get current user profile
   */
  fastify.get(
    "/me",
    { preHandler: authenticateUser },
    async (request, reply) => {
      try {
        const user = await UserService.getUserById(request.user!.id);

        if (!user) {
          return reply.code(404).send({
            error: "Not Found",
            message: "User not found",
          });
        }

        return { data: user };
      } catch (error) {
        request.log.error(error);
        return reply.code(500).send({
          error: "Internal Server Error",
          message: "Failed to get user profile",
        });
      }
    },
  );

  /**
   * PATCH /api/v1/users/me
   * Update current user profile
   */
  fastify.patch<{ Body: unknown }>(
    "/me",
    { preHandler: authenticateUser },
    async (request, reply) => {
      try {
        // Validate request body
        const validationResult = UserUpdateSchema.safeParse(request.body);
        if (!validationResult.success) {
          return reply.code(400).send({
            error: "Validation Error",
            message: "Invalid request body",
            details: validationResult.error.issues,
          });
        }

        const updatedUser = await UserService.updateUser(
          request.user!.id,
          validationResult.data,
        );

        return { data: updatedUser };
      } catch (error) {
        request.log.error(error);
        return reply.code(500).send({
          error: "Internal Server Error",
          message: "Failed to update user profile",
        });
      }
    },
  );

  /**
   * DELETE /api/v1/users/me
   * Delete current user account
   */
  fastify.delete(
    "/me",
    { preHandler: authenticateUser },
    async (request, reply) => {
      try {
        await UserService.deleteUser(request.user!.id);

        return reply.code(204).send();
      } catch (error) {
        request.log.error(error);
        return reply.code(500).send({
          error: "Internal Server Error",
          message: "Failed to delete user account",
        });
      }
    },
  );

  /**
   * POST /api/v1/users/password-reset
   * Request password reset (returns WorkOS reset URL)
   */
  fastify.post<{ Body: unknown }>("/password-reset", async (request, reply) => {
    try {
      // Validate request body
      const validationResult = PasswordResetRequestSchema.safeParse(
        request.body,
      );
      if (!validationResult.success) {
        return reply.code(400).send({
          error: "Validation Error",
          message: "Invalid request body",
          details: validationResult.error.issues,
        });
      }

      const resetUrl = UserService.getPasswordResetUrl(
        validationResult.data.email,
      );

      return {
        data: {
          resetUrl,
          message: "Password reset URL generated",
        },
      };
    } catch (error) {
      request.log.error(error);
      return reply.code(500).send({
        error: "Internal Server Error",
        message: "Failed to generate password reset URL",
      });
    }
  });
}
