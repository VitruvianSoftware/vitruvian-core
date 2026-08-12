/*
Copyright (c) 2026 VitruvianSoftware

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

// Command revname prints the Cloud Run revision name the tabula app stack WOULD
// deploy for a given env config + image digest, WITHOUT running Pulumi.
//
// The deploy preflight (tools/ci/tabula-deploy-preflight.sh) compares this to
// the live serving revision name: equal means the running service already IS
// the desired state, so the deploy can be skipped. Because it reuses the app
// stack's own revision package, the two can never disagree — a reimplementation
// in bash could, and a wrong "they differ" verdict would skip a real deploy.
//
// It fails LOUD (non-zero, message on stderr, nothing on stdout) on any
// problem, so the preflight treats "cannot compute" as "deploy" — fail-open,
// never a false skip.
//
//	go run ./cmd/revname --config Pulumi.development.yaml \
//	  --digest us-central1-docker.pkg.dev/p/tabula/app@sha256:<hex>
package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/tabula/revision"
	"gopkg.in/yaml.v3"
)

// pulumiStackConfig is the on-disk Pulumi.<env>.yaml shape we need: the flat
// `config:` map, whose keys are namespaced like `tabula-app:project`.
type pulumiStackConfig struct {
	Config map[string]string `yaml:"config"`
}

// The config keys the revision name depends on. SOURCE OF TRUTH for the mapping
// is ../../main.go (cfg.Require/Get on the same names); keep them in sync — the
// hashing itself is already shared via the revision package.
const (
	ns          = "tabula-app:"
	keyProject  = ns + "project"
	keyEnv      = ns + "environment"
	keyAPIURL      = ns + "apiUrl"
	keyPMOrigin    = ns + "authPostmessageOrigin"
	keyCORSOrigin  = ns + "corsOrigin"
)

// computeRevisionName renders the revision name from a Pulumi stack config file
// and an image digest, exactly as the app stack's main() does.
func computeRevisionName(configPath, imageDigest string) (string, error) {
	raw, err := os.ReadFile(configPath)
	if err != nil {
		return "", fmt.Errorf("read %s: %w", configPath, err)
	}
	var sc pulumiStackConfig
	if err := yaml.Unmarshal(raw, &sc); err != nil {
		return "", fmt.Errorf("parse %s: %w", configPath, err)
	}

	// project and environment are Require()d by the app stack — absent means a
	// malformed config, so error (fail-open) rather than emit a partial name.
	project, env := sc.Config[keyProject], sc.Config[keyEnv]
	if project == "" {
		return "", fmt.Errorf("%s: %q is required", configPath, keyProject)
	}
	if env == "" {
		return "", fmt.Errorf("%s: %q is required", configPath, keyEnv)
	}

	shortDigest, err := revision.ShortDigest(imageDigest)
	if err != nil {
		return "", err
	}

	// Mirror main.go exactly: serviceName = tabula-api-<env>, env map from the
	// two optional public config values (absent when unset).
	serviceName := fmt.Sprintf("tabula-api-%s", env)
	env2 := revision.EnvMap(project, sc.Config[keyAPIURL], sc.Config[keyPMOrigin], sc.Config[keyCORSOrigin])
	return revision.Name(serviceName, shortDigest, env2), nil
}

func main() {
	configPath := flag.String("config", "", "path to Pulumi.<env>.yaml")
	digest := flag.String("digest", "", "image digest ref <image>@sha256:<hex>")
	flag.Parse()

	if *configPath == "" || *digest == "" {
		fmt.Fprintln(os.Stderr, "revname: --config and --digest are required")
		os.Exit(2)
	}
	name, err := computeRevisionName(*configPath, *digest)
	if err != nil {
		fmt.Fprintf(os.Stderr, "revname: %v\n", err)
		os.Exit(1)
	}
	fmt.Println(name)
}
