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

Go 1.22 or later, and nothing outside Go's standard library. MIT licence.
`toolkit/protocol_gen.go` is written by the SDK's generator from the
protocol's schemas; do not edit it.
