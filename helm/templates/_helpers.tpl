{{/*
Expand the name of the chart.
*/}}
{{- define "wordpress.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "wordpress.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "wordpress.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "wordpress.labels" -}}
helm.sh/chart: {{ include "wordpress.chart" . }}
{{ include "wordpress.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "wordpress.selectorLabels" -}}
app.kubernetes.io/name: {{ include "wordpress.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
MariaDB labels
*/}}
{{- define "wordpress.mariadb.labels" -}}
helm.sh/chart: {{ include "wordpress.chart" . }}
{{ include "wordpress.mariadb.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
MariaDB selector labels
*/}}
{{- define "wordpress.mariadb.selectorLabels" -}}
app.kubernetes.io/name: mariadb
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: primary
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "wordpress.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "wordpress.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper WordPress image name
*/}}
{{- define "wordpress.image" -}}
{{- printf "%s:%s" .Values.wordpress.image.repository .Values.wordpress.image.tag }}
{{- end }}

{{/*
Return the proper MariaDB image name
*/}}
{{- define "wordpress.mariadb.image" -}}
{{- printf "%s:%s" .Values.mariadb.image.repository .Values.mariadb.image.tag }}
{{- end }}

{{/*
Return the MariaDB Hostname
*/}}
{{- define "wordpress.databaseHost" -}}
{{- if .Values.mariadb.enabled }}
    {{- printf "%s-mariadb" (include "wordpress.fullname" .) -}}
{{- else }}
    {{- printf "%s" .Values.externalDatabase.host -}}
{{- end }}
{{- end }}

{{/*
Return the MariaDB Port
*/}}
{{- define "wordpress.databasePort" -}}
{{- if .Values.mariadb.enabled }}
    {{- printf "3306" -}}
{{- else }}
    {{- printf "%d" (.Values.externalDatabase.port | int ) -}}
{{- end }}
{{- end }}

{{/*
Return the MariaDB Database Name
*/}}
{{- define "wordpress.databaseName" -}}
{{- if .Values.mariadb.enabled }}
    {{- printf "%s" .Values.mariadb.auth.database -}}
{{- else }}
    {{- printf "%s" .Values.externalDatabase.database -}}
{{- end }}
{{- end }}

{{/*
Return the MariaDB User
*/}}
{{- define "wordpress.databaseUser" -}}
{{- if .Values.mariadb.enabled }}
    {{- printf "%s" .Values.mariadb.auth.username -}}
{{- else }}
    {{- printf "%s" .Values.externalDatabase.user -}}
{{- end }}
{{- end }}

{{/*
Return the MariaDB Secret Name
*/}}
{{- define "wordpress.databaseSecretName" -}}
{{- if .Values.mariadb.auth.existingSecret }}
    {{- printf "%s" .Values.mariadb.auth.existingSecret -}}
{{- else }}
    {{- printf "%s-mariadb" (include "wordpress.fullname" .) -}}
{{- end }}
{{- end }}
