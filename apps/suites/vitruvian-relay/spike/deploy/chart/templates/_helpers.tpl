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
*/}}

{{- define "vitruvian-relay-spike.name" -}}vitruvian-relay-spike{{- end -}}

{{- define "vitruvian-relay-spike.labels" -}}
app.kubernetes.io/name: {{ include "vitruvian-relay-spike.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "vitruvian-relay-spike.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vitruvian-relay-spike.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Every value below fails the render when missing rather than defaulting: an
unset client id or subject list must never mean "let everyone in".
*/}}
{{- define "vitruvian-relay-spike.imageRef" -}}
{{- $raw := required "image.digest is required: pin the image by digest, never a tag" .Values.image.digest -}}
{{- $d := regexReplaceAll "^.*@" $raw "" -}}
{{ .Values.image.repository }}@{{ $d }}
{{- end -}}
