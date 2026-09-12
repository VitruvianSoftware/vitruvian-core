{{- define "tabula.name" -}}
tabula
{{- end -}}

{{- define "tabula.labels" -}}
app.kubernetes.io/name: {{ include "tabula.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "tabula.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tabula.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
