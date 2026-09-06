# Vitruvian — how to build with this system

Vitruvian is a **dark-first, drafting-table** design language: square corners, one
hairline, a steel-blue accent, red-chalk "sanguine" for danger, and a Fibonacci
spacing ramp. Type is JetBrains Mono for headings, labels, buttons and data;
IBM Plex Sans for prose. The look is a technical drawing, not a consumer app.

## Setup — no provider, no wrapper

There is **no theme provider and no context to set up.** Link `styles.css` and
the ground is already correct: `body` gets the board background and text colour
from `:root`, which carries the **dark** palette by default.

- Dark is the default. Do **not** add a wrapper to get it.
- The light alternate ("parchment") is opt-in: put `data-theme="light"` on
  `<html>` or on any container. There is no `data-theme="dark"` to add.
- `VitruvianGround` appears in the bundle but is **preview scaffolding for the
  design-system pane — never use it in a design.**

## Compose from the components first

Import from the bundle; these all exist:

| Group | Components |
|---|---|
| Frame | `Plate` `RegistrationMarks` `VMark` `Rule` `Glass` |
| Action | `Button` — `variant` primary/secondary/ghost/danger, `size` sm/md, `block`, `icon`, `registered`, `done` |
| Label | `Tag` (`tone`) `Label` (`accent`) `Kbd` |
| Container | `Card` — `kicker` `title` `meta`, `surface` plate/fill/glass, `elevation` sm/md/lg |
| Form | `Field` `Input` `Textarea` `Select` `Checkbox` `Radio` `Switch` `Segmented` |
| Navigation | `Nav` `Tabs` `Shell` `SideGroup` `SideItem` `Crumbs` |
| Data | `Status` `Metric` `Meter` `SegBar` `Spark` `LogStream` `Table` |
| Code | `Terminal` `Code` |
| Overlay | `Dialog` `Banner` `Menu` `MenuItem` `MenuDivider` |
| State | `EmptyState` `Skeleton` `Spinner` |
| Utility | `cn` (class-name joiner) |

`Plate` is the system's frame — square corners, one hairline, four crosshair
registration marks. Every card, figure and panel is one. Reach for it before
drawing a bordered `<div>`.

## The styling idiom — two layers, both real

**1. Semantic component classes** (hand-written CSS, always present). Use these
for anything the DS already names:

`.plate` `.card` `.card-fill` `.glass` `.blueprint` `.rule` `.vm` `.grid-field`
`.btn` `.btn-primary` `.btn-secondary` `.btn-ghost` `.btn-danger` `.btn-block`
`.tag` `.tag-ok` `.tag-warn` `.tag-sanguine` `.tag-accent` `.tag-neutral` `.tag-outline`
`.label` `.kbd` `.mono` `.num` `.dim`
`.field` `.field-error` `.field-hint` `.input` `.select` `.check` `.radio` `.switch` `.seg` `.seg-opt`
`.nav` `.nav-brand` `.nav-links` `.shell` `.shell-side` `.shell-main` `.side-group` `.side-item` `.tabs` `.tab` `.crumbs`
`.status` `.metric` `.metric-value` `.metric-delta` `.meter` `.segbar` `.spark` `.table` `.log` `.log-row` `.log-ts` `.log-lvl`
`.term` `.term-bar` `.term-body` `.term-line` `.code`
`.dialog` `.dialog-backdrop` `.dialog-title` `.dialog-body` `.dialog-actions` `.banner`
`.state` `.state-title` `.state-body` `.skeleton` `.spinner` `.elev-sm` `.elev-md` `.elev-lg`

**2. A Tailwind v4 preset whose palette is renamed to the design language.**
Never use stock Tailwind colour names (`bg-slate-800`, `text-gray-400`) — they
are not in this build. Use these, on `bg-` / `text-` / `border-`:

| Family | Names |
|---|---|
| Grounds | `ink` `ink-2` `ink-3` |
| Ink on ground | `paper` `paper-dim` |
| Lines | `hairline` (dividers) `rule` (fainter) |
| Brand steel | `steel` `steel-text` `steel-quiet` `steel-100`…`steel-900` |
| Red chalk | `sanguine` `sanguine-text` |
| Signal | `ok` `warn` `crit` |

Type: `font-display` `font-body` `font-mono`. Elevation: `shadow-sm/md/lg`.

**Spacing is the Fibonacci sequence, not Tailwind's 0.25rem ramp** — this is
part of the design language, so `p-4` is **13px** and `gap-5` is **21px**:

`0`→0 · `1`→3px · `2`→5px · `3`→8px · `4`→13px · `5`→21px · `6`→34px · `7`→55px · `8`→89px

Applies to every `p/px/py/pt/pr/pb/pl`, `m/mx/my/mt/mr/mb/ml`, `gap`, `space-y/x`.

**Everything is square by construction.** `--radius-*` is 0, so `rounded-md` and
friends exist but do nothing. Do not try to round corners.

## Where the truth lives

Read these before styling — they beat this summary: `_ds/<folder>/styles.css`
and the stylesheet it imports (the full token list and every component class),
and each component's own `<Name>.prompt.md` and `<Name>.d.ts`.

## One idiomatic screen

`Shell` takes the sidebar as a **`side` prop**, not as children. `SideGroup`
renders a group *heading* (its children are the label text); the items are
`SideItem` siblings after it, and the active one gets `current`. `Crumbs` wraps
real anchors rather than taking an array.

```jsx
<Plate className="overflow-hidden">
  <Shell
    side={
      <>
        <SideGroup>Platform</SideGroup>
        <SideItem href="#" current>Overview</SideItem>
        <SideItem href="#">Clusters</SideItem>
        <SideGroup>Delivery</SideGroup>
        <SideItem href="#">Pipelines</SideItem>
      </>
    }
  >
    <Crumbs>
      <a href="#">platform</a> / <span className="dim">edge-01</span>
    </Crumbs>
    <h3 className="my-4">edge-01</h3>

    <div className="grid grid-cols-3 gap-5">
      <Metric label="Uptime" value="99.982%" delta="+0.004" />
      <Metric label="P95 latency" value="214ms" delta="-11ms" down />
      <Metric label="Reconcile" value="86%" />
    </div>

    <Card kicker="01 · Cluster" title="edge-01" className="mt-5">
      <p className="text-paper-dim">Three nodes ready, no drift.</p>
      <div className="flex gap-3 mt-4">
        <Button variant="primary" registered>Deploy</Button>
        <Button variant="danger">Destroy</Button>
      </div>
    </Card>

    <div className="flex gap-5 mt-5">
      <Status signal="ok">3/3 ready</Status>
      <Status signal="run">reconciling</Status>
    </div>
  </Shell>
</Plate>
```

Note the idiom: library components carry the controls; the layout glue is the
DS's own utility vocabulary (`grid-cols-3`, `gap-5`, `text-paper-dim`,
`font-display`) — never stock Tailwind colours, never a rounded corner.
