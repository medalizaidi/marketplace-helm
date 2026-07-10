{{/*
Full image reference for an app.
Usage: {{ include "marketplace.image" (dict "root" $ "name" "configserver") }}
*/}}
{{- define "marketplace.image" -}}
{{ .root.Values.dockerhubUser }}/{{ .name }}:{{ .root.Values.imageTag }}
{{- end -}}
