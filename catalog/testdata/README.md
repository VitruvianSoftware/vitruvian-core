# Frozen inputs for //catalog:bump_test

The bump tests run against these copies, never the live files, so a real
catalog update can't break them:

- `tools.json`: the catalog as it was at 0716cc91f (HomeSpeaker 1.19.1,
  GitHub 1.3.0), the versions the tests bump from.
- `sources.json`: `catalog/sources.json` as the tests were written.
- `Info.plist`: an app whose oldest macOS is 14.0.

The tests that must track the live `tools.json`, `sources.json` and the
app's `Info.plist` are `SourcesTest`, `FormatTest` and
`test_the_apps_info_plist_names_an_oldest_macos`.
