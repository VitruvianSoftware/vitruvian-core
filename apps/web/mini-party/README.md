# Mini Party

Thirteen rapid-fire party mini-games for 2–4 players. Play on one shared
screen (each player gets a corner to tap), or start a remote room and share
the link so everyone plays from their own phone.

The games: ZAP!, BOOST!, ECHO!, PINPOINT!, GLANCE!, SNIPE!, TUG!, STABLE!,
COLOR!, PUMP!, SEARCH!, AVOID! and SMASH!.

Originally built in Google AI Studio; this folder is now the source of truth.

## Run it

```sh
bazel run //apps/web/mini-party:serve          # http://localhost:3000
PORT=8080 bazel run //apps/web/mini-party:serve
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
bazel test //apps/web/mini-party/...   # type-check + room server tests
bazel build //apps/web/mini-party:build
```

Not deployed anywhere yet.
