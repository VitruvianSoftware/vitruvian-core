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
| `index.markdown`, `about.markdown`, `*.md` | Pages |
| `_posts/` | Blog posts, named `YYYY-MM-DD-title.markdown` |
| `_layouts/`, `_includes/` | Page templates, header and footer |
| `assets/`, `images/`, `js/` | Stylesheet, scripts and images |
| `_config.yml` | Site title, navigation and plugins |
| `.github/workflows/jekyll.yml` | The build-and-deploy workflow that runs in the standalone repository |
