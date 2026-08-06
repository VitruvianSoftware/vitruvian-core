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

import { createServer } from "node:http";

import { SignJWT, errors, generateKeyPair, type CryptoKey } from "jose";

import {
  AudienceMismatchError,
  SubjectNotAllowedError,
  IdpUnavailableError,
  isIdpSideFailure,
  InvalidTokenError,
  MissingTokenError,
  OpaqueTokenError,
  audienceScopeFor,
  createTokenVerifier,
  extractBearerToken,
  fullScopeString,
  looksLikeJwt,
} from "../src/auth.js";

const ISSUER = "https://auth.example.test";
const PROJECT_ID = "123456789";
const OTHER_PROJECT_ID = "987654321";

let privateKey: CryptoKey;
let publicKey: CryptoKey;

beforeAll(async () => {
  ({ privateKey, publicKey } = await generateKeyPair("RS256"));
});

/** Mints a token the way Zitadel would, with overridable claims. */
async function mintToken({
  audience = PROJECT_ID,
  issuer = ISSUER,
  subject = "user-42",
  expiresIn = "5m",
}: {
  audience?: string | string[];
  issuer?: string;
  subject?: string;
  expiresIn?: string;
} = {}): Promise<string> {
  return new SignJWT({})
    .setProtectedHeader({ alg: "RS256" })
    .setIssuer(issuer)
    .setAudience(audience)
    .setSubject(subject)
    .setIssuedAt()
    .setExpirationTime(expiresIn)
    .sign(privateKey);
}

function verifier(projectId = PROJECT_ID, allowedSubjects = ["user-42"]) {
  return createTokenVerifier({
    issuer: ISSUER,
    projectId,
    allowedSubjects,
    keySource: () => Promise.resolve(publicKey),
  });
}

describe("looksLikeJwt", () => {
  it("accepts three base64url segments", () => {
    expect(looksLikeJwt("aaa.bbb.ccc")).toBe(true);
    expect(looksLikeJwt("a-_A.b-_B.c-_C")).toBe(true);
  });

  it("rejects Zitadel's opaque token shape", () => {
    // Opaque access tokens are a single random string, not a dotted triple.
    expect(looksLikeJwt("Xk9fJ2mQ7bTn4vRz8sLpWc")).toBe(false);
    expect(looksLikeJwt("two.segments")).toBe(false);
    expect(looksLikeJwt("four.seg.ments.here")).toBe(false);
    expect(looksLikeJwt("has.bad!chars.here")).toBe(false);
  });
});

describe("extractBearerToken", () => {
  it("pulls the credential out of a Bearer header, case-insensitively", () => {
    expect(extractBearerToken("Bearer abc.def.ghi")).toBe("abc.def.ghi");
    expect(extractBearerToken("bearer abc.def.ghi")).toBe("abc.def.ghi");
    expect(extractBearerToken("  Bearer   abc.def.ghi  ")).toBe("abc.def.ghi");
  });

  it("rejects absent, malformed or empty credentials", () => {
    expect(() => extractBearerToken(undefined)).toThrow(MissingTokenError);
    expect(() => extractBearerToken("")).toThrow(MissingTokenError);
    expect(() => extractBearerToken("Basic abc")).toThrow(MissingTokenError);
    expect(() => extractBearerToken("Bearer ")).toThrow(MissingTokenError);
  });
});

describe("scope string helpers", () => {
  it("builds Zitadel's project audience scope", () => {
    expect(audienceScopeFor(PROJECT_ID)).toBe(
      `urn:zitadel:iam:org:project:id:${PROJECT_ID}:aud`
    );
  });

  it("builds the full string a client must request", () => {
    expect(fullScopeString(PROJECT_ID)).toBe(
      `openid offline_access urn:zitadel:iam:org:project:id:${PROJECT_ID}:aud`
    );
  });
});

describe("token verification", () => {
  it("accepts a correctly issued token and returns the subject", async () => {
    const caller = await verifier().verify(await mintToken());
    expect(caller.subject).toBe("user-42");
  });

  it("accepts an audience array that includes the project", async () => {
    const token = await mintToken({ audience: [OTHER_PROJECT_ID, PROJECT_ID] });
    await expect(verifier().verify(token)).resolves.toMatchObject({
      subject: "user-42",
    });
  });

  it("rejects a token from a different issuer", async () => {
    const token = await mintToken({ issuer: "https://evil.example.test" });
    await expect(verifier().verify(token)).rejects.toBeInstanceOf(
      InvalidTokenError
    );
  });

  it("rejects an expired token", async () => {
    const token = await mintToken({ expiresIn: "-1m" });
    await expect(verifier().verify(token)).rejects.toBeInstanceOf(
      InvalidTokenError
    );
  });

  // This server and the IdP are separate hosts with independently drifting
  // clocks. jose defaults to zero slack, which rejects freshly-issued tokens
  // on a couple of seconds of drift — presenting as an auth bug that
  // reproduces only sometimes. The tolerance is deliberate, so it is pinned:
  // small drift is absorbed, a genuinely expired token is still refused.
  // Pinned at the boundary, not merely bracketed. The earlier version asserted
  // -10s accepted and -120s rejected, which only proves the tolerance sits
  // somewhere in (10s, 120s] — a later widening to 90s would have passed
  // unnoticed. These two cases fail if the value moves in either direction.
  //
  // Scope of the evidence: the drift this absorbs is between this server and
  // Zitadel, co-located and measured at 81ms worst case over 24h. It says
  // nothing about the clock on the client side issuing the request, which
  // nobody here can observe.
  it("accepts 29s past expiry and rejects 31s, pinning the tolerance at 30s", async () => {
    await expect(
      verifier().verify(await mintToken({ expiresIn: "-29s" }))
    ).resolves.toMatchObject({ subject: "user-42" });

    await expect(
      verifier().verify(await mintToken({ expiresIn: "-31s" }))
    ).rejects.toBeInstanceOf(InvalidTokenError);
  });

  it("rejects a token signed by an unknown key", async () => {
    const { privateKey: attackerKey } = await generateKeyPair("RS256");
    const forged = await new SignJWT({})
      .setProtectedHeader({ alg: "RS256" })
      .setIssuer(ISSUER)
      .setAudience(PROJECT_ID)
      .setSubject("user-42")
      .setIssuedAt()
      .setExpirationTime("5m")
      .sign(attackerKey);
    await expect(verifier().verify(forged)).rejects.toBeInstanceOf(
      InvalidTokenError
    );
  });

  // The failure mode IgnoreChanges on accessTokenType makes undetectable from
  // the Pulumi side: a client silently issuing opaque tokens. Without this
  // branch it would surface as an indistinguishable stream of 401s.
  it("diagnoses an opaque token instead of reporting a bad signature", async () => {
    const error = await verifier()
      .verify("Xk9fJ2mQ7bTn4vRz8sLpWc")
      .catch((e: unknown) => e);
    expect(error).toBeInstanceOf(OpaqueTokenError);
    expect((error as OpaqueTokenError).message).toContain("accessTokenType");
    expect((error as OpaqueTokenError).status).toBe(401);
  });

  // The failure mode a human causes by pasting an incomplete scope string into
  // Spark's config form. The token is valid in every other respect.
  it("diagnoses a wrong audience and names the missing scope", async () => {
    const token = await mintToken({ audience: OTHER_PROJECT_ID });
    const error = await verifier()
      .verify(token)
      .catch((e: unknown) => e);

    expect(error).toBeInstanceOf(AudienceMismatchError);
    const err = error as AudienceMismatchError;
    expect(err.status).toBe(403);
    expect(err.code).toBe("insufficient_scope");
    // The whole point: the error carries the fix, not just the rejection.
    expect(err.requiredScope).toBe(audienceScopeFor(PROJECT_ID));
    expect(err.message).toContain(fullScopeString(PROJECT_ID));
    // And it says what was actually presented, so a wrong project is obvious.
    expect(err.message).toContain(OTHER_PROJECT_ID);
  });

  it("rejects a token with no audience at all", async () => {
    const token = await new SignJWT({})
      .setProtectedHeader({ alg: "RS256" })
      .setIssuer(ISSUER)
      .setSubject("user-42")
      .setIssuedAt()
      .setExpirationTime("5m")
      .sign(privateKey);
    await expect(verifier().verify(token)).rejects.toBeInstanceOf(
      AudienceMismatchError
    );
  });

  it("rejects a token with no subject", async () => {
    const token = await new SignJWT({})
      .setProtectedHeader({ alg: "RS256" })
      .setIssuer(ISSUER)
      .setAudience(PROJECT_ID)
      .setIssuedAt()
      .setExpirationTime("5m")
      .sign(privateKey);
    await expect(verifier().verify(token)).rejects.toBeInstanceOf(
      InvalidTokenError
    );
  });

  it("verifies straight from an Authorization header", async () => {
    const token = await mintToken();
    await expect(
      verifier().verifyAuthorizationHeader(`Bearer ${token}`)
    ).resolves.toMatchObject({ subject: "user-42" });
    await expect(
      verifier().verifyAuthorizationHeader(undefined)
    ).rejects.toBeInstanceOf(MissingTokenError);
  });
});

// The defect this section exists for: `jwtVerify` fetches the JWKS over the
// network, so an IdP outage lands in the same catch as a bad signature. It was
// reported as InvalidTokenError/401 — telling a caller holding a valid token
// that their credential was bad, and making an outage indistinguishable from
// an unauthenticated probe in the response codes.
//
// These use the REAL verifier against a dead JWKS URI. The earlier transport
// test asserted the outage path with a stub throwing a raw TypeError, which
// the real verifier never produces — so it passed while the real path was
// wrong. That is the difference between testing a path and testing a stub.
describe("IdP reachability is distinguished from token validity", () => {
  async function realVerifierWithDeadJwks() {
    return createTokenVerifier({
      issuer: ISSUER,
      allowedSubjects: ["user-42"],
      projectId: PROJECT_ID,
      jwksUri: "http://127.0.0.1:1/unreachable",
    });
  }

  it("reports a JWKS outage as 503, not as an invalid token", async () => {
    const verifier = await realVerifierWithDeadJwks();
    const error = await verifier.verify(await mintToken()).catch((e) => e);

    expect(error).toBeInstanceOf(IdpUnavailableError);
    expect((error as IdpUnavailableError).status).toBe(503);
    // The message has to say whose fault it is, or the caller goes looking at
    // their own credential.
    expect((error as IdpUnavailableError).message).toContain("not judged");
  });

  it("still reports a genuinely bad token as 401 when the IdP is reachable", async () => {
    const { privateKey: attackerKey } = await generateKeyPair("RS256");
    const forged = await new SignJWT({})
      .setProtectedHeader({ alg: "RS256" })
      .setIssuer(ISSUER)
      .setAudience(PROJECT_ID)
      .setSubject("user-42")
      .setIssuedAt()
      .setExpirationTime("5m")
      .sign(attackerKey);

    const error = await verifier().verify(forged).catch((e) => e);
    expect(error).toBeInstanceOf(InvalidTokenError);
    expect((error as InvalidTokenError).status).toBe(401);
  });

  // The discrimination is "did jose reach a verdict", not "does this look like
  // a network error". An unrecognised failure must land on 503 — being wrong
  // in that direction tells the truth (we could not judge it); being wrong the
  // other way accuses a valid credential.
  it("treats an unrecognised failure as unavailability, not as rejection", async () => {
    const verifier = createTokenVerifier({
      issuer: ISSUER,
      allowedSubjects: ["user-42"],
      projectId: PROJECT_ID,
      keySource: () => {
        throw new Error("something nobody anticipated");
      },
    });
    const error = await verifier.verify(await mintToken()).catch((e) => e);
    expect(error).toBeInstanceOf(IdpUnavailableError);
  });
});

// The first fix for the JWKS-outage defect survived the defect. All fourteen
// jose error classes extend JOSEError, so "is it a JOSEError" cannot separate
// a verdict from an inability to reach one — and the repro used an
// unreachable host, which throws a bare TypeError and so took the correct
// branch by accident. These test the shapes that actually discriminate.
describe("IdP-side failures are classified explicitly, not by base class", () => {
  // A slow IdP, not a dead one: the server accepts the connection and never
  // answers. This is the case the earlier fix got wrong.
  it("reports a JWKS timeout as 503, not as an invalid token", async () => {
    const hanging = createServer(() => {
      /* accept the socket and never respond */
    });
    await new Promise<void>((resolve) => hanging.listen(0, resolve));
    const { port } = hanging.address() as { port: number };

    try {
      const verifier = createTokenVerifier({
        issuer: ISSUER,
        allowedSubjects: ["user-42"],
        projectId: PROJECT_ID,
        jwksUri: `http://127.0.0.1:${port}/jwks`,
        jwksTimeoutMs: 50,
      });
      const error = await verifier.verify(await mintToken()).catch((e) => e);

      expect(error).toBeInstanceOf(IdpUnavailableError);
      expect((error as IdpUnavailableError).status).toBe(503);
    } finally {
      hanging.closeAllConnections?.();
      await new Promise<void>((resolve) => hanging.close(() => resolve()));
    }
  });

  it("routes each IdP-side jose error to unavailability", () => {
    expect(isIdpSideFailure(new errors.JWKSTimeout())).toBe(true);
    expect(isIdpSideFailure(new errors.JWKSInvalid("bad"))).toBe(true);
    expect(isIdpSideFailure(new errors.JWKInvalid("bad"))).toBe(true);
    expect(isIdpSideFailure(new errors.JWKSMultipleMatchingKeys())).toBe(true);
    // Not a jose error at all — unreachable host. Also ours.
    expect(isIdpSideFailure(new TypeError("fetch failed"))).toBe(true);
  });

  it("keeps genuine verdicts about the token on the caller's side", () => {
    expect(isIdpSideFailure(new errors.JWTExpired("exp", {}))).toBe(false);
    expect(isIdpSideFailure(new errors.JWSSignatureVerificationFailed())).toBe(
      false
    );
    expect(isIdpSideFailure(new errors.JWTInvalid("bad"))).toBe(false);
    expect(isIdpSideFailure(new errors.JWKSNoMatchingKey())).toBe(false);
    expect(isIdpSideFailure(new errors.JOSEAlgNotAllowed("no"))).toBe(false);
  });

  // A partial enumeration is what produced the original defect, so this fails
  // if jose adds an error class nobody has classified.
  it("has classified every error class the library exposes", () => {
    const unclassified = Object.entries(errors)
      .filter(([name]) => name !== "JOSEError")
      .map(([name, ctor]) => [name, (ctor as { code?: string }).code])
      .filter(([, code]) => typeof code !== "string");

    expect(unclassified).toEqual([]);
    // 14 as of jose@6.2.4; a change here means a new case to place.
    expect(Object.keys(errors).filter((n) => n !== "JOSEError")).toHaveLength(14);
  });
});

// The per-request identity control. Everything else in this file checks that a
// token is genuine; this checks whose it is.
describe("subject allow-list", () => {
  it("admits a listed subject", async () => {
    const token = await mintToken({ subject: "379361013981513322" });
    const caller = await verifier(PROJECT_ID, [
      "379361013981513322",
    ]).verify(token);
    expect(caller.subject).toBe("379361013981513322");
  });

  it("refuses a valid token from an unlisted subject", async () => {
    // The token is entirely genuine: right issuer, right audience, valid
    // signature, unexpired. Zitadel will issue exactly this to any account in
    // the instance, because the audience scope is grantable without checking
    // the requesting user's grants.
    const token = await mintToken({ subject: "999999999999999999" });
    await expect(
      verifier(PROJECT_ID, ["379361013981513322"]).verify(token)
    ).rejects.toBeInstanceOf(SubjectNotAllowedError);
  });

  it("names the received subject in the rejection", async () => {
    // Zitadel subjects are opaque numeric IDs, so an operator configuring this
    // cannot discover the right value without decoding a token by hand.
    const token = await mintToken({ subject: "123456789012345678" });
    await expect(
      verifier(PROJECT_ID, ["other"]).verify(token)
    ).rejects.toThrow(/123456789012345678/);
  });

  it("rejects with 403, not 401", async () => {
    // The credential is fine; the identity is not served. A 401 would tell a
    // client to go and get a new token, which would produce the same result.
    const token = await mintToken({ subject: "nope" });
    await verifier(PROJECT_ID, ["other"])
      .verify(token)
      .catch((error: SubjectNotAllowedError) => {
        expect(error.status).toBe(403);
        expect(error.subject).toBe("nope");
      });
    expect.assertions(2);
  });

  it("refuses to construct a verifier with an empty allow-list", () => {
    // Fail at construction rather than admitting everyone at request time.
    expect(() => verifier(PROJECT_ID, [])).toThrow(/at least one allowed subject/);
  });

  it("checks the subject only after the signature and audience", async () => {
    // Ordering matters: this must never be the reason a forged or misaudienced
    // token is accepted, so an unlisted subject on a bad token still reports
    // the token problem.
    const wrongAudience = await mintToken({
      audience: "some-other-project",
      subject: "not-listed",
    });
    await expect(
      verifier(PROJECT_ID, ["379361013981513322"]).verify(wrongAudience)
    ).rejects.toBeInstanceOf(AudienceMismatchError);
  });
});
