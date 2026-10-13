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

Go 1.22 or later, and nothing outside Go's standard library. MIT licence.
`toolkit/protocol_gen.go` is written by the SDK's generator from the
protocol's schemas; do not edit it.
