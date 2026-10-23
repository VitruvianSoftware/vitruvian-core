# vitruviansoftware.dev

The public website for Vitruvian Software, live at <https://vitruviansoftware.dev>.
It is a [Jekyll](https://jekyllrb.com/) site: Markdown pages and blog posts, a few
HTML layouts, one stylesheet.

## Where to edit

Edit it in the [vitruvian-core](https://github.com/VitruvianSoftware/vitruvian-core)
monorepo, under `apps/web/vitruviansoftware-dev/`. The
[site-vitruviansoftware-dev](https://github.com/VitruvianSoftware/site-vitruviansoftware-dev)
repository is a read-only copy; changes made there are overwritten.

## How a change goes live

1. A change under `apps/web/vitruviansoftware-dev/` merges to `main` in the monorepo.
2. The `Copybara Export (site-vitruviansoftware-dev)` workflow pushes it to the
   standalone repository.
3. That push starts the standalone repository's `jekyll.yml`, which builds the
   site and deploys it to GitHub Pages.

Expect a few minutes end to end. A green export means the change reached the
standalone repository; the deploy itself is the `jekyll.yml` run there.

## Preview locally

```bash
bundle install
```

```bash
bundle exec jekyll serve
```

Then open <http://localhost:4000>.

## Layout

| Path | What it holds |
|---|---|
| `index.html`, `projects.html`, `ai.html`, `engineering.html`, `blog.html`, `about.html` | Pages |
| `tech-stack.html`, `contributions.html` | Redirects from URLs the previous site used |
| `_data/projects.yml` | Every project card on the site; edit a project here, once. A project with an `extension` block is also listed on `/ai/` |
| `_data/team.yml` | The leadership and team section of the About page: the founder, and the AI agents with their portraits |
| `_posts/` | Blog posts, named `YYYY-MM-DD-title.md`; set `description` for the listing |
| `tools/` | The Tools section. `index.html` is written by hand. `guide.md`, `protocol.md` and `examples/*.md` are copies of `packages/vitruvian-sdk`'s docs and samples, written by `bazel run //tools/sync-site-tools:sync`: do not edit them, and `//tools/sync-site-tools:in_sync_test` fails until they match their sources |
| `_layouts/`, `_includes/` | Page, post and card templates, header, footer, brand mark |
| `assets/css/main.css` | The stylesheet, built on the Vitruvian design tokens |
| `assets/js/main.js` | Theme toggle, mobile menu and the image lightbox |
| `images/` | Blog images and SVG diagrams |
| `_config.yml` | Site title, navigation and plugins |
| `AGENTS.md` | Conventions for agents editing the site, including the image standard |
| `.github/workflows/jekyll.yml` | The build-and-deploy workflow that runs in the standalone repository |

## Images

Every image in a blog post or Tools page opens full size when clicked, or when
focused and Enter is pressed: a viewer with the caption, a zoom toggle and a link
to the original file. Nothing to add per image. Put the image on its own line and
the caption in italics on the next line:

```markdown
![What the diagram shows](/images/my-diagram.svg)
*Figure 1: What the reader should take from it.*
```

Images inside a link, tiny icons, and anything marked `data-no-lightbox` are left
alone. Prefer SVG for diagrams. The full standard, including `<figure>` and how
to opt in outside a post, is in [`AGENTS.md`](AGENTS.md#images-the-standard).

## Constraints

Production builds with `actions/jekyll-build-pages`, which uses the
`github-pages` gem: Jekyll 3, safe mode, whitelisted plugins only. So:

- the stylesheet is plain CSS, not Sass, because that gem's Sass compiler
  rejects modern CSS;
- no custom plugins (redirects are plain HTML pages for that reason);
- colours, type and spacing come from
  [`packages/design-system/src/tokens.css`](../../../packages/design-system/src/tokens.css).
  Keep the copies in `main.css` in step when the tokens change.
