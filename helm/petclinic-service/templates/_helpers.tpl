{{/*
Common labels applied to every resource in this chart.
The release name IS the service name (e.g. customers-service).
*/}}
{{- define "petclinic-service.labels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/part-of: petclinic
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/component: {{ .Values.component }}
{{- end }}

{{/*
Selector labels — stable subset used for Service selectors and HPA/PDB references.
Only app.kubernetes.io/name so selectors survive label additions.
*/}}
{{- define "petclinic-service.selectorLabels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
{{- end }}
