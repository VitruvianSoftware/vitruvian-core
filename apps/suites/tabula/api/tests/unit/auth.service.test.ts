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

import bcrypt from "bcryptjs";

/**
 * Example unit test for password hashing service
 * This demonstrates the testing pattern for service layer functions
 */

describe("AuthService - Password Hashing", () => {
  describe("hashPassword", () => {
    it("should hash a password successfully", async () => {
      const password = "TestPassword123!";
      const hash = await bcrypt.hash(password, 12);

      expect(hash).toBeDefined();
      expect(hash).not.toBe(password);
      expect(hash.length).toBeGreaterThan(50);
    });

    it("should generate different hashes for the same password", async () => {
      const password = "TestPassword123!";
      const hash1 = await bcrypt.hash(password, 12);
      const hash2 = await bcrypt.hash(password, 12);

      expect(hash1).not.toBe(hash2);
    });
  });

  describe("verifyPassword", () => {
    it("should verify a correct password", async () => {
      const password = "TestPassword123!";
      const hash = await bcrypt.hash(password, 12);

      const isValid = await bcrypt.compare(password, hash);
      expect(isValid).toBe(true);
    });

    it("should reject an incorrect password", async () => {
      const password = "TestPassword123!";
      const wrongPassword = "WrongPassword123!";
      const hash = await bcrypt.hash(password, 12);

      const isValid = await bcrypt.compare(wrongPassword, hash);
      expect(isValid).toBe(false);
    });

    it("should reject empty password", async () => {
      const password = "TestPassword123!";
      const hash = await bcrypt.hash(password, 12);

      const isValid = await bcrypt.compare("", hash);
      expect(isValid).toBe(false);
    });
  });
});
