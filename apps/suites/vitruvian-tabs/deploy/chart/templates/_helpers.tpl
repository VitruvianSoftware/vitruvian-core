{{- define "vitruvian-tabs.name" -}}
vitruvian-tabs
{{- end -}}

{{- define "vitruvian-tabs.labels" -}}
app.kubernetes.io/name: {{ include "vitruvian-tabs.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "vitruvian-tabs.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vitruvian-tabs.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
