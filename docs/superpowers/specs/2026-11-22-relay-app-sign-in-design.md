---
status: approved
---

# Relay app sign-in: Gemini for any invited person

## Why

An invited person should connect Gemini by pasting one URL. Today Zitadel must
list every Gemini callback exactly, and Gemini has a different callback for each
Google user and each URL, so every new person or computer needs a config change
and a shared client secret.

## Goals

- Gemini connects with only the URL: no client id, no secret, no config change.
- An invite (the `relay-user` role) stays the only way in.
- Claude's working connector does not change.

## Non-goals

- ChatGPT (the design leaves room; it is not enabled or tested).
- Open sign-up, or a change to how invites are granted.
- One URL per account.

## Anti-goals

- Anyone on the internet creating clients in Zitadel.
- A link that gets a signed-in person to hand their computer to someone else's
  Gemini without being asked.

## What we measured (2026-11-22, throwaway probe, real Gemini web app)

With client id and secret blank, Gemini:

1. reads the protected-resource and authorization-server metadata;
2. shows its consent screens;
3. `POST /register` with `client_name: "Google"`, `token_endpoint_auth_method:
   client_secret_post`, `grant_types: [authorization_code, refresh_token]` and
   **six** redirect URIs: hosts `oauth-redirect`, `oauth-redirect-sandbox`,
   `oauth-redirect-test` (`.googleusercontent.com`), each with
   `/r/user_bound_custom-mcp-<24 hex>` and `/a/...`, one shared id;
4. opens `/authorize` with PKCE S256, `resource`, `state`, and the production
   `/r/` callback.

Not measured: Gemini's `/token` and refresh calls (the probe stopped at
`/authorize`). The first real sign-in proves them.

Desktop Commander's public metadata shows the same shape: its server is its own
authorization server with a `/register` endpoint.

## Approaches

1. **Sign-in layer in the relay (chosen by James).** The relay registers apps
   itself and sends people through Zitadel on one fixed callback.
2. Dashboard creates a Zitadel client per person. Safe, but the person copies
   values back and forth, so it does not "just work".
3. Zitadel open registration. Rejected: anyone could create clients on the
   identity system that protects other apps.

## Design

**A second URL for apps that register themselves.** `/mcp/app/<device>` behaves
exactly like `/mcp/d/<device>`, except its protected-resource metadata names the
relay as the authorization server. `/mcp/d/` keeps naming Zitadel, so Claude is
untouched. `vrelay login` and the dashboard show the right URL for each app.

**Registration holds no state.** `POST /register` accepts only a request whose
redirect URIs are all in Google's six forms above with one shared id. The
`client_id` is that id plus an HMAC; the `client_secret` is an HMAC of the
`client_id`. Nothing is stored, so open registration cannot fill a table. The key
is a new sealed secret. Rate-limited per IP.

**Only the production `/r/` callback is ever used.** Sandbox and test forms are
accepted at registration, because Gemini sends them all and rejects a partial
answer, and refused at `/authorize`.

**Sign-in.** `/authorize` checks the client, callback, PKCE S256 and that
`resource` is this relay's `/mcp/app/<device>` URL, then sends the person to
Zitadel through one new public client (`relay-apps`, PKCE, no secret, like the
dashboard's) with one fixed callback, `<public url>/oauth/callback`.

**A consent page is required.** After Zitadel, the relay shows who is signed in,
the app, the callback's id and the computer, with Allow and Deny (CSRF-protected,
no JavaScript, like the dashboard). Without it, an attacker with their own Gemini
could send an invited person a link and receive access to that person's computer.
The computer must belong to the signed-in person, or the answer is the same as
for an unknown device.

**Tokens.** The relay's one-time code (60 s, bound to client, callback, PKCE and
resource) is redeemed at `/token`. The access token is Zitadel's own, so the
existing verifier checks it, with the new client id added to its allowed list.
The refresh token is sealed (AEAD) with the client id inside, so one client
cannot use another's. Removing someone's role takes effect as with every token.

**In memory.** Pending sign-ins and codes live in memory: the relay is one
replica, and a restart mid-sign-in only means trying again. Both are bounded.

**Rollout.** Expand/contract: a new Zitadel client, a sealed secret, then a chart
switch that defaults off. Turning it on is a values change.

## Done when

- A second, non-admin test user with the role connects Gemini using only the URL
  and makes a call.
- The same user without the role is refused.
- A link started by another Gemini account stops at the consent page, and Deny
  sends no code.
- One person's token cannot reach another person's computer through `/mcp/app/`.
- Claude's connector still works, unchanged.

## Left to the builder

Module layout, exact error bodies, rate-limit numbers, and in-memory bounds.
