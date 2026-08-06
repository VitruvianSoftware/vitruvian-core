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

{{- define "mcp-slack.name" -}}mcp-slack{{- end -}}

{{- define "mcp-slack.labels" -}}
app.kubernetes.io/name: {{ include "mcp-slack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "mcp-slack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mcp-slack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Required-value helpers.

Every one of these guards a security property, so each fails the render rather
than defaulting. The reasoning is the same one this deployment's design rests
on throughout: a value the chart cannot interpret must never resolve to the
permissive case. An unset allow-list is not "allow everything", and an unset
project id is not "skip the audience check" — both are refusals.

`required` is deliberate over `default`: a default here would produce a
deployment that renders, syncs, reports Healthy, and is wrong.
*/}}

{{- define "mcp-slack.imageRef" -}}
{{- $d := required "image.digest is required — pin the image by digest, never a tag. An internet-facing workload must run the artifact that was reviewed, not whatever the tag points at today." .Values.image.digest -}}
{{ .Values.image.repository }}@{{ $d }}
{{- end -}}

{{- define "mcp-slack.projectId" -}}
{{ required "oidc.projectId is required — take it from `pulumi stack output projectId` on the zitadel-apps-mcp-slack stack. It is the audience the server validates against, so a wrong or absent value is the boundary, not a setting." .Values.oidc.projectId }}
{{- end -}}

{{- define "mcp-slack.allowedSubjects" -}}
{{ required "oidc.allowedSubjects is required — comma-separated Zitadel subjects (numeric user ids). This is the only identity check made per request; the audience check is not one, because `aud` is caller-authored and every account this instance issues a token to can put this project in it. Refusing to render is correct: an empty subject list would admit the whole instance, which today is anyone who can self-register." .Values.oidc.allowedSubjects }}
{{- end -}}

{{- define "mcp-slack.channelIds" -}}
{{ required "slack.channelIds is required — this is the channel allow-list and it is the only thing bounding which conversations a caller can reach. Refusing to render is correct; an empty allow-list would expose every channel the bot belongs to." .Values.slack.channelIds }}
{{- end -}}

{{/*
The in-process shutdown budget, in milliseconds, derived from the pod's
terminationGracePeriodSeconds so the two cannot drift apart.

Guarded rather than computed blindly. A grace period of 2s or less yields a
zero or negative budget, which would either disable the drain or be coerced
into something meaningless — the fail-open-on-an-uninterpretable-value shape
this chart refuses everywhere else. Refusing to render is the honest outcome.
*/}}
{{- define "mcp-slack.shutdownGraceMs" -}}
{{- $g := int .Values.terminationGracePeriodSeconds -}}
{{- if lt $g 3 -}}
{{- fail (printf "terminationGracePeriodSeconds is %d, which leaves no room for the in-process drain. SHUTDOWN_GRACE_MS is derived as (grace - 2s); at %ds that is zero or negative, so the drain would be disabled while appearing configured. Use at least 3." $g $g) -}}
{{- end -}}
{{- mul (sub $g 2) 1000 -}}
{{- end -}}
