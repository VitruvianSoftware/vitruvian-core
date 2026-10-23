# vitruviansoftware.dev — agent guide

> Scoped to `apps/web/vitruviansoftware-dev/`. Repo-wide rules live in the root
> [`AGENTS.md`](../../../AGENTS.md); the developer SOP is [`CONTRIBUTING.md`](../../../CONTRIBUTING.md),
> which wins on any conflict. How the site is built, previewed and deployed is in
> [`README.md`](README.md).

## The essentials

- Plain Jekyll 3 under the `github-pages` gem: no plugins beyond the whitelisted
  ones in `_config.yml`, no Sass. One stylesheet (`assets/css/main.css`), one script
  (`assets/js/main.js`), both with zero dependencies. Keep it that way.
- Colours, type and spacing come from the design-system tokens copied at the top of
  `main.css`. Use the variables (`--color-*`, `--space-*`, `--font-*`), never a raw value.
- Every new file at this level that is not part of the site (like this one) must be
  listed under `exclude:` in `_config.yml`, or Jekyll publishes it.
- Check a change in both themes (the moon/sun toggle) and at phone width before
  calling it done.

## Images: the standard

Every content image on the site can be clicked, tapped, or focused and opened with
Enter or Space, to see it full size. You do not wire this up per image. It follows
from where the image sits.

**What gets the lightbox, automatically:**

- any image inside `.prose`, which is every blog post and every Tools page;
- any `<img data-lightbox>`, anywhere;
- any image inside an element marked `data-expandable`, anywhere.

**What never does:**

- an image inside a link (`<a>`): the link wins;
- an image with `data-no-lightbox`, or inside an element that has it;
- a tiny image, under 96px wide (icons, avatars, logos), unless it says
  `data-lightbox` explicitly.

**Write a figure like this** — the image on its own line, the caption in italics on
the very next line, no blank line between:

```markdown
![Short description of the diagram](/images/my-diagram.svg)
*Figure 1: One or two plain sentences on what the reader should take from it.*
```

Or, in HTML:

```html
<figure>
  <img src="/images/my-diagram.svg" alt="Short description of the diagram">
  <figcaption>Figure 1: What the reader should take from it.</figcaption>
</figure>
```

Either shape becomes a **figure plate**: wider than the text column on a big screen
(up to 960px), on a surface with a hairline and corner marks, caption centred below
in mono. The lightbox picks the caption up by itself, in this order: the
`<figcaption>`; the italic line right after the image; an italic-only paragraph
right after an image-only paragraph; and last, the alt text. So always write real
alt text. It is the screen-reader label (`Expand image: <alt>`) and the fallback
caption.

**Diagrams.** Prefer SVG. Give the root `<svg>` a `viewBox` and `width="100%"`, as
the diagrams in `images/` do. The lightbox sizes an SVG from its shape, not its
reported size, so it fills the viewer crisply at any width, and offers *Zoom 2×*
for dense ones. Raster images (PNG, JPG) are never enlarged past their own pixels;
they get a *1:1* button when the screen shows them smaller than that. Export
screenshots at 2× so 1:1 is worth having.

**Opting out**, for a decorative mark or a picture that should stay put:

```html
<img src="/assets/img/mark.svg" alt="" data-no-lightbox>
```

In Markdown, the same through a kramdown attribute list:

```markdown
![](/assets/img/mark.svg){: data-no-lightbox="" }
```

**Opting in** outside `.prose`, for a page that draws its own layout:

```html
<img src="/images/screenshot.png" alt="The settings window" data-lightbox>
<div data-expandable> … any images in here … </div>
```

## How the lightbox works

It lives in `assets/js/main.js` (the block headed *Image lightbox*) and the
`lightbox` section of `assets/css/main.css`. It is one native `<dialog>`, built on
first use and reused:

- `showModal()` traps focus and puts it on *Close*; Escape, a click on the backdrop
  or *Close* shuts it, and focus returns to the image that opened it. The page
  behind does not scroll while it is open.
- The toolbar has the zoom toggle (when zooming would show more), *Open original*
  (the file itself, new tab) and *Close [Esc]*. Clicking the image also toggles zoom.
- It respects `prefers-reduced-motion` (no open animation), and is hidden when
  printing. Browsers without `<dialog>` simply do not get the behaviour; images stay
  as they are.

If you change it, check by hand in a browser: a blog post with an SVG diagram and
one with a JPG; open each by click and by keyboard; Escape; both themes; phone width.
