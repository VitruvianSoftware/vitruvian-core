---
name: roborock-setup
description: Connect the Roborock vacuum for the first time, or fix a login that stopped working. Use when the user wants to set up, log in to, or reconnect their Roborock, or when a roborock tool reports authenticated=false or "not logged in".
---

# Roborock setup

The vacuum is reached through the user's Roborock cloud account. Logging in takes
their account email and a code that Roborock emails them. No password is involved.

## Steps

1. Call `get_status`. If it reports `authenticated: true`, there is nothing to set
   up: tell the user and stop. If `connected` is false there, the login is fine and
   the vacuum itself is unreachable (see Troubleshooting).
2. Ask the user for the email address on their Roborock account.
3. Call `setup_login` with only `email`. Roborock emails them a verification code.
4. Ask the user for the code. Do not guess it and do not ask for a password.
5. Call `setup_login` again with `email` and `code`.
6. Call `get_status` to confirm `authenticated: true`. The first connection can take
   ten to twenty seconds; if `connected` is still false, wait and call it once more.

Steps 3 and 5 must happen in the same session: the code only works for the session
that requested it. If the session restarted in between, start again from step 3.

## What gets stored

The login is saved to `~/.config/vitruvian/roborock/credentials.json`, readable only
by the user. If they already used the `roborock` command-line tool, its login in
`~/.roborock` is picked up automatically and no setup is needed.

## Troubleshooting

| What the tool says | What to do |
|---|---|
| Code wrong or expired | Request a new code (step 3). |
| Requested too recently / rate limited | Wait a minute before asking for another code. |
| Accept the user agreement | The user must open the Roborock phone app and accept the updated terms, then retry. |
| `daemon_unavailable` | Ask the user to run `rrctl daemon start` in a terminal and share any error. |
| `authenticated: true`, `connected: false` | The vacuum is offline or the cloud is unreachable. Check it has power and Wi-Fi. |

The user can do all of this themselves in a terminal with `rrctl setup`.
