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
- `server.ts` serves the built client (when there is one) and hosts the
  remote rooms, plus `/healthz`.
- `server/gameServer.ts` is the room relay: up to 4 players per room, seats
  reused when someone leaves, and game events forwarded to the other players
  in the sender's room only.

## Checks

```sh
bazel test //apps/web/mini-party/...   # type-check, room server, static build
bazel build //apps/web/mini-party:build          # with online rooms
bazel build //apps/web/mini-party:build_static   # the GitHub Pages build
bazel build //apps/web/mini-party:server_bundle  # the rooms server, as the image runs it
```

## Where it is published

```
browser ── the game ──────► GitHub Pages            mini-games.vitruviansoftware.dev
        └─ online rooms ──► homelab rooms server    mini-games-rooms.vitruviansoftware.dev
```

- **The game** is static. The mirror's `.github/workflows/pages.yml` builds
  it and GitHub Pages serves it. Shared-screen play needs nothing else.
- **Online rooms** need `server.ts`, which Pages cannot run. The Pages build
  sets `VITE_ROOMS_URL` so the game connects to the rooms server on the
  homelab cluster instead. If the homelab is down, only online rooms stop.
- **The rooms server** is this folder's `Dockerfile`: the socket.io relay and
  `/healthz`, without the client. `mini-party-image.yaml` builds it on `main`,
  argocd-image-updater opens a digest-bump PR, and ArgoCD runs it from
  `gitops/argocd/platform/mini-party` behind the Cloudflare tunnel. It
  accepts connections only from the game's own site (`ALLOWED_ORIGINS`) and
  limits rooms, connections, message size and message rate
  (`server/gameServer.ts`, `DEFAULT_LIMITS`). Rooms live in memory, so a
  redeploy ends games in progress.

The domain's DNS record and the mirror's Pages setting are code in
`infrastructure/pulumi/platform/repo-config` (`internal/site_domain` and
`internal/copybara_sync`); the rooms server's record is the `DNSEndpoint` in
`gitops/argocd/platform/mini-party`.

HTTPS is forced: `http://` redirects to `https://`. GitHub turned that on by
itself when the domain was reattached on 2026-11-19, so the code's
`PagesHTTPS` still reads false. Leave it: the Pages provider removes the custom
domain on any update that leaves the domain unchanged; see the warning above
`NewRepositoryPages` in `internal/copybara_sync/sync.go`.

## Checks

```sh
bazel test //apps/web/mini-party/...   # type-check, room server, static build
bazel build //apps/web/mini-party:build          # with online rooms
bazel build //apps/web/mini-party:build_static   # the GitHub Pages build
bazel build //apps/web/mini-party:server_bundle  # the rooms server, as the image runs it
```
