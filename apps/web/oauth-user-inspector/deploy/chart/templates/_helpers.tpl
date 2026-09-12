{{- define "oauth-user-inspector.name" -}}
oauth-user-inspector
{{- end -}}

{{- define "oauth-user-inspector.labels" -}}
app.kubernetes.io/name: {{ include "oauth-user-inspector.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "oauth-user-inspector.selectorLabels" -}}
app.kubernetes.io/name: {{ include "oauth-user-inspector.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
