#!/usr/bin/env bash

set -e

KUBE_ENDPOINT="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"
KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
BOTTLEDNS_HOSTS='/etc/bottledns.hosts'
DNSMASQ_CONF='/etc/dnsmasq.conf'
BOTTLEDNS_NAP_TIME=120

function curl_k8s {
  local path=$1
  curl -s --header "Authorization: Bearer ${KUBE_TOKEN}" --insecure "${KUBE_ENDPOINT}/${path}"
}

function get_all_ingress {
  curl_k8s "apis/networking.k8s.io/v1/ingresses"
}

function generate_config {
  jq -r \
    '.items[] | "\(.status.loadBalancer.ingress | map(.ip)[]) \(.spec.rules | map(.host)[])"' \
  <<< "$(get_all_ingress)" | sort
}

printf '%s\n' 'Starting dnsmasq'
dnsmasq -C "$DNSMASQ_CONF"

while true; do
  current_hash=$(md5sum "$BOTTLEDNS_HOSTS")
  generate_config > "$BOTTLEDNS_HOSTS"

  if ! md5sum -c <<< "$current_hash" &>/dev/null; then
    printf '%s\n' 'Reloading custom hosts due to change'
    pkill -SIGHUP dnsmasq
  fi

  # Needed so that we can be interupted by SIGHUP
  sleep "$BOTTLEDNS_NAP_TIME" &
  wait $!

done
