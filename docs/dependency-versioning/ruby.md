# Ruby dependency versions

See [Dependency Versioning & the One Version Rule](index.md) for the concepts referenced here.

## How this repo resolves them

Ruby gems are managed by `rules_ruby` via Bundler, from a single `Gemfile` and its
`Gemfile.lock`. This is a **flat** resolver in the strictest sense: Bundler resolves the entire
gem graph to exactly one version per gem, or it refuses to resolve at all.

## Two apps, different versions

You can't, within one bundle. If two apps need incompatible versions of a gem, `bundle install`
fails with a resolution error — there is no nesting. A lagging transitive gem that caps a
version blocks the whole bundle until it's relaxed.

This is the bluntest of the flat resolvers: the conflict is loud and immediate, which is
arguably a feature (no silent runtime surprise).

## If you truly need different versions

Bundler's model is one bundle = one version set, so isolation means a **separate bundle**: give
the divergent app its own `Gemfile`/`Gemfile.lock` and its own `bundle install`, kept out of the
shared bundle. The two apps then resolve independently. If they must run in the same Ruby
process, there's no supported way to load two versions of one gem — converge instead.

## Inspect / detect

```bash
# Why is a gem in the bundle, and at what version?
bundle why <gem>            # (bundler-why), or:
bundle show <gem>

# Inspect the resolved version directly
grep -A2 "<gem> " Gemfile.lock
```
