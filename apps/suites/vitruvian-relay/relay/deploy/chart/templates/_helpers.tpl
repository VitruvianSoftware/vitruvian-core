{{/*
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
*/}}

{{- define "vitruvian-relay.name" -}}vitruvian-relay{{- end -}}

{{- define "vitruvian-relay.labels" -}}
app.kubernetes.io/name: {{ include "vitruvian-relay.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "vitruvian-relay.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vitruvian-relay.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Every value below fails the render when missing rather than defaulting: an
unset client id or subject list must never mean "let everyone in".
*/}}
{{- define "vitruvian-relay.imageRef" -}}
{{- $raw := required "image.digest is required: pin the image by digest, never a tag" .Values.image.digest | toString -}}
{{- $d := regexReplaceAll "^.*@" $raw "" -}}
{{- if not (regexMatch "^sha256:[0-9a-f]{64}$" $d) -}}
{{- fail (printf "image.digest must be \"sha256:<64 hex>\" (optionally \"<tag>@sha256:...\"), never a tag; got %q" $raw) -}}
{{- end -}}
{{ .Values.image.repository }}@{{ $d }}
{{- end -}}

{{/*
Who may sign in: a role (oidc.requiredRole, for the current relay) or a list of
users (oidc.allowedSubjects, the only check the old relay has). Both empty fails
the render: a missing check must never mean "let everyone in".
*/}}
{{- define "vitruvian-relay.whoMaySignIn" -}}
{{- if not (or .Values.oidc.requiredRole .Values.oidc.allowedSubjects) -}}
{{- fail "oidc.requiredRole or oidc.allowedSubjects is required: with neither, every account in the instance would be admitted" -}}
{{- end -}}
{{- end -}}

{{/*
MCP_CLIENT_LABELS: the mcpClientLabels map as Label=<client id>, comma
separated, in label order (so the render is stable).
*/}}
{{- define "vitruvian-relay.mcpClientLabels" -}}
{{- $pairs := list -}}
{{- range $label, $id := .Values.mcpClientLabels -}}
{{- $pairs = append $pairs (printf "%s=%s" $label ($id | toString)) -}}
{{- end -}}
{{- join "," $pairs -}}
{{- end -}}

{{/*
The upstream idle timeout, checked against the relay's own idle close (75 s,
header_read_timeout in src/http.rs): Envoy must drop an idle connection first,
or it reuses one the relay just closed (a 503). Accepts minutes and seconds,
e.g. "60s", "1m", "1m10s"; anything else, zero, or 75 s and up fails the render.
*/}}
{{- define "vitruvian-relay.upstreamIdleTimeout" -}}
{{- $t := required "upstreamIdleTimeout is required: keep it below the relay's 75 s idle close" .Values.upstreamIdleTimeout | toString -}}
{{- if not (regexMatch "^([0-9]+m)?([0-9]+s)?$" $t) -}}
{{- fail (printf "upstreamIdleTimeout must be minutes and/or seconds, like \"60s\" or \"1m10s\"; got %q" $t) -}}
{{- end -}}
{{- $m := regexFind "[0-9]+m" $t | trimSuffix "m" | default "0" | atoi -}}
{{- $s := regexFind "[0-9]+s" $t | trimSuffix "s" | default "0" | atoi -}}
{{- $total := add (mul $m 60) $s -}}
{{- if or (le $total 0) (ge $total 75) -}}
{{- fail (printf "upstreamIdleTimeout must be above 0 and below the relay's 75 s idle close (header_read_timeout); got %q (%d s)" $t $total) -}}
{{- end -}}
{{ $t }}
{{- end -}}
