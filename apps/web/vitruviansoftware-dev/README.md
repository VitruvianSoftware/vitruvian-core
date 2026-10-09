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
| `index.html`, `projects.html`, `engineering.html`, `blog.html`, `about.html` | Pages |
| `tech-stack.html`, `contributions.html` | Redirects from URLs the previous site used |
| `_data/projects.yml` | Every project card on the site; edit a project here, once |
| `_posts/` | Blog posts, named `YYYY-MM-DD-title.md`; set `description` for the listing |
| `_layouts/`, `_includes/` | Page, post and card templates, header, footer, brand mark |
| `assets/css/main.css` | The stylesheet, built on the Vitruvian design tokens |
| `assets/js/main.js` | Theme toggle and mobile menu |
| `_config.yml` | Site title, navigation and plugins |
| `.github/workflows/jekyll.yml` | The build-and-deploy workflow that runs in the standalone repository |

## Constraints

Production builds with `actions/jekyll-build-pages`, which uses the
`github-pages` gem: Jekyll 3, safe mode, whitelisted plugins only. So:

- the stylesheet is plain CSS, not Sass, because that gem's Sass compiler
  rejects modern CSS;
- no custom plugins (redirects are plain HTML pages for that reason);
- colours, type and spacing come from
  [`packages/design-system/src/tokens.css`](../../../packages/design-system/src/tokens.css).
  Keep the copies in `main.css` in step when the tokens change.
