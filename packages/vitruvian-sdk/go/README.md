# The Vitruvian tool kit, in Go

```sh
go get github.com/VitruvianSoftware/vitruvian-sdk/go
```

```go
tool := toolkit.New("0.1.0")
tool.Command("hello", func(ctx context.Context, app *toolkit.App) error {
	return app.Notify.HUD("Hello", "hand.wave")
})
tool.Run()
```

Package `toolkit` writes a [Vitruvian](https://vitruviansoftware.dev) tool
in Go: declare commands, handle them, call the app. A tool is a program the
Vitruvian app starts and talks to over its standard input and output. It is
trusted like an app: it runs as you, with every permission Vitruvian has.
The guide and the protocol are in `../docs` and `../protocol`;
`vitruvian-tool init --template go` starts a new tool.

A tool of protocol 2 draws, with package `toolkit/ui`. `app.UI.Status` sets
the small mark the app draws on the closed island, and `ui.Choice` is a
pop-up menu on a page. Those two are newer than protocol 2 itself:
`app.Supports(toolkit.FeatureChoice)` says whether this app has one. On an
app from before them `Status` sends nothing and gives false, and a choice is
drawn as its fallback text, so send a `ui.Field` there instead.
`toolkit.StatusOptions{Activity: "3"}` puts a few words beside the mark, and
`Since: time.Now()` a count of seconds the app keeps, when the manifest's
status says `"activity": true`. An app before 3.50 does not have
`toolkit.FeatureStatusActivity`; the status is sent to it without them.

`ui.Chips` is a list of options, each a `toolkit.UIChipOption` with a
`Value`, a `Title` and whether it is `On`, any number of them on at once;
turning one is the event change, and `PanelEvent.Values` gives the value of
every option then on. `ui.HeadingOptions{Section: true}` starts a section of
the page, and `Help` in the options of `ui.Toggle`, `ui.Field`, `ui.Choice`
and `ui.Chips` is a line under the control. An app without
`toolkit.FeatureChips` draws chips as their fallback text, so send a
`ui.Toggle` for each option there; an app without `toolkit.FeatureSections`
ignores a section and help, so send the help as a `ui.Text` there.

`app.Notify.ShowNotice(title, detail, icon, system)` shows a line in the
island, and with system true a macOS notification too; it needs `notify` in
`uses`. An app without `toolkit.FeatureNotice` gets the title as `notify/hud`
instead. A tool whose manifest declares `contributes.slot` is told where its
slot is through `tool.OnSlot`, and `app.UI.DockToSlot()` asks the app to show
it; to an app without `toolkit.FeatureSlot` it sends nothing and gives false.
`"picker": "folder"` on a text preference adds a Choose… button that picks a
folder; an app without `toolkit.FeatureFolderPicker` draws a plain field.

Go 1.22 or later, and nothing outside Go's standard library. MIT licence.
`toolkit/protocol_gen.go` is written by the SDK's generator from the
protocol's schemas; do not edit it.
