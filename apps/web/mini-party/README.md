# Mini Party

Thirteen rapid-fire party mini-games for 2–4 players. Play on one shared
screen (each player gets a corner to tap), or start a remote room and share
the link so everyone plays from their own phone.

The games: ZAP!, BOOST!, ECHO!, PINPOINT!, GLANCE!, SNIPE!, TUG!, STABLE!,
COLOR!, PUMP!, SEARCH!, AVOID! and SMASH!.

Play it at **https://mini-games.vitruviansoftware.dev**.

Originally built in Google AI Studio; this folder in
[vitruvian-core](https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/web/mini-party)
is the source of truth. [VitruvianSoftware/mini-party](https://github.com/VitruvianSoftware/mini-party)
is a read-only mirror of it, updated on every change.

## Run it

In vitruvian-core:

```sh
bazel run //apps/web/mini-party:serve          # http://localhost:3000
PORT=8080 bazel run //apps/web/mini-party:serve
```

In the standalone mirror:

```sh
npm install
npm run dev     # http://localhost:3000
```

## How it fits together

- `src/` is the React client. `App.tsx` runs the round loop
  (lobby → game intro → play → scoreboard); each game in `src/games/` reports
  its winners back to it.
- `server.ts` serves the built client and hosts the remote rooms.
- `server/gameServer.ts` is the room relay: up to 4 players per room, seats
  reused when someone leaves, and game events forwarded to the other players.
  Rooms live in memory, so they vanish when the server restarts.

## Checks

```sh
bazel test //apps/web/mini-party/...   # type-check, room server, static build
bazel build //apps/web/mini-party:build          # with online rooms
bazel build //apps/web/mini-party:build_static   # the GitHub Pages build
```

## Where it is published

The mirror publishes itself with GitHub Pages: its
`.github/workflows/pages.yml` builds the client and deploys it to
mini-games.vitruviansoftware.dev. Pages serves files only, with no server, so
that build sets `VITE_REMOTE_PLAY=off` and the site offers shared-screen play
only. Online rooms need `server.ts` running somewhere, which is not set up yet.

The domain's DNS record and the mirror's Pages setting are code in
`infrastructure/pulumi/platform/repo-config` (`internal/site_domain` and
`internal/copybara_sync`).
