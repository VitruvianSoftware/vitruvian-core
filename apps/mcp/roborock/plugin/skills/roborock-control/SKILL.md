---
name: roborock-control
description: Check on or control the Roborock vacuum. Use when the user asks what the vacuum is doing, where it is, how much battery it has, or wants to start, pause, resume or stop cleaning, clean specific rooms, send it back to the dock, wash the mop, or see the map.
---

# Roborock control

## Always start with status

Call `get_status` before acting. It tells you three things that decide what to do:

- `authenticated: false`: nobody is logged in. Use the roborock-setup skill first.
- `connected: false`: the vacuum cannot be reached. Say so; commands will fail.
- `state`, `battery`, `error`, `rooms`: what it is doing and what you can ask of it.

## Tools

| The user wants | Call |
|---|---|
| What is it doing / battery / errors | `get_status` |
| Clean everywhere | `start_clean` |
| Clean certain rooms | `start_clean` with `rooms` set to names from `get_status` |
| Pause, resume, stop | `control` with `action` |
| Find the vacuum (it speaks) | `control` with `action: "find"` |
| Send it home | `return_to_dock` |
| Wash the mop | `wash_mop` |
| See the map | `get_map` |

## Getting it right

- **Room names must match.** Use the names in `get_status.rooms` exactly as given. If
  the user names a room that is not there, list the real ones and ask.
- **Resume, not start, after a pause.** `start_clean` on a paused vacuum begins a new
  whole-home clean and discards the room selection. Use `control` with `resume`.
- **Report errors in plain words.** If `error` is set (stuck, bin full, brush
  jammed), tell the user what the vacuum needs before trying anything else.
- **Confirm the effect.** After a command, call `get_status` again and tell the user
  the new state rather than assuming it worked. It can take a few seconds to change.
- **Mop washing needs the right dock.** If `wash_mop` is refused, the dock has no
  washer; say so rather than retrying.

For a live view the user can run `rrctl dashboard` in a terminal.
