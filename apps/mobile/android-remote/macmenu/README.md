# Vitruvian Remote menu bar app

A small macOS menu bar app for the [Mac agent](../macagent/README.md). The
agent runs hidden in the background; this app lets you see it and steer it
without a terminal. It is a separate app from HomeSpeaker on purpose.

## What it shows

- **Whether the agent is up**: running with its version, running with stale
  readings, not responding, or not installed. The icon fades when the agent
  isn't healthy, so a glance at the menu bar is enough.
- **The phone**: connected (model and since when), paired but not connected,
  or not paired.
- **Push notifications**: on, off, or not set up.

It refreshes every five seconds from the agent's read-only endpoints
(`/healthz` and `/v1/phone` on `127.0.0.1:7411`).

## What it does

| Menu item            | What happens                                                                 |
| -------------------- | ---------------------------------------------------------------------------- |
| Pair a Phone…        | Asks for the six-digit code the phone shows, then runs the agent's `pair`.   |
| Restart Agent        | `launchctl kickstart -k`, which keeps the agent's installed flags.           |
| Open Agent Log       | Opens `~/Library/Logs/vitruvian-remote-agent.log` in Console.                |
| Unpair All Phones…   | After a confirmation, runs `token --rotate`. Every phone must pair again.    |
| Open at Login        | Registers the app as a login item.                                           |
| Copy Install Command | Shown only when the agent isn't installed.                                   |

## Security

The app holds no token. It reads only the agent's unauthenticated endpoints,
and pairing and unpairing run the agent's own command-line tool. Unpairing
prints the new token to the tool's output; the app throws that away and
never shows it.

## Install

```sh
bazel run --config=macos-app //apps/mobile/android-remote/macmenu:install
```

That builds the app, puts it in `/Applications`, and opens it. Install the
agent first with `//apps/mobile/android-remote/macagent:install`.

## Tests

```sh
bazel test --config=macos-app //apps/mobile/android-remote/macmenu:RemoteMenuTests //apps/mobile/android-remote/macmenu:paths_match_installer_test
```

The second test fails when the agent's installer and this app disagree about
where the agent lives, so the menu can't quietly report "not installed" about
an agent that is running fine.
