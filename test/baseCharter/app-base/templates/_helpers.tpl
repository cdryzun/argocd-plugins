{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "app-base.fullname" -}}
{{- default .Release.Name .Values.appName | trunc 63 | trimSuffix "-" }}
{{- end }}


{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "app-base.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "app-base.group" -}}
{{- if .Values.appGroups }}
{{- printf "%s-%s" .Values.appGroups .Release.Namespace }}
{{- else }}
{{- if .Values.appName -}}
{{- printf "%s-%s" .Values.appName .Release.Namespace }}
{{- else }}
{{- printf "%s-%s" .Release.Namespace .Release.Namespace }}
{{- end}}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "app-base.labels" }}
{{- $helmChart := include "app-base.chart" $ -}}
{{- $app := include "app-base.fullname" $ -}}
{{- $groups := include "app-base.group" $ -}}
{{- $labels := dict "helm.sh/chart" $helmChart "app" $app "group" $groups -}}
{{ merge .extraLabels $labels | toYaml | indent 4 }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "app-base.selectorLabels" -}}
app: {{ include "app-base.fullname" . }}
groups: {{ include "app-base.group" . }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "app-base.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "app-base.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}


{{/*
Renders a value that contains template.
Usage:
{{ include "app-base.tplValue" ( dict "value" .Values.path.to.the.Value "context" $) }}
*/}}
{{- define "app-base.tplValue" -}}
    {{- if typeIs "string" .value }}
        {{- tpl .value .context }}
    {{- else }}
        {{- tpl (.value | toYaml) .context }}
    {{- end }}
{{- end -}}