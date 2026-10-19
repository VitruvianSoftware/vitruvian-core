module example.com/hello-panel-go

go 1.22

require github.com/VitruvianSoftware/vitruvian-sdk/go v1.8.0 // x-release-please-version

// The kit beside it, in this repository and in the published mirror. A
// tool of your own requires a released version instead:
// vitruvian-tool init --template go writes that.
replace github.com/VitruvianSoftware/vitruvian-sdk/go => ../../go
