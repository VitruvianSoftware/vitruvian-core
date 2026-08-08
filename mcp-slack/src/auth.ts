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

// ---------------------------------------------------------------------------
// Bearer token validation (OAuth 2.0 resource server)
// ---------------------------------------------------------------------------
//
// Gemini Enterprise authenticates as a pre-registered confidential client
// against Zitadel and forwards the resulting access token to us. We are the
// resource server: we have no callback URL, we register no client, and we run
// no discovery endpoint. We validate the token we are handed and nothing else.
//
// Validation is local — signature and claims against the IdP's public JWKS —
// rather than a call back to Zitadel's introspection endpoint. Introspection
// would require this service to hold its own Zitadel credentials, which would
// put a second secret in the cluster; JWKS is public and needs none.
//
// Two failures here are configuration mistakes made elsewhere, and both would
// otherwise surface as an indistinguishable stream of 401s that reads exactly
// like a broken build. Each one names its own cause instead:
//
//   * the client is issuing opaque tokens (its accessTokenType is not JWT), or
//   * the caller's scope string omits the audience-granting scope, so a token
//     that is valid in every other respect carries the wrong audience.

import { createRemoteJWKSet, errors, jwtVerify, type JWTPayload } from "jose";

/** Base class for anything that should terminate a request at the boundary. */
export abstract class AuthError extends Error {
  /** HTTP status this failure should produce. */
  abstract readonly status: number;
  /** Machine-readable code, surfaced in the WWW-Authenticate error field. */
  abstract readonly code: string;
  /**
   * Identity the caller presented, when the failure got far enough to know it.
   *
   * Exists so the boundary can record *who* was refused without importing each
   * subclass to test for it. Undefined on the failures that happen before a
   * verified identity exists — no token, opaque token, bad signature — where
   * there is nothing trustworthy to record.
   */
  readonly presented?: string;
  /**
   * What {@link presented} represents — `"sub"`, `"azp"`, `"client_id"` — so
   * the refusal log can label the value it is printing instead of assuming it
   * is always a subject. Undefined wherever `presented` is.
   */
  readonly presentedLabel?: string;
}

/** No credentials presented at all. */
export class MissingTokenError extends AuthError {
  readonly status = 401;
  readonly code = "invalid_request";

  constructor() {
    super("Authorization header with a Bearer token is required.");
    this.name = "MissingTokenError";
  }
}

/**
 * The bearer token is not a JWT.
 *
 * This is nearly always an infrastructure misconfiguration rather than a bad
 * caller: Zitadel issues opaque tokens unless the OIDC client sets
 * accessTokenType to JWT. That field is deliberately covered by IgnoreChanges
 * in the Pulumi stack — it prevents a destructive replace diff, at the cost of
 * Pulumi never reconciling the value after creation. So this boundary is the
 * only place a wrong value gets noticed, and it says so plainly.
 */
export class OpaqueTokenError extends AuthError {
  readonly status = 401;
  readonly code = "invalid_token";

  constructor() {
    super(
      "Bearer token is not a JWT. The Zitadel OIDC client appears to be " +
        "issuing opaque tokens — check that its accessTokenType is " +
        "OIDC_TOKEN_TYPE_JWT (`pulumi stack output accessTokenType` after a " +
        "refresh, in the zitadel-apps-mcp-slack stack)."
    );
    this.name = "OpaqueTokenError";
  }
}

/**
 * We could not reach the IdP to validate the token at all.
 *
 * This is deliberately **not** a 401. `jwtVerify` fetches the JWKS over the
 * network, so an IdP outage arrives at the same catch as a bad signature —
 * and reporting it as "your token is invalid" is wrong twice over: it tells a
 * caller holding a perfectly good token to go and fix it, and it makes an
 * outage indistinguishable from an unauthenticated probe in the response
 * codes, so nothing downstream can alert on it.
 *
 * 503 with Retry-After says what is actually true: the token was never judged.
 */
export class IdpUnavailableError extends AuthError {
  readonly status = 503;
  readonly code = "temporarily_unavailable";

  constructor(reason: string) {
    super(
      `Unable to verify the bearer token: the identity provider could not be ` +
        `reached (${reason}). The token was not judged — this is a server-side ` +
        `failure, not a problem with the credential.`
    );
    this.name = "IdpUnavailableError";
  }
}

/** Signature, issuer or expiry check failed. */
export class InvalidTokenError extends AuthError {
  readonly status = 401;
  readonly code = "invalid_token";

  constructor(reason: string) {
    super(`Bearer token rejected: ${reason}`);
    this.name = "InvalidTokenError";
  }
}

/**
 * The token verified, but its audience does not include our project.
 *
 * The audience is granted by a scope the *client* requests, so the fix is in
 * the caller's configuration, not here. Naming the exact scope string turns a
 * silent uniform rejection into a self-service fix.
 */
export class AudienceMismatchError extends AuthError {
  readonly status = 403;
  readonly code = "insufficient_scope";
  readonly requiredScope: string;

  constructor(projectId: string, presented: string[]) {
    const requiredScope = audienceScopeFor(projectId);
    super(
      `Token audience does not include this server's Zitadel project ` +
        `(${projectId}). Presented audience: ` +
        `${presented.length > 0 ? presented.join(", ") : "(none)"}. ` +
        `Add "${requiredScope}" to the scopes requested by the OAuth client — ` +
        `the full string this server expects is "${fullScopeString(projectId)}".`
    );
    this.name = "AudienceMismatchError";
    this.requiredScope = requiredScope;
  }
}

/**
 * Raised when a valid token belongs to a subject this server does not serve.
 *
 * **Not redundant with Zitadel's `projectRoleCheck`, and not a duplicate of the
 * audience check.** Both of those are decided at *issuance*: they govern which
 * tokens Zitadel mints, so revoking a grant leaves every already-issued token
 * working until it expires. This is evaluated per request, against
 * configuration this server reads at startup — which makes it **the only
 * control here whose revocation takes effect on the next request** rather than
 * at the end of an access-token lifetime nobody has read yet.
 *
 * It is also the only one that discriminates between two users of the same
 * client. Zitadel's audience scope is documented as grantable to any client
 * that asks, without verifying the requesting user's grants, so `aud` alone
 * says the token came from this instance for this project — never who holds it.
 *
 * The received `sub` is named in the message on purpose. Zitadel subjects are
 * opaque numeric IDs with nothing human-readable in them, so an operator
 * configuring this cannot otherwise discover what to put in the variable
 * without decoding a token by hand.
 */
export class SubjectNotAllowedError extends AuthError {
  readonly status = 403;
  readonly code = "insufficient_scope";
  readonly subject: string;
  readonly presented: string;
  readonly presentedLabel = "sub";

  constructor(subject: string) {
    super(
      `Token is valid but subject "${subject}" is not served by this ` +
        `endpoint. Add it to OIDC_ALLOWED_SUBJECTS to grant access, or leave ` +
        `it out to keep this caller refused.`
    );
    this.name = "SubjectNotAllowedError";
    this.subject = subject;
    this.presented = subject;
  }
}

/**
 * The token carries an `azp` claim at all.
 *
 * Zitadel puts `azp` on **id_tokens** and `client_id` on **access tokens** —
 * confirmed against the installed `jose@6.2.4` and Zitadel's own token
 * construction, rather than assumed, because the spec only guarantees `azp`
 * is present when a token has multiple audiences. This endpoint is handed a
 * bearer credential, which is meant to be an access token; a token carrying
 * `azp` satisfying every other check is not evidence it was issued to the
 * expected client, because `azp` is a different claim from `client_id` and
 * this server never asked Zitadel to mint one for it. Rejecting outright,
 * rather than comparing `azp` to an expected value, means a token of the
 * wrong kind can never be mistaken for a correctly pinned one.
 *
 * Its own error class for the same reason {@link AudienceMismatchError} and
 * {@link SubjectNotAllowedError} are already distinct classes at the same
 * status: collapsing this into `ClientNotAllowedError` or
 * `SubjectNotAllowedError` would make a client-pinning rejection
 * indistinguishable from the other two, in both logs and the
 * `McpSlackSustainedForbidden` alert — three different security events
 * collapsing into one.
 */
export class AuthorizedPartyPresentError extends AuthError {
  readonly status = 403;
  readonly code = "insufficient_scope";
  readonly presented: string;
  readonly presentedLabel = "azp";

  constructor(azp: string) {
    super(
      `Token carries an "azp" claim ("${azp}"), which this endpoint does ` +
        `not accept. This looks like an id_token; only an access token ` +
        `issued directly to this server's pinned OIDC client is accepted.`
    );
    this.name = "AuthorizedPartyPresentError";
    this.presented = azp;
  }
}

/**
 * Raised when a valid, correctly-audienced, correctly-subjected token was not
 * issued to the OIDC client this server pins itself to (#1491).
 *
 * This closes a gap `OIDC_ALLOWED_SUBJECTS` cannot: Zitadel documents the
 * audience-granting scope as requestable by any client, without checking the
 * requesting user's grants. So a token can carry a listed subject and this
 * project's audience while having been minted for a client the operator never
 * authorised to reach this endpoint — the audience and subject checks above
 * both pass, and this is what actually narrows the caller to the intended
 * app. Pinning `client_id` closes the class of caller rather than one
 * instance of it, and — unlike the subject allow-list — needs no maintenance
 * as people join or leave it.
 *
 * `clientId !== config.allowedClientId` is the whole check, deliberately: an
 * absent, wrong-type or merely-different `client_id` all take the same
 * branch. A guard shaped `clientId && clientId !== expected` would let an
 * absent claim skip the check and pass — the same defect class as an
 * unvalidated optional channel parameter, just in a new claim.
 */
export class ClientNotAllowedError extends AuthError {
  readonly status = 403;
  readonly code = "insufficient_scope";
  readonly presented: string;
  readonly presentedLabel = "client_id";

  constructor(clientId: string) {
    super(
      clientId.length > 0
        ? `Token is valid but was issued to client "${clientId}", which ` +
          `this endpoint does not accept. Only this server's pinned OIDC ` +
          `client may be used to reach it.`
        : `Token is valid but carries no "client_id" claim. This endpoint ` +
          `requires an access token issued directly to its pinned OIDC ` +
          `client; a token minted for a different flow will not have one.`
    );
    this.name = "ClientNotAllowedError";
    this.presented = clientId;
  }
}

/** The Zitadel scope that adds a project to a token's audience. */
export function audienceScopeFor(projectId: string): string {
  return `urn:zitadel:iam:org:project:id:${projectId}:aud`;
}

/** The complete scope string a client must request to reach this server. */
export function fullScopeString(projectId: string): string {
  return `openid offline_access ${audienceScopeFor(projectId)}`;
}

/**
 * A JWT is three base64url segments separated by dots. Checking the shape
 * before verification lets an opaque token produce a specific diagnosis rather
 * than being reported as a malformed signature.
 */
export function looksLikeJwt(token: string): boolean {
  const parts = token.split(".");
  if (parts.length !== 3) return false;
  return parts.every((part) => /^[A-Za-z0-9_-]+$/.test(part));
}

/** Extracts the credential from an `Authorization: Bearer <token>` header. */
export function extractBearerToken(header: string | undefined): string {
  if (!header) throw new MissingTokenError();
  const match = /^Bearer[ ]+(.+)$/i.exec(header.trim());
  if (!match) throw new MissingTokenError();
  const token = match[1]!.trim();
  if (token.length === 0) throw new MissingTokenError();
  return token;
}

/** Normalises the `aud` claim, which may be a string or an array of strings. */
export function audienceList(payload: JWTPayload): string[] {
  const aud = payload.aud;
  if (typeof aud === "string") return [aud];
  if (Array.isArray(aud)) return aud.filter((a): a is string => typeof a === "string");
  return [];
}


/**
 * jose error codes that mean *we* could not judge the token, rather than that
 * the token is bad.
 *
 * All fourteen of jose's error classes extend `JOSEError`, so "is it a
 * JOSEError" cannot separate a verdict from an inability to reach one — an
 * earlier version used exactly that predicate and sent a JWKS **timeout** back
 * as a 401, telling a caller with a valid token that their credential was bad.
 * That survived its own fix because the repro used an unreachable host, which
 * throws a plain `TypeError` and so took the correct branch by accident.
 *
 * So the classification is explicit and complete. Every code in `jose@6` is
 * listed in one of the two groups below; adding a case means choosing.
 *
 * **IdP-side — 503, the token was never judged:**
 *   ERR_JWKS_TIMEOUT                  the IdP is up but did not answer in time
 *   ERR_JWKS_INVALID                  the IdP served a malformed key set
 *   ERR_JWK_INVALID                   a key within that set is malformed
 *   ERR_JWKS_MULTIPLE_MATCHING_KEYS   the key set is ambiguous for this kid
 *
 * **Verdicts about the presented token — 401:**
 *   ERR_JWS_SIGNATURE_VERIFICATION_FAILED, ERR_JWT_EXPIRED,
 *   ERR_JWT_CLAIM_VALIDATION_FAILED, ERR_JWT_INVALID, ERR_JWS_INVALID,
 *   ERR_JWKS_NO_MATCHING_KEY, ERR_JOSE_ALG_NOT_ALLOWED,
 *   ERR_JOSE_NOT_SUPPORTED, ERR_JWE_INVALID, ERR_JWE_DECRYPTION_FAILED
 *
 * Anything that is not a jose error at all — a bare `TypeError: fetch failed`
 * from an unreachable host — is also IdP-side. An unrecognised failure lands
 * on 503 deliberately: "we could not judge it" is true of every case, whereas
 * a wrong 401 accuses a credential that may be perfectly good.
 */
const IDP_SIDE_JOSE_CODES = new Set([
  "ERR_JWKS_TIMEOUT",
  "ERR_JWKS_INVALID",
  "ERR_JWK_INVALID",
  "ERR_JWKS_MULTIPLE_MATCHING_KEYS",
]);

export function isIdpSideFailure(error: unknown): boolean {
  if (!(error instanceof errors.JOSEError)) return true;
  return IDP_SIDE_JOSE_CODES.has((error as { code?: string }).code ?? "");
}

export interface TokenVerifierConfig {
  /** Zitadel issuer, e.g. https://auth.ipv1337.dev */
  issuer: string;
  /** Zitadel project ID that must appear in the token's audience. */
  projectId: string;
  /**
   * The `sub` values this endpoint serves. Required rather than optional, and
   * deliberately not defaulted: an optional allow-list whose absence means
   * "allow everyone" is the shape that gets forgotten and never noticed,
   * because a working endpoint looks identical either way.
   */
  allowedSubjects: readonly string[];
  /**
   * The OIDC client this server pins itself to (#1491). Required, and
   * deliberately not defaulted: an absent pin must mean "refuse to start",
   * never "accept any client" — the same fail-closed treatment
   * {@link allowedSubjects} gives an unset allow-list.
   */
  allowedClientId: string;
  /** Overridable for tests; defaults to the issuer's standard JWKS path. */
  jwksUri?: string;
  /**
   * Key material to verify against. Defaults to a remote JWKS fetched from
   * {@link jwksUri}. Tests inject a local key so the suite never needs network
   * access; production never sets this.
   */
  keySource?: Parameters<typeof jwtVerify>[1];
  /**
   * How long to wait for the JWKS fetch. jose's default is 5s and is
   * invisible; naming it makes the timeout a decision rather than a default,
   * and lets a test exercise the timeout path without waiting five seconds.
   */
  jwksTimeoutMs?: number;
}

export interface VerifiedCaller {
  /** The `sub` claim — the Zitadel subject that authorised this session. */
  subject: string;
  claims: JWTPayload;
}

export interface TokenVerifier {
  verify(token: string): Promise<VerifiedCaller>;
  verifyAuthorizationHeader(header: string | undefined): Promise<VerifiedCaller>;
}

/**
 * Builds the verifier used by the HTTP transport.
 *
 * The remote JWKS is cached and refreshed by `jose`, so steady-state
 * verification makes no network call.
 */
export function createTokenVerifier(config: TokenVerifierConfig): TokenVerifier {
  const issuer = config.issuer.replace(/\/+$/, "");
  const jwksUri = config.jwksUri ?? `${issuer}/oauth/v2/keys`;
  const jwks =
    config.keySource ??
    createRemoteJWKSet(new URL(jwksUri), {
      timeoutDuration: config.jwksTimeoutMs ?? 5000,
    });
  // Captured once. Same reasoning as the channel guard: no reload path exists,
  // so the set cannot change under an in-flight request.
  const allowedSubjects = new Set(config.allowedSubjects);
  if (allowedSubjects.size === 0) {
    throw new Error(
      "createTokenVerifier requires at least one allowed subject. An empty " +
        "list would authenticate every caller Zitadel is willing to issue a " +
        "token to, which is not the same set as the people this endpoint serves."
    );
  }
  if (!config.allowedClientId) {
    throw new Error(
      "createTokenVerifier requires allowedClientId. An empty value would " +
        "accept a token minted for any OIDC client, which defeats the pin " +
        "this check exists to enforce."
    );
  }

  async function verify(token: string): Promise<VerifiedCaller> {
    if (!looksLikeJwt(token)) throw new OpaqueTokenError();

    let payload: JWTPayload;
    try {
      // algorithms is pinned rather than left to the token's own header.
      // jose already rejects "alg: none" and an asymmetric JWKS cannot be
      // coerced into HMAC, so this is defence in depth rather than a fix —
      // it keeps the accepted set explicit if the IdP's advertised keys ever
      // widen. RS256 is what Zitadel issues.
      //
      // clockTolerance is not optional in practice. jose defaults to zero
      // slack on exp/nbf/iat, and this server and the IdP are separate hosts
      // with independently drifting clocks. Without it, a couple of seconds
      // of drift rejects freshly-issued tokens intermittently — which
      // presents as an auth bug that reproduces only sometimes, the most
      // expensive kind to chase. 30s is small enough not to meaningfully
      // extend a token's life and large enough to cover ordinary NTP drift.
      ({ payload } = await jwtVerify(token, jwks, {
        issuer,
        algorithms: ["RS256"],
        clockTolerance: 30,
      }));
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      throw isIdpSideFailure(error)
        ? new IdpUnavailableError(reason)
        : new InvalidTokenError(reason);
    }

    const audiences = audienceList(payload);
    if (!audiences.includes(config.projectId)) {
      throw new AudienceMismatchError(config.projectId, audiences);
    }

    const subject = typeof payload.sub === "string" ? payload.sub : "";
    if (subject.length === 0) {
      throw new InvalidTokenError("token has no subject (sub) claim");
    }

    // Last, after the signature, issuer and audience have all been checked —
    // so this only ever sees a subject the IdP actually vouched for, and can
    // never be the reason a forged token is accepted.
    if (!allowedSubjects.has(subject)) {
      throw new SubjectNotAllowedError(subject);
    }

    // Pins the caller to this server's own OIDC client (#1491). Checked last
    // — after signature, issuer, audience and subject — so it only ever
    // narrows an identity that has already been fully established, and can
    // never be the reason a forged or misaudienced token is accepted.
    //
    // azp identifies an id_token's authorized party; access tokens carry
    // client_id instead. A token carrying azp at all is not this server's
    // expected shape, so it is rejected outright rather than compared.
    const azp = payload["azp"];
    if (azp !== undefined) {
      throw new AuthorizedPartyPresentError(
        typeof azp === "string" ? azp : JSON.stringify(azp)
      );
    }

    // Fails closed on purpose: `!==` rejects an absent, wrong-type and
    // wrong-value client_id in the same branch. A guard shaped
    // `clientId && clientId !== expected` would let an absent claim skip the
    // check entirely.
    const clientId = payload["client_id"];
    if (clientId !== config.allowedClientId) {
      // Only a genuinely absent claim (undefined) reports as "". A present
      // but wrong-type value is stringified, same as the azp branch above —
      // otherwise "wrong type" collapses into "absent" and the refusal
      // (and the alert annotation that tells an operator how to read it)
      // asserts something false about what the token actually carried.
      throw new ClientNotAllowedError(
        clientId === undefined
          ? ""
          : typeof clientId === "string"
            ? clientId
            : JSON.stringify(clientId)
      );
    }

    return { subject, claims: payload };
  }

  return {
    verify,
    // `async` is load-bearing: extractBearerToken throws, and a Promise-typed
    // method that throws synchronously would slip past a caller's .catch() and
    // escape the boundary handler as an uncaught exception rather than a 401.
    verifyAuthorizationHeader: async (header) => verify(extractBearerToken(header)),
  };
}
